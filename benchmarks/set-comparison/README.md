# Ordered Set comparisons with Ash

The generator compares `mo:core/Set` with `mo:fast/Set`, and
`mo:core/pure/Set` with `mo:fast/pure/Set`, using Core 2.5.0. Generic calls
use the same `Nat` comparison function. Native cases call the plugins'
`Nat` helpers without a comparator callback.
Keys in this matrix are small natural numbers; the results do not establish
the same speedups for text, blobs, records, or large natural numbers.
See the [recorded comparison tables](RESULTS.md) and
[raw evidence](../results/set-comparison/README.md).

```sh
mkdir -p _build/map-deps
cp benchmarks/results/pure-map/dependencies/mops.toml _build/map-deps/
cp benchmarks/results/pure-map/dependencies/mops.lock _build/map-deps/
(cd _build/map-deps && mops install --no-toolchain --lock check)
python3 benchmarks/generate-set-comparison.py \
  --out _build/set-comparison --deps _build/map-deps
python3 benchmarks/set-comparison/run.py \
  --out _build/set-comparison --archive _build/set-evidence \
  --motoko ../motoko_sha --ash /path/to/ash \
  --ash-moc-binary "$HOME/.local/lib/motoko-compute/moc" \
  --deps _build/map-deps --trials 3
python3 benchmarks/set-comparison/summarize.py _build/set-evidence
```

Build `dist/mutable-set` and `dist/pure-set` first with the current compiler,
and install that compiler with the managed Ash compiler wrapper. The
dependency directory must contain a
Mops lockfile and `.mops/core@2.5.0`. The runner checks the installed compiler
binary against native build manifests and verifies all locked Core source
hashes. Each Ash configuration runs serially in a fresh PocketIC instance.
Each operation has its own canister and PocketIC instance, so allocator and
collector history also start independently. Archive directories must be new;
a failed run remains marked incomplete.

Default sizes are 1,000, 10,000, and 100,000. A fixed Fisher–Yates shuffle controls
insertion order. Each public update builds fresh inputs, calls `Test.test`
around the operation, and then checks the result. Point operations use 32
distinct probes from the beginning of that shuffle; missing keys add the set
size to those probes. Input and output contents are checked after measurement.
Iteration retains a checked element count and a checksum reduced modulo
1,000,003, avoiding artificial large-integer allocations in the consumer loop.
Union/intersection
use 50% overlap and verify the complete output and unchanged inputs. Pure
point updates also verify the original version is still intact.

Construction measures the complete build, excluding creation of the shuffled
input array. Other cases exclude setup. Mutation cases start independently;
one implementation never inherits the effects of another measured phase.
The measurements include common Ash harness overhead and any collection
within the measured closure.

Raw `totalAllocatedBytes` is the cumulative allocation delta, including
temporary garbage; it is not retained memory. Ash also records `heapBytes`
(a nonnegative heap delta) and `maxLiveBytes` (a change in the runtime's
historical live-size high-water mark). Neither is labelled peak operation
memory. The summary reports instructions and cumulative allocated bytes per
operation; exact totals remain in the raw Ash JSON files.

The archive includes raw logs/metrics, emitted Wasm hashes, generated and
plugin sources, native build manifests, source hashes, and exact commands.
Ash's commit, dirty status, source hashes, and generated Motoko metrics module
are retained; unrelated local Ash source is not copied. Exact reconstruction
of a dirty local Ash checkout requires files matching those source hashes.
Source and binary inputs are rechecked after every configuration so concurrent
edits cannot silently contaminate final evidence. `summarize.py` verifies the
archive manifest and each summary sample against its raw Ash record.
