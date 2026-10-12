# Crypto optimization round two

The [complete public API table](../../../benchmark_crypto.md) compares pure Motoko with the final plugins. The [optimization report](RESULTS.md) compares the delivered plugins with retained round-two changes. [API measurement evidence](api-measurements.json) retains all workload sizes and every table cell's source stage.

The final table covers 155 callables and 181 workload rows: 181 plugin fixtures and 166 closest pure Motoko fixtures passed three trials each. The 140 paired callables include explicitly marked differences in nonce preparation, mutable state, wire formats and caching; 15 callables have no correct operation in the pinned packages. The [final verification ledger](final-verification.json) checks all 57 production source/artifact pins and preservation of all 1,242 round-one files.

This round compares new candidates with the delivered implementation frozen in `_build/crypto-optimization-round2/baseline`. Round-one sources, measurements and reports remain unchanged. Every stage uses the original three-trial protocol: a fresh canister for every trial, setup outside measurement, exact independently derived output checks outside measurement, IC instruction counts, cumulative allocations and whole-canister Wasm bytes.

Generate additional hash boundary, streaming and BLAKE3 XOF workloads:

```sh
python3 benchmarks/crypto/round2/generate-hashes.py
```

Build and measure a delivered baseline cohort:

```sh
python3 benchmarks/crypto/round2/run-stage.py --stage sha512-baseline --manifest benchmarks/crypto/round2/hash-cases.json --family '^sha512$'
```

Measure a private, built candidate with the identical fixtures:

```sh
python3 benchmarks/crypto/round2/run-stage.py --stage sha512-candidate --manifest benchmarks/crypto/round2/hash-cases.json --family '^sha512$' --root /absolute/private/candidate --plugin sha512
```

Stages are immutable and stored under `benchmarks/crypto/results/round2-<stage>`. Choose a new stage name for every build. All unspecified plugins come from the frozen delivered baseline; `--plugin` is repeatable for composed candidates. The public Motoko package comes from `--root`. Existing fixtures can be selected from the default `all-cases.json`; additional fixtures must have source paths relative to `benchmarks/crypto`. Each family owns a separate directory to prevent generator races.

Compare only complete, matching cohorts:

```sh
python3 benchmarks/crypto/round2/compare.py --baseline round2-sha512-baseline --candidate round2-sha512-candidate --out benchmarks/crypto/round2/comparisons/sha512-candidate.json
```

Comparison verifies identical fixture source and expected output, compiler/RTS/PocketIC/runner identities, archived Wasm/source hashes and at least three uniquely indexed successful trials. It records every candidate case, including regressions, allocation changes and code-size tradeoffs. Medians and ranges are retained. A candidate may select a subset of a broader baseline, but no candidate case can be omitted from its comparison.

The public API table additionally requires exactly three trials and explicit final plugin cohorts. `fingerprint-final.py` verifies every frozen public module and plugin artifact against the final shared production build; `render-api.py` rejects plugin cells from any other stage. Pure Motoko adapters have separately checked output oracles and include validation where their public byte-oriented contracts require it.

`pack-sources.py` creates a separate round-two content-addressed source archive without modifying round-one evidence. `restore-sources.py --stage round2-... --out /new/directory` reconstructs its exact source snapshot. Early launcher bodies are retained under `source-versions/` and checked against recorded launcher hashes. The actual compiler input actors, expected outputs, build script and measurement runner were frozen at every build; supplementary late oracle captures are labelled explicitly.

Round-two source packing excludes generated `_out` directories and binary object/Wasm files. The preserved round-one archive contains 13 historical test Wasm outputs that its earlier source-only description did not exclude; those files do not affect measurements or selected source hashes. Artifact hashes and locally frozen binaries remain available separately.

Verify retained files with `python3 benchmarks/crypto/round2/verify-evidence.py`. To additionally check restoration, pass `--restored /path/to/restored/round2-api-final` after using `restore-sources.py` for that stage. The final archive contains 87 stage maps and 1,915 distinct source contents in approximately 7.2 MB.
