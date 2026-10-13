Prepared-key reports use `crypto-prepared-v1` evidence and exactly three fresh-canister trials per case:

```sh
python3 benchmarks/crypto/prepared/summarize.py \
  --run benchmarks/crypto/prepared/results/prepared-example \
  --json /tmp/prepared-report.json --markdown /tmp/prepared-report.md
python3 -m unittest discover -s benchmarks/crypto/prepared -p test_summarize.py
```

Repeat `--run` to combine disjoint cohorts. Each directory must contain `build.json`, `results.json`, frozen inputs and compiled Wasm. Reports never overwrite existing paths. Every supplied case is validated; the utility rejects failed, incomplete, duplicated or mismatched evidence instead of filtering it away.

A comparison group must contain one `direct`, one `prepare` and one `prepared` case with `reuse=1`. The compiler, both RTS artifacts, PocketIC binary, runner, loaded runner dependencies, Motoko dependency pins and frozen `mo:fast` package sources must match within that group. Each frozen input, source, fixture and Wasm artifact is checked against its recorded hash. Plugin compiler/runtime artifacts and their source pins must also be identical: older-plugin baselines belong in a separate comparison. The schemes, profiles, operations, fixture IDs, fixture file hashes, plugins and expected output must match. Motoko benchmark source files intentionally differ between modes.

Preparation's `bytesResult` exercises its newly prepared key **outside the timed interval** to return the same independent operation oracle as direct and prepared calls. Preparation and prepared calls must declare the same byte payload; direct calls may report zero. This payload excludes object headers and other managed heap bookkeeping.

The report shows preparation separately from per-call direct and prepared costs. Each instruction, allocation and sampled memory figure is a median with its full three-trial range. Allocation measures bytes allocated during the timed operation, including transient allocations; it is not retained memory. Wasm size is the complete canister artifact.

Given median preparation cost `P`, direct cost `D` and prepared cost `H`, the report models `N×D` against `P+N×H` for `N=1,2,10,100`. These are arithmetic projections from the **reuse=1** measurements, not observed batch costs. If `H < D`, the first integer reuse count with a strict instruction saving is `P // (D-H) + 1`; equality is not counted as a saving. Otherwise there is no crossover. Integer arithmetic avoids rounding at large counter values. Optional measured cases with `reuse>1` appear separately as whole-batch costs and never replace the inputs to that model.

Optional `cold` cases measure one factory call plus `N` operations in the same timed interval. They appear with the actual batch observations, including when `N=1`, and never affect the per-call model or break-even calculation. They retain the same fixture, oracle and prepared payload checks as other comparable modes.

An optional `control` group contains exactly one standalone operation measurement, such as direct public-key derivation or key generation. It cannot mix with a comparison triplet or another control case. Controls appear separately in both JSON and Markdown, with no derived speedup, model or break-even claim.

Memory snapshots are queried before the run, after its message and after four further GC increments. They show sampled occupied heap and Wasm capacity, **not peaks or retained live data**. Message-end GC may occur before the second snapshot; four increments need not complete collection. Setup can retain a prepared key, and the result remains reachable for its oracle check. The JSON preserves all phases and cumulative counters so readers can inspect the context without interpreting a snapshot difference as a precise object size.

The harness is a reproducibility check, not a proof that fixtures represent equivalent application workloads. A review must still confirm that sources measure the intended operation, preparation is outside the hot-call interval, fixtures come from independent vectors, and the declared payload matches the implementation.

Completed stage source snapshots can be deduplicated without consulting current working sources:

```sh
python3 benchmarks/crypto/prepared/pack-sources.py
python3 benchmarks/crypto/prepared/verify-evidence.py
python3 benchmarks/crypto/prepared/restore-sources.py \
  --stage prepared-example --out /tmp/prepared-example-sources
python3 benchmarks/crypto/prepared/verify-evidence.py \
  --stage prepared-example --restored /tmp/prepared-example-sources
```

The `crypto-prepared-source-store-v1` archive and index live beside these scripts; immutable `source-map.json` files and build/result metadata stay under `prepared/results/<stage>/`. Pack only completed, inactive stages; `--stage` may be repeated to select an explicit cohort. Frozen bytes and modes come from each stage's original archive or matching input pins. Compiler/toolchain binaries, compiled plugin artifacts and generated directories are excluded from this source store, while their existing hashes remain in build metadata. Commit the source store, index, maps and stage metadata; keep generated inputs, binaries and duplicate per-stage source archives local. Restoration requires a new directory and reconstructs exact source bytes and modes. Verification checks available local binary artifacts too, but missing binaries are not reconstructed and source integrity alone does not certify successful performance measurements.
