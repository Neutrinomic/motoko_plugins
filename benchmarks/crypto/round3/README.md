# Signature plugins: round three

This protocol measures new signature plugins and optimization candidates against the delivered plugins pinned in [baseline.json](baseline.json). Earlier crypto rounds and their measurement files remain unchanged.

Every workload runs on **three fresh canisters**. Setup and four forced GC increments precede the measured operation. The operation records IC instructions, cumulative allocated bytes and reclaimed bytes; output conversion and exact oracle checks execute outside that interval. Cases must provide an independently derived `expected_hex`, including deterministic signing randomness where applicable. Key generation, public-key derivation, signing and verification are separate workloads. Compare complete public calls, and label prepared-input or prehash cases explicitly.

Fixtures generated with `round3/common.py` can pass `memory_metrics=True` to `actor` and set `memory_metrics: true` in their manifest entry. This adds an untimed `memory()` query. The runner records three snapshots:

| Snapshot | Meaning |
|---|---|
| `before_run` | After setup and its four GC increments |
| `after_run` | After the operation message, including any end-of-message collection |
| `after_gc` | After four additional forced GC increments |

Each contains occupied heap, Wasm memory capacity, cumulative allocation and reclaimed bytes. These are **sampled occupancy and capacity**, not true peak heap or retained live data. Four increments do not guarantee a completed collection. The operation result remains reachable throughout the snapshots. Memory queries and extra GC calls do not occur inside the measured interval. Old fixtures without the flag retain the instruction/allocation protocol and have no memory snapshots.

The launcher checks every frozen baseline file, the installed compiler against the frozen compiler hash, plugin source/artifact provenance and locked Motoko dependencies. The installed compiler executable preserves its loader path; release/debug RTS come from the frozen baseline. Each stage copies its input sources, all round-three generator/oracle resources, public package, plugin artifacts and toolchain before building. The frozen runner executes those immutable artifacts. No dependency resolution occurs during measurement.

```sh
# Delivered baseline, with identical newly instrumented fixtures.
python3 benchmarks/crypto/round3/run-stage.py \
  --stage curves-baseline \
  --manifest benchmarks/crypto/round3/control-cases.json

# Candidate secp256k1 build; all other plugin artifacts use the baseline.
python3 benchmarks/crypto/round3/run-stage.py \
  --stage curves-candidate \
  --manifest benchmarks/crypto/round3/control-cases.json \
  --root /absolute/candidate/root --plugin secp256k1

python3 benchmarks/crypto/round3/compare.py \
  --baseline round3-curves-baseline --candidate round3-curves-candidate \
  --out benchmarks/crypto/round3/comparisons/curves-candidate.json
```

`--plugin` is repeatable; `--root` also supplies the public `mo:fast` package. New plugins therefore need explicit overrides. The default baseline is `/srv/shared/code/motoko_experiments/plugins/_build/signature-round3/baseline`; `--baseline` relocates an identical snapshot. `--family`, `--filter` and `--implementation` select workloads. `--include-mops` includes pure Motoko fixtures. Fixture `source` paths are relative to `benchmarks/crypto`. `--compile-only` separates compilation from PocketIC scheduling; subsequently invoke the stage's frozen `inputs/benchmarks/crypto/round3/run.mjs` with `--build`, `--out` and `--trials 3`.

Stages reside under `benchmarks/crypto/results/round3-NAME` and cannot be overwritten. Failed stages stay intact; use a new name for another attempt. Comparison outputs also cannot be overwritten. Comparisons reject incomplete cohorts, changed input/Wasm bytes, mismatched source/oracle/toolchain/runner/dependency identities or overlapping baseline cohorts, unequal trial counts, failed oracle checks and mismatched memory instrumentation. They retain all selected candidate rows, including regressions, with median/range instruction, allocation, reclamation and optional memory values, plus total canister Wasm size. A candidate subset can match a larger baseline; `--family` explicitly narrows the reported family while validating the complete stages. New algorithms without an older plugin implementation are standalone measurements or labelled comparisons against other algorithms, not same-workload optimization speedups.

## Portable source reproduction

After all selected builds and measurements have finished, pack their exact frozen source bytes:

```sh
python3 benchmarks/crypto/round3/pack-sources.py
python3 benchmarks/crypto/round3/verify-evidence.py
python3 benchmarks/crypto/round3/restore-sources.py \
  --stage round3-controls-baseline --out /new/directory
python3 benchmarks/crypto/round3/verify-evidence.py \
  --stage round3-controls-baseline --restored /new/directory
```

The packer defaults to every `results/round3-*` build and the earlier `r3-rsa-generic-baseline` screen; repeat `--stage` to select an explicit completed cohort. Incomplete builds or missing pinned source contents fail packing. It reads only the original stage `sources.tar.gz` and frozen `inputs`, never the current production tree. New stages verify relative-path input pins; earlier screening stages verify recorded input content hashes. Each plugin's declared `source_sha256` and every compiled fixture hash must resolve within that same stage. Missing production inputs are not recovered from newer source versions.

`source-store.tar.gz` deduplicates exact source contents, including C/header/Rust/vendor sources and binary test-vector inputs. Compiler/toolchain binaries, Wasm/object artifacts and generated `_out` directories are excluded. Executable source scripts retain their permissions. Each immutable stage `source-map.json` pins its original archive and build; `source-store.json` pins every map and retained stage metadata file. The aggregate store/index may be regenerated before committing evidence; existing source maps must stay identical. Restoration requires a nonexistent destination and preserves exact bytes and file modes.

The verifier checks declared plugin inputs, source-store integrity, metadata, and any original archives or Wasm/plugin binaries still present locally. Those large binaries are not required for portable source restoration; their original hashes remain in build metadata. It reports failed or incomplete measurement results explicitly: successful source-integrity verification does not convert a failed screening experiment into a valid performance result. Use the strict comparison tool for measurement acceptance. Earlier-round stores and archives remain untouched.
