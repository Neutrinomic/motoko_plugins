# Candid size estimation

`CandidX.estimateSize(value)` avoids creating a Candid Blob when only an
admission estimate is needed. These PocketIC measurements compare it with
ordinary `(to_candid(value)).size()` using the plugin PR compiler at
`92b1bdecbc7bc67fd51ad226f8d147d15494fc09`, without the discarded compiler
size optimization. This is an approximate-size comparison, not an encoding
throughput comparison: the estimator returns a conservative bound instead of
exact bytes.

Each entry is the median of three fresh-canister trials. All three trials
were identical in instruction counts, allocations, and returned sizes.

| Value | Native instructions | Estimate instructions | Instruction ratio | Native allocated bytes | Exact → estimated bytes |
|---|---:|---:|---:|---:|---:|
| `Nat` 42 | 1,190 | 382 | 3.12× | 88 | 8 → 28 |
| Fourcans-shaped Fanout request | 10,542 | 2,673 | 3.94× | 952 | 439 → 731 |
| Blob, 1 KiB | 3,436 | 455 | 7.55× | 2,152 | 1,035 → 1,055 |
| Blob, 1 MiB | 2,098,590 | 481 | 4,362.97× | 2,097,256 | 1,048,588 → 1,048,607 |
| Fixed-width records, 0 | 1,363 | 533 | 2.56× | 152 | 33 → 81 |
| Fixed-width records, 1,024 | 831,905 | 559 | 1,488.20× | 43,160 | 21,538 → 21,585 |
| Fixed-width records, 10,000 | 8,111,467 | 585 | 13,865.76× | 420,152 | 210,034 → 210,081 |
| Text array, 1,024 | 328,822 | 79,477 | 4.14× | 24,664 | 12,293 → 21,533 |
| Big `Nat` array, 128 | 1,749,747 | 35,091 | 49.86× | 23,032 | 5,926 → 18,851 |
| Recursive tree, depth 64 | 41,905 | 15,524 | 2.70× | 1,432 | 677 → 1,306 |
| `Int` −2^4096 | 684,646 | 1,038 | 659.58× | 6,104 | 593 → 2,360 |

**Every estimate allocated zero Motoko heap bytes.** Every returned bound
was checked against the size of an actual ordinary Candid Blob. No phase
reported synchronous reclamation. Allocation measures temporary heap
traffic, not peak heap, retained memory, or Wasm linear memory.

Large Blobs and fixed-width record arrays need only their length; they do
not require inspecting each byte or record. Text and arbitrary-size integer
arrays still require visiting their elements. The recursive case visits
both branches. Small instruction differences between length-only cases
include selecting the benchmark case; counts have no overhead subtraction.

The Fanout request mirrors the public fields of fourcans' `Fanout.Request`,
with a 32-byte topic, a 256-byte prepared request, three block IDs, four
anonymous principals, and realistic timestamps. Fixed records contain
`Nat64`, `Int32`, `Bool`, and `Float`. Big Nats range from 257 to 384 bits.
The negative integer is `-(2 ** 4096)`. These are focused examples, not
end-to-end fourcans throughput measurements.

The estimate intentionally includes slack. In this sample it is 1.67× the
exact Fanout size and up to 3.98× for the large negative integer. Near a
limit, conservative admission can reject a value that exact encoding would
accept. The API's work/depth/size sentinel is documented in
[CandidX.mo](../../packages/fast/src/CandidX.mo); sentinel behavior is covered
by the module correctness tests, not used as a successful measurement here.

## Reproduce

Build the CandidX plugin against the same compiler checkout first, following
the repository build instructions. Supply an explicit compiler bundle with
`moc`, `mo-rts.wasm`, and `mo-rts-debug.wasm`:

```sh
python3 benchmarks/candid-size/build.py --bundle /path/to/motoko-bundle
bun benchmarks/candid-size/run.mjs --ash /path/to/ash --trials 3
```

The runner reuses Ash's existing PocketIC transport and installed Candid
dependencies. As in Ash, the PocketIC executable is
`~/.local/bin/pocket-ic`. Recorded versions are PocketIC 10.0.0, Bun 1.2.13,
and `@dfinity/pic` 0.16.1. It creates an application subnet with production
instruction limits and default deterministic time slicing.

Input construction happens in a separate update before measurements. Each
phase runs four explicit GC increments before its single measured call.
Native/estimate order alternates across trials. Counts come from
`performanceCounter(0)`, `rts_total_allocation`, and `rts_reclaimed`; they
include case dispatch, counter and result assignment overhead, but exclude
reply construction and end-of-message GC. The exact-size phase is also the
independent actual-Blob oracle; the estimator never calls it. The runner
checks bounds, zero estimate allocations, zero synchronous reclamation, and
unchanged build inputs before accepting results. Canisters are stopped
after each trial and the entire PocketIC server is discarded at the end.

[main.mo](main.mo), [run.mjs](run.mjs), and [build.py](build.py) are the complete
benchmark harness. [results.json](results.json) contains every raw sample;
[build.json](build.json) records commands, explicit RTS paths, compiler/plugin
hashes, and source hashes. Compiled Wasm remains in ignored `_out/`.
