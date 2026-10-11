# CBOR second optimization round

Reusing the existing integer conversion buffer and removing one pass over its bytes reduces 1,024-element `Nat` and `Int` array decode instructions by **20.11% and 20.29%**, with **78.99% and 79.15% fewer allocated bytes**. Small integers also improve. The existing fixed-width record, Blob, and native-library comparison workloads have exactly unchanged instruction and allocation counts. These gains apply to unbounded `Nat`/`Int` decoding; encoding and fixed-width integers do not use this conversion.

The baseline is plugin source `0df5cd2d63d4b592e08c4c7a5f9d1e76fac22152`. Both versions use frozen compiler `c320bf90d0b63a058b5de2c41a42c96e8b82243f`, executable SHA-256 `722ba089cc3f6fb7710423363c3adc55d0af9f841eaa5a283e97eb08f3c8335c`. ABI remains 1. There is no SDK, compiler, public API, or canonical wire-format change.

## Changes and safety

The decoder previously replaced `Context.scalar` with a newly allocated LEB buffer for every `Nat`/`Int`. It now clears that buffer and replaces it only when its capacity is too small. This does not copy old bytes when growing an empty buffer. Sign-complement and continuation bits are emitted with each seven-bit group, removing a second complete traversal. The existing signed terminator rule is retained; only the last continuation bit needs clearing afterward. Terminal errors retain their original one-byte zero fallback.

The generated visitor immediately consumes the scratch pointer through `BigNum.of_leb128`. The compiler's short path produces an immediate managed value; the RTS long path reads every byte into a newly persisted bigint. Neither stores an input pointer in the result. Arrays, records, options and variants retain those completed values, so later integer reads can reuse the temporary buffer. Strings and Blobs separately borrow input only until the SDK copies their bytes; every integer read resets the borrowed-input selector. No parser-context pointer escapes the synchronous GC-free call.

The existing 4,096-byte magnitude check still runs before conversion, bounding the LEB buffer at 4,683 bytes. Input-dependent byte, item, nesting, numeric-range, duplicate-key and UTF-8 checks are unchanged. Error kind, message, path and offset are unchanged. No unchecked pointer accessor or output helper was introduced. Excluding tests, production code grows by four lines while removing a full per-integer pass.

## Results

All 52 phase pairs have three identical fresh-canister trials: **312 samples**, zero failures, identical retained results/encoder bytes. Eleven of 34 plugin workloads improve instructions; the other 23 are unchanged. No plugin workload regresses in instructions or allocation. All 18 native phases are unchanged. Counters include Result unwrapping, retained result assignment and counter overhead; setup and validation occur outside timing. Allocated bytes are cumulative managed plus ephemeral allocation, **not peak or live memory**. No measured plugin call reclaimed memory.

These are all changed plugin rows; [summary.csv](summary.csv) includes every unchanged plugin and native row.

| Workload | Baseline → final instructions | Change | Baseline → final allocated bytes |
|---|---:|---:|---:|
| scalars-decode | 21,476 → 20,849 | -2.92% | 1,032 → 992 |
| nat-zero-decode | 1,852 → 1,788 | -3.46% | 320 → 320 |
| int-negative-decode | 1,861 → 1,795 | -3.55% | 320 → 320 |
| big-positive-decode | 2,394,303 → 2,386,780 | -0.31% | 45,928 → 45,928 |
| big-negative-decode | 652,923 → 644,341 | -1.31% | 24,752 → 24,752 |
| nats-1024-decode | 1,475,341 → 1,178,719 | -20.11% | 41,360 → 8,688 |
| ints-1024-decode | 1,458,464 → 1,162,511 | -20.29% | 41,360 → 8,624 |
| big-ints-256-decode | 390,042,970 → 387,925,355 | -0.54% | 8,975,760 → 8,818,680 |
| mixed-scalars-256-decode | 390,668,822 → 388,482,695 | -0.56% | 9,014,672 → 8,849,400 |
| nat-negative-error | 2,714 → 2,694 | -0.74% | 504 → 504 |
| late-integer-error | 2,399,693 → 2,392,128 | -0.32% | 46,296 → 46,296 |

The unchanged empty-array decode is 1,325 instructions / 312 allocated bytes. Empty-record decode is 1,757 / 1,008. Both 4,096-bit integer arrays alternate signs; the mixed array also alternates large and small integers with Text and Blob. Much of the large-integer cost is the unchanged Motoko RTS bigint construction, which explains its smaller instruction gain.

The fresh native comparison retains the same locked `serde@3.5.0`, `serde-core@0.2.1` and `cbor@4.1.0` dependencies. For 1,024 fixed-width records, `cbor@4.1.0` encoding is 49,934,053 instructions / 2,452,232 B against plugin 5,395,241 / 174,160 B; decoding is 152,527,112 / 11,545,504 B against plugin 7,324,274 / 173,128 B. The actors include the libraries' required adapters and conversions. No new native comparison is claimed for the added unbounded-integer workloads.

## Validation and rejected experiments

All **11 Rust kernel tests and seven Motoko fixtures** pass, including source/IR/Wasm execution and forced-GC retention. The new fixture uses independently specified CBOR bytes to interleave retained big/small integers, borrowed Text/Blob, options and variants. The existing exhaustive binary16 and malformed-input tests also pass.

The independent [audit](audit.md) adds **10,632** canonical and nonpreferred integer cases, using cbor2 input plus a separate Python integer-shift implementation of signed/unsigned LEB. It covers sign/group boundaries, leading zeros, empty magnitudes and the 4,096-byte limit, including errors after scratch reuse. Its Motoko fixtures retain 106 signed integers and 53 mixed tuples through all execution engines and forced GC. [audit-oracle.py](audit-oracle.py) recreates those tests; sources, logs and hashes are under [validation](validation/).

The accepted result follows small, measured simplifications. [Reuse alone](experiments/reuse-only.json) reduced array allocation but made standalone integers about 7% slower. Passing the Vec by value was slower again. Removing the second byte pass helped, but ordinary `reserve_exact` still performed unnecessary empty-buffer growth work. Replacing an insufficient empty buffer directly removed that cost. These earlier one-trial experiments remain under [experiments](experiments/) with source patches.

Attempting reuse after a terminal error saved 32 bytes on one late error but made negative-to-Nat errors 79 instructions slower. [That version](experiments/error-reuse.json) was rejected; restoring the original one-byte error fallback is simpler and improves the final error measurement. The old pilot manifests inherited the runner's unrelated SHA/Candid correctness description because the optional field was absent; their measured validation still used the checked CBOR actor. The final integer manifest explicitly describes its independent CBOR checks, and both final cohorts were measured again after that metadata correction. No historical raw experiment was rewritten.

## Evidence and reproduction

[provenance.json](provenance.json) records compiler/package/runtime/source/actor/runner hashes. [baseline-build.json](baseline-build.json) and [final-build.json](final-build.json) include the complete compiler and plugin source hashes. Runtime source snapshots preserve exact measured versions. Generated Wasm binaries remain in `_build/opt2-cbor/{baseline,final}` and are represented by hashes in the archive.

The unchanged [core actor and cases](../../codec-comparison/cbor/main.mo), [edge actor and cases](../../optimization-round/cbor/edges/main.mo), and [error actor and cases](../../optimization-round/cbor/errors/main.mo) are referenced without duplicating them. Their recorded hashes match both measurements. The new [integer actor](integers/main.mo) and [manifest](integers/cases.json) are archived locally. Core native dependencies were independently checked against every file in the locked 20-alias/18-package manifest before each build. Encoder bytes are validated against the unchanged independent cbor2 oracle; decoder inputs come from cbor2 and retained results are checked against separately constructed typed values.

From the compiler's Nix shell, build only CBOR with `scripts/build.sh --motoko "$MOTOKO_ROOT" --skip-motoko-build cbor`. Preserve the baseline package before applying the runtime change. Generate the integer actor with the pinned cbor2 environment and `benchmarks/generate-cbor-integers.py --out PATH`. Compile the original core actor with `benchmarks/build-codec-comparison.py`; compile edge/error/integer actors with `moc --plugin PACKAGE ACTOR -o main.wasm`. Run the archived runner against each baseline/final actor with `--trials 3`, `--cases cases.json`, explicit SDK/canonicalizer/cbor-python paths, and `--delete-canisters true`. The exact runner is [run.mjs](run.mjs).

`python3 benchmarks/results/optimization-round-2/cbor/summarize.py` validates all paired samples and recorded hashes, then regenerates the deterministic CSV using only the Python standard library. It works from a temporary copy of this component archive and needs no compiler, runtime binary, dependencies or benchmark server.
