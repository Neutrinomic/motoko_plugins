# Integrated CBOR measurements

The audited SDK/compiler change produces five further CBOR instruction reductions: four array decodes and one partial-array failure. The other 18 plugin workloads and every measured allocation count are unchanged from the audited CBOR candidate on `f1ccbba5e`. All 23 integrated plugin workloads still improve instructions and allocation over the original plugin baseline `093957a`.

This report measures canonical compiler `c320bf90d0b63a058b5de2c41a42c96e8b82243f` and its matching canonical CBOR package. The compiler binary SHA-256 is `722ba089cc3f6fb7710423363c3adc55d0af9f841eaa5a283e97eb08f3c8335c`; it differs from the isolated SDK build because the build paths differ. CBOR production source and Rust runtime are identical to the audited candidate. [build.json](build.json) records the compiler, package, and complete source hashes.

The three stages are original plugin sources `093957a` on `f1ccbba5e`, audited CBOR candidate on `f1ccbba5e`, and the integrated candidate on `c320bf90d`. Comparisons against the original baseline include both CBOR and SDK improvements; comparisons against the audited candidate isolate the compiler/SDK integration on identical CBOR source.

## Incremental SDK effect

These are all five changed workloads. Each count is identical across three fresh-canister trials. Allocated bytes are unchanged from the audited candidate in all 23 workloads; no measured plugin call reclaimed memory. Full values for every unchanged workload and native phase are in [comparison.csv](comparison.csv).

| Workload | Audited f1 instructions | Integrated instructions | Change | Allocated bytes |
|---|---:|---:|---:|---:|
| records-1024-decode | 7,334,513 | 7,324,274 | -0.1396% | 173,128 |
| bools-4096-decode | 1,357,625 | 1,316,666 | -3.0170% | 33,168 |
| options-256-decode | 333,398 | 330,839 | -0.7676% | 5,184 |
| unicode-256-decode | 289,177 | 286,618 | -0.8849% | 12,688 |
| nested-index-error | 13,772 | 13,649 | -0.8931% | 1,720 |

The 18 unchanged plugin cases comprise all ten encoders, record/Blob/empty-record/scalar/wide-record/variant decoders, and the two long-key errors. No measured regression is omitted. The matched CBOR suite covers empty records but does not include empty arrays. The separate [SDK tabulation microbenchmark](../../sdk/README.md) records a one-instruction empty-array increase (561 → 562); that is outside these CBOR measurements.

## Original baseline through integration

| Workload | Original instructions | Audited f1 instructions | Integrated instructions | Change vs original | Original → integrated allocated bytes |
|---|---:|---:|---:|---:|---:|
| record-encode | 11,260 | 8,638 | 8,638 | -23.29% | 784 → 760 |
| record-decode | 11,612 | 8,797 | 8,797 | -24.24% | 1,272 → 1,248 |
| records-1024-encode | 8,409,156 | 5,395,241 | 5,395,241 | -35.84% | 174,224 → 174,160 |
| records-1024-decode | 10,577,700 | 7,334,513 | 7,324,274 | -30.76% | 173,192 → 173,128 |
| blob-64k-encode | 133,973 | 133,925 | 133,925 | -0.04% | 131,480 → 131,456 |
| blob-64k-decode | 67,174 | 67,115 | 67,115 | -0.09% | 65,872 → 65,848 |

## Fresh native comparison

Each cell shows **instructions / allocated bytes**. All four implementations use the same actor, compiler, typed inputs and wire semantics. Timed native paths include tree adapters, required Candid bridges, Result unwrapping and Blob conversion. All 18 native phase counts are unchanged from the f1 reports; they were measured again on the integrated compiler.

| Workload | serde 3.5.0 | serde-core 0.2.1 | cbor 4.1.0 | Integrated plugin |
|---|---:|---:|---:|---:|
| record-encode | 226,209 / 18,032 | 269,622 / 21,312 | 98,350 / 4,568 | 8,638 / 760 |
| record-decode | 452,201 / 49,560 | 546,055 / 37,384 | 188,248 / 13,352 | 8,797 / 1,248 |
| records-1024-encode | 82,729,674 / 6,041,088 | 91,466,776 / 6,039,896 | 49,934,053 / 2,452,232 | 5,395,241 / 174,160 |
| records-1024-decode | 286,327,797 / 22,644,936 | 309,636,040 / 20,164,416 | 152,527,112 / 11,545,504 | 7,324,274 / 173,128 |
| blob-64k-encode | 119,759,518 / 6,598,376 | 119,211,844 / 6,599,224 | 64,977,425 / 1,676,112 | 133,925 / 131,456 |
| blob-64k-decode | 204,734,570 / 9,455,408 | 223,952,628 / 8,142,752 | 74,088,272 / 1,145,048 | 67,115 / 65,848 |

## Validation and reproduction

[core.json](core.json), [edges.json](edges.json), and [errors.json](errors.json) contain all 123 integrated samples. The 41 phase rows each have three stable trials, zero failed measurements, identical outputs across all three stages, and matching actor, manifest and runner hashes. The [archive-only summarizer](summarize.py) regenerates `comparison.csv` using Python's standard library; independent CI validation ran it in a temporary copy and reproduced the exact saved CSV bytes.

The same independent oracles are retained: Python `cbor2@6.1.5` decodes successful encoder outputs; edge outputs also equal its canonical bytes exactly. Decoder inputs come from cbor2 and retained typed values are compared outside timing. The three malformed inputs are independently rejected by cbor2, and actor queries verify the complete error kind, message, path and offset. Native dependency resolution checks every file against the existing 20-alias/18-package Mops lock.

[provenance.json](provenance.json) records all new artifact hashes and immutable old-archive hashes. [pre-ready-sha256.json](pre-ready-sha256.json) snapshots those archives and harnesses before integration; they remain unchanged. The input sources and manifests are the existing [core actor](../../../codec-comparison/cbor/main.mo), [edge actor](../../cbor/edges/main.mo), and [error actor](../../cbor/errors/main.mo), with `cases.json` alongside each. Compiled actors and the exact package snapshot remain under `_build/opt-cbor-integrated/{core,edges,errors,package}`.

The complete compile/run sequence is in [run.sh](run.sh). It uses the existing canonical package, verifies compiler/package/source hashes before compiling, and runs the unchanged PocketIC harness with three trials and explicit SDK/canonicalizer/Python paths. It never rebuilds the compiler or packages. From the compiler checkout's Nix shell, replay with:

```sh
cd /srv/shared/code/motoko_experiments/plugins
bash benchmarks/results/optimization-round/integrated/cbor/run.sh --ready
python3 benchmarks/results/optimization-round/integrated/cbor/summarize.py
```

The scoped [integration audit](audit.md) checks the final hashes, trials, independent validations, and retained safety conclusions. Original f1 results remain in [the frozen-compiler report](../../cbor/README.md).
