# HistoryRing: additional measured optimization round

The final plugin uses fewer instructions for append, overwrite, lookup, paging,
and partial drops than the **previously delivered plugin**. This baseline is
generator `26762844…`, not the original implementation before round one.
The accepted generator is `30b20a89…`; no compiler, SDK, public module, or ABI
change was needed. [Candidate decisions and regressions](OPTIMIZATION.md) preserve
the four cumulative experiments.

Both final builds completed **126 cases × three trials** at capacities
0, 1, 64, 65, 129, 1,000, and 100,000. Each sample uses fresh canisters.
The table reports median instruction counts; allocation means bytes newly
allocated inside the measured loop, not retained heap. Pages return up to the
stated length. Full results include quarter/full/zero/wrapped drops, one-entry
and 64-entry pages, and all small-capacity cases in
[final-comparison.csv](results/final-comparison.csv).

| Capacity | Operation | Count | Core instructions | Previous plugin | Final plugin | Plugin reduction | Core / final allocation |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1,000 | append | 1,000 | 1,355,240 | 1,220,398 | 1,146,398 | 6.06% | 96,000 / 8,944 B |
| 1,000 | overwrite | 1,024 | 1,901,859 | 1,713,443 | 1,150,243 | 32.87% | 98,304 / 0 B |
| 1,000 | get_middle | 10 | 1,329,804 | 9,546 | 8,806 | 7.75% | 960 / 0 B |
| 1,000 | drop_half | 500 | 285,553 | 64,206 | 4,221 | 93.43% | 0 / 0 B |
| 1,000 | drop_wrapped_half | 500 | 285,553 | 64,250 | 2,265 | 96.47% | 0 / 0 B |
| 1,000 | pop_all | 1,000 | 640,397 | 673,581 | 673,581 | 0.00% | 0 / 24 B |
| 1,000 | page_tail_32 | 10 | 2,671,942 | 67,514 | 50,314 | 25.48% | 4,160 / 2,800 B |
| 1,000 | page_tail_1024 | 10 | 3,175,256 | 1,790,508 | 1,240,078 | 30.74% | 81,600 / 80,240 B |
| 100,000 | append | 100,000 | 135,500,240 | 121,629,718 | 114,229,718 | 6.08% | 9,600,000 / 866,936 B |
| 100,000 | overwrite | 100,000 | 185,700,291 | 167,300,291 | 112,300,291 | 32.88% | 9,600,000 / 0 B |
| 100,000 | get_middle | 10 | 132,009,804 | 9,546 | 8,806 | 7.75% | 960 / 0 B |
| 100,000 | drop_half | 50,000 | 28,500,553 | 6,335,262 | 90,801 | 98.57% | 0 / 0 B |
| 100,000 | drop_wrapped_half | 50,000 | 28,500,553 | 6,335,262 | 90,939 | 98.56% | 0 / 0 B |
| 100,000 | pop_all | 100,000 | 64,000,397 | 67,275,837 | 67,275,837 | 0.00% | 0 / 24 B |
| 100,000 | page_tail_32 | 10 | 264,031,942 | 67,514 | 50,314 | 25.48% | 4,160 / 2,800 B |
| 100,000 | page_tail_1024 | 10 | 264,547,782 | 1,833,274 | 1,269,994 | 30.73% | 83,520 / 82,160 B |

Core 2.6.2 uses a linked Queue. Its page baseline deliberately follows the
forward-cursor pattern from Takt Trace; these timings are **not a comparison
against the best suffix-only Core implementation**. `reverseValues` can avoid
scanning the prefix for suffix pages, and `peekBack` is O(1) for one entry.
Indexed lookup and pages also benefit from a different data structure, so the
large Core ratios must not be attributed to native code alone. Core full-drop
rows use repeated popFront; callers can instead use clear when removing every
entry. Capacity-zero append-and-trim can likewise be bypassed when retention
is disabled. Neither special case is headline speedup evidence.

There are small regressions: nonempty one-entry pages add 16–23 instructions
per call, nonzero full drops add 19, and capacity-zero appends add one.
Pop performance is unchanged and remains slower than Core in this matrix.
Tiny first appends and empty pages also remain slower than Core. Empty drops
now allocate zero bytes instead of 24; nonempty bulk operations keep their
previous allocation costs.

## Correctness and retention

After every timed call and memory sample, an independent query checks every
retained value against its exact absolute sequence, checks iterator length, and
asserts that occupied physical plugin slots equal logical size. This catches
wrong retained order and stale payload references after wrapped/chunk drops.
Checksums, sequence bounds, operation counts, archive hashes, and complete trial
sets are also checked by [verify_semantics.py](verify_semantics.py). Core costs
and allocation match exactly between final baseline and final candidate.

The separate 64-batch retention probe appends 65,536 fresh 1 KiB Blobs at
capacity 1,024. All nonempty checkpoints retain exactly 1,024 payloads /
1,048,576 bytes.
After a 512-entry partial drop and eight GC increments, every remaining byte
is validated and the plugin has exactly 512 occupied slots / 524,288 payload
bytes. Clearing then leaves zero directory entries, chunks, occupied slots, or
payload bytes. Core byte checksums and sequence results agree.

| After 64 batches | Core Queue | Previous plugin | Final plugin |
|---|---:|---:|---:|
| Retained entries | 1,024 | 1,024 | 1,024 |
| Total allocation since install (B) | 619,910,344 | 613,645,336 | 613,645,336 |
| Reclaimed by GC (B) | 582,878,592 | 582,543,544 | 582,543,544 |
| Current managed heap (B) | 37,031,752 | 31,101,792 | 31,101,792 |
| Wasm memory high-water (B) | 268,435,456 | 268,435,456 | 268,435,456 |
| Historical post-GC heap high-water (B) | 63,481,136 | 66,284,608 | 66,284,608 |

Payload construction dominates total allocation in this probe. Current heap
includes uncollected partition garbage; fixed GC increments do not establish
exact live bytes. Wasm memory and `maxLive` are historical high-water counters.
The occupied-slot/payload-byte checks establish retention independently of
GC timing. Partial drops retain the directory high-water length; clear releases
it. Raw `storage` fields in Core rows inspect its unused plugin ring and must
not be interpreted as Core storage usage.

Independent published-build validation passed four native fixtures, eight Ash
tests, and two upgrades, including 405 drop/refill cases, page/chunk boundaries,
large sequences, nullable payloads, and mutation during incremental GC.
See [validation evidence](../../../packages/fast/tests/ash/coverage/HistoryRing-validation-round2.json)
and the [harness audit](HARNESS_AUDIT.md). The benchmark oracle complements those
model tests; additive timed checksums alone do not certify returned page/pop
order.

## Build provenance and reproduction

Compiler `92b1bdecb`, the original release RTS, Core 2.6.2, ABI 1, PocketIC 10,
and the Ash transport are pinned by hashes. Source/module/compiler/harness
paths remain fixed across the final comparison; only plugin source/artifacts
and emitted Wasm differ. Build inputs are checked before/after compilation,
and archived plugin sources match their build manifests. The runner validates
its own hash and the exact archived Wasm before installation.

The measured private native plugin is `71ca3734…`; the published native plugin
is `f71c15ec…`. They share generator `30b20a89…` and emit **byte-identical**
benchmark Wasm `1d89bd04…`. [Publication evidence](results/published-equivalence/equivalence.json)
archives both identities rather than treating the private native artifact as
installed. [Final results](results/final/results.json) and
[matched current-plugin baseline](results/final-baseline/results.json) retain
all raw samples, memory checkpoints, sources, artifacts, and build commands.

Measurement includes dispatch, counters, and loop/checksum overhead; setup,
reply encoding, end-of-message GC, and the exact-state oracle are excluded.
No measured call reclaimed memory synchronously. Wrapping Nat32 checksums avoid
bigint allocation at 100,000 entries. Timed sequence numbers stay compact;
large-sequence correctness is tested separately.

To measure an already built plugin repository in a new immutable stage:

```sh
python3 benchmarks/history-ring/round2/build.py --stage my-run --plugin-root .
bun benchmarks/history-ring/round2/run.mjs --stage my-run --trials 3 --sizes 0,1,64,65,129,1000,100000 --churn yes
python3 benchmarks/history-ring/round2/verify_semantics.py benchmarks/history-ring/round2/results/my-run
```

`write_report.py` regenerates this summary and the final comparison CSV from
the validated immutable `final-baseline` and `final` reports.
