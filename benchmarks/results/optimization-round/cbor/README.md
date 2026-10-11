# CBOR optimization round

On frozen `moc` `f1ccbba5e445df9db03bbc35be557187ade9b436`, all 23 measured plugin workloads use fewer instructions and allocate fewer bytes than plugin sources at `093957ad1ba611384a8b998c83bd86c75b585e4f`. Record-array encoding improves 35.84%; decoding improves 30.66%. Blob costs remain effectively unchanged. Successful calls save only 24–64 allocated bytes; the large instruction gains come from avoiding per-element path formatting.

The six original workloads compare the plugin with locked Mops `serde@3.5.0`, `serde-core@0.2.1`, and `cbor@4.1.0`. Fourteen additional workloads cover empty records, fixed and large integers, floats, Char, Principal, 4,096 booleans, nested options, Unicode text, sixteen-field maps, and variants. Three failing decodes cover a 256 KiB key, an escaped Unicode key, and a nested multi-digit array index. There are no omitted measured regressions relative to the baseline.

## Change and invariants

The runtime now stores borrowed path components and formats a JSON Pointer only for the first error. One component stack replaces an eagerly maintained String plus a parallel length stack. Keys borrow immutable input or compiler constants throughout the existing GC-free call; none borrow growing output or scalar buffers. Error rendering reserves the raw key byte length before escaping. Initial oversized-input errors initialize their root path directly, keeping context allocation cheap.

The compiler uses the OCaml byte length of constant labels, removing a temporary local and runtime Blob-length load. It still obtains payload pointers through the SDK. Motoko source field names are ASCII identifiers; incoming CBOR keys may contain arbitrary valid UTF-8, including NUL. Tests cover non-ASCII and NUL input keys as well as JSON Pointer escaping.

ABI 1, typed `#ok`/`#err`, deterministic RFC 8949 output, error kind/message/path/offset, and all input-dependent UTF-8, duplicate-key, range, quota, and trailing-byte checks remain intact. No SDK, shared build script, workspace manifest, compiler source, or historical raw archive changed.

## Results

Each cell is the identical count from three fresh-canister trials. Instructions include Result unwrapping, retained output assignment and counter overhead. Allocations are total managed and ephemeral allocated bytes during the timed call, not peak/live memory. No measured plugin call reclaimed memory. See [summary.csv](summary.csv) for every plugin and native phase, and [summarize.py](summarize.py) for consistency checks.

| Workload | Baseline → final instructions | Change | Baseline → final allocated bytes |
|---|---:|---:|---:|
| record-encode | 11,260 → 8,638 | -23.29% | 784 → 760 |
| record-decode | 11,612 → 8,797 | -24.24% | 1,272 → 1,248 |
| records-1024-encode | 8,409,156 → 5,395,241 | -35.84% | 174,224 → 174,160 |
| records-1024-decode | 10,577,700 → 7,334,513 | -30.66% | 173,192 → 173,128 |
| blob-64k-encode | 133,973 → 133,925 | -0.04% | 131,480 → 131,456 |
| blob-64k-decode | 67,174 → 67,115 | -0.09% | 65,872 → 65,848 |
| empty-record-encode | 1,829 → 1,784 | -2.46% | 376 → 352 |
| empty-record-decode | 1,821 → 1,757 | -3.51% | 1,032 → 1,008 |
| scalars-encode | 27,740 → 21,896 | -21.07% | 1,528 → 1,504 |
| scalars-decode | 27,468 → 21,476 | -21.81% | 1,056 → 1,032 |
| bools-4096-encode | 3,935,481 → 925,162 | -76.49% | 21,168 → 21,144 |
| bools-4096-decode | 4,433,502 → 1,357,625 | -69.38% | 33,192 → 33,168 |
| options-256-encode | 540,925 → 258,697 | -52.18% | 6,128 → 6,064 |
| options-256-decode | 628,526 → 333,398 | -46.96% | 5,248 → 5,184 |
| unicode-256-encode | 384,407 → 201,648 | -47.54% | 11,928 → 11,904 |
| unicode-256-decode | 476,310 → 289,177 | -39.29% | 12,712 → 12,688 |
| wide-record-encode | 36,399 → 22,290 | -38.76% | 1,224 → 1,200 |
| wide-record-decode | 96,231 → 80,529 | -16.32% | 1,464 → 1,440 |
| variant-encode | 9,525 → 5,932 | -37.72% | 616 → 552 |
| variant-decode | 9,538 → 5,779 | -39.41% | 1,264 → 1,200 |
| long-key-error | 21,576,255 → 21,305,590 | -1.25% | 1,574,560 → 525,624 |
| escaped-key-error | 2,227,472 → 2,209,586 | -0.80% | 116,288 → 75,096 |
| nested-index-error | 22,146 → 13,772 | -37.81% | 1,744 → 1,720 |

Native comparison cells show **instructions / allocated bytes**. Adapters, Candid bridges required by serde, Result unwrapping and output conversion are included. Libraries run in the same actor as the plugin, with matching typed inputs and wire semantics; this is an end-to-end comparison, not isolated parser timing.

| Workload | serde 3.5.0 | serde-core 0.2.1 | cbor 4.1.0 | Plugin |
|---|---:|---:|---:|---:|
| record-encode | 226,209 / 18,032 | 269,622 / 21,312 | 98,350 / 4,568 | 8,638 / 760 |
| record-decode | 452,201 / 49,560 | 546,055 / 37,384 | 188,248 / 13,352 | 8,797 / 1,248 |
| records-1024-encode | 82,729,674 / 6,041,088 | 91,466,776 / 6,039,896 | 49,934,053 / 2,452,232 | 5,395,241 / 174,160 |
| records-1024-decode | 286,327,797 / 22,644,936 | 309,636,040 / 20,164,416 | 152,527,112 / 11,545,504 | 7,334,513 / 173,128 |
| blob-64k-encode | 119,759,518 / 6,598,376 | 119,211,844 / 6,599,224 | 64,977,425 / 1,676,112 | 133,925 / 131,456 |
| blob-64k-decode | 204,734,570 / 9,455,408 | 223,952,628 / 8,142,752 | 74,088,272 / 1,145,048 | 67,115 / 65,848 |

## Validation and provenance

All 10 Rust kernel tests and seven Motoko expectation fixtures pass, including source/IR/Wasm execution, rejection diagnostics and forced-GC retention tests. New regressions exercise `/a/11`, `/a/some`, escaped Unicode siblings, and a NUL-bearing key. Existing Rust checks include every binary16 pattern, integer boundaries, large-map duplicate detection and malformed-input fuzzing. `rustfmt --check` and `git diff --check` pass. The independent [audit](audit.md) found no blocking defect.

Encoder outputs are independently decoded with Python `cbor2@6.1.5`. The added edge actor also compares exact bytes with cbor2's canonical encodings, including large integers and float widths. Decoder input is generated by cbor2 and compared with complete independently constructed Motoko values after timing. Malformed error inputs are independently rejected by cbor2, and actor queries assert the entire typed error. No correctness check relies solely on plugin encode/decode round trips.

[baseline.json](baseline.json), [final.json](final.json), [baseline-edges.json](baseline-edges.json), [final-edges.json](final-edges.json), [baseline-errors.json](baseline-errors.json), and [final-errors.json](final-errors.json) retain all 246 baseline/final samples. [provenance.json](provenance.json) records hashes of all six Wasm artifacts, sources, harnesses and dependency locks. [baseline-build.json](baseline-build.json) and [final-build.json](final-build.json) record package hashes and identical compiler source/binary hashes. Baseline package sources were separately verified against `093957a`; its preserved build metadata names an earlier commit because subsequent commits had not changed those sources.

Core actor/manifests are byte-identical to the existing [codec actor](../../codec-comparison/cbor/main.mo) and [cases](../../codec-comparison/cbor/cases.json). Added actors/manifests are archived under [edges](edges/main.mo) and [errors](errors/main.mo). The preserved local baseline package and compiled actors are under `_build/opt-cbor/baseline`; final actors are under `_build/opt-cbor/{bench,edges,errors}`. The frozen compiler binary SHA-256 is `375484d8cb78891111b1a7c1700ac2bc31e71226b23a11583a5d22d973da1aa8`.

## Experiments and tradeoffs

The [initial lazy-path experiment](experiments/lazy-path.json) improved records but added 257–268 instructions to blob calls because context construction called the general error renderer. Direct initialization of the root error removed that regression. Runtime field-name length loads were then replaced by known byte counts.

A later error-only reservation reduces 256 KiB-key error allocation from 1,312,392 bytes in the [lazy intermediate](experiments/errors-before-reserve.json) to 525,624 bytes. It costs 254,116 extra instructions relative to that intermediate (about 1.2%); the final error still improves both instructions and allocation versus baseline. The escaped-key error similarly trades 7,091 intermediate instructions for 16,592 fewer allocated bytes. These allocation reductions justify the one-line reservation; successful calls are unaffected.

Broader output-check removal was not implemented: exported pointer operations need their bounds checks before constructing slices, and another unchecked-write helper would complicate the local safety proof. Constant text flattening is already zero-copy for these flat literals in the frozen compiler; no new SDK entry point was needed.

The first edge generator used local aliases `T0`, `T1`, etc., revealing a separate frozen-compiler error: the ordinary Motoko program `actor { type T1 = [Bool]; transient var value : ?T1 = null; public func go() : async () { value := value }; }` fails IR checking with a free type constructor even without any plugin. Renaming the alias works. The SDK agent received the preserved reproducer; these benchmarks use inline types and the compiler remains frozen.

## Reproduction

Run in the frozen compiler's Nix environment. The original baseline build/package must be captured before applying this CBOR change; all subsequent compilation uses the same compiler. The installed Mops directory below is verified against every file in the archived lockfile by the build helper.

```sh
export CBOR_ROOT=/srv/shared/code/motoko_experiments/optimization-round/cbor
export MOTOKO_ROOT=/srv/shared/code/motoko_experiments/motoko_sha
export CBOR_DEPS=/srv/shared/code/motoko_experiments/plugins/_build/codec-comparison/deps
export CBOR_PYTHON=/srv/shared/code/motoko_experiments/plugins/_build/codec-comparison/oracle/bin/python
cd "$MOTOKO_ROOT"
nix develop
cd "$CBOR_ROOT"

# Build only CBOR, without rebuilding moc.
scripts/build.sh --motoko "$MOTOKO_ROOT" --skip-motoko-build cbor

# Run once with baseline sources, preserving dist/cbor and main.wasm,
# then repeat compilation with final sources and identical generated inputs.
"$CBOR_PYTHON" benchmarks/generate-codec-comparison.py --codec cbor --out _build/opt-cbor/bench
python3 benchmarks/build-codec-comparison.py --motoko "$MOTOKO_ROOT" \
  --deps "$CBOR_DEPS" --out _build/opt-cbor/bench --codec cbor
"$CBOR_PYTHON" benchmarks/generate-opt-cbor-edges.py --out _build/opt-cbor/edges
"$CBOR_PYTHON" benchmarks/generate-opt-cbor-edges.py --errors-only --out _build/opt-cbor/errors
"$MOTOKO_ROOT/bin/moc" --plugin dist/cbor _build/opt-cbor/edges/main.mo -o _build/opt-cbor/edges/main.wasm
"$MOTOKO_ROOT/bin/moc" --plugin dist/cbor _build/opt-cbor/errors/main.mo -o _build/opt-cbor/errors/main.wasm

# Example final run; repeat for edges/errors and each preserved baseline Wasm.
node benchmarks/run.mjs --wasm _build/opt-cbor/bench/main.wasm \
  --cases _build/opt-cbor/bench/cases.json \
  --out benchmarks/results/optimization-round/cbor/final.json --label final --trials 3 \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js --cbor-python "$CBOR_PYTHON"
python3 benchmarks/results/optimization-round/cbor/summarize.py
cargo test -p motoko-compute-cbor --locked --target-dir _build/opt-cbor/native-tests
rustfmt --edition 2024 --check plugins/cbor/runtime/src/lib.rs
export PATH="$MOTOKO_ROOT/bin:$PATH"
cd "$MOTOKO_ROOT"
test-runner -b "$CBOR_ROOT/plugins/cbor/tests/run" "$CBOR_ROOT/plugins/cbor/tests/fail" "$CBOR_ROOT/plugins/cbor/tests/run-drun"
```
