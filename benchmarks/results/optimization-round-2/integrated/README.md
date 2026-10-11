# Round 2 integrated compiler/package proof

All six representative measured actors retain **every executable byte**, including
their static initializers, after integration on compiler `128a41c06`. The complete
new Wasm binaries can be reconstructed from the measured `c320bf90d` binaries by
replacing exactly two occurrences of `2.0.0-10-gc320bf90d` with
`2.0.0-11-g128a41c06`. Both strings have the same length. One occurrence is passive
data; the other is the `icp:private motoko:compiler` custom section. All other
sections are byte-identical. The code section and all 9,690 function bodies are
byte-identical.

| Actor / historical measurements | Wasm bytes, both versions | Identical function bodies |
|---|---:|---:|
| [JSON native comparison](../json/native/final.json) | 1,279,731 | 2,508 |
| [CBOR native comparison](../cbor/final.json) | 1,108,342 | 2,177 |
| [Map functions, Nat64 keys](../pure-map/functions/after/results.json) | 548,249 | 1,528 |
| [SHA256 native comparison](../sha256/final.json) | 440,571 | 654 |
| [CandidX native comparison](../candidx/native-main/candidate.json) | 1,401,116 | 1,383 |
| [CandidX repeated variant comparison](../candidx/native-repeated/candidate.json) | 1,412,772 | 1,440 |

This is a compilation-equivalence check, **not a new performance run**. The linked
trials remain labeled with the compiler and binaries actually measured. The
instruction/allocation comparisons for these actors remain applicable to the
integrated packages because their executable code and memory layout are unchanged;
only compiler-version text changes. Existing failed native comparison rows also
remain unchanged. The separate SDK small-scalar measurements are in
[the SDK archive](../sdk/README.md).

The SDK production delta from `c320bf90d` to `128a41c06` changes only
`Compare.scalar` for small primitive types. Codec generators do not call that
helper, and the measured map actor uses Nat64 keys. The binary proof checks the
result directly; it does not depend on this source-level expectation.

`compile.py` verified every historical source, case file and Wasm against its raw
trial hashes before compiling the exact historical source path into a new scratch
directory. It verified all 20 native dependency aliases / 18 locked packages,
the native CandidX revision and source pins, the map wrapper, package source and
runtime identity, all rebuilt package inputs, the clean compiler revision and
binary, and unchanged compiler wrapper/RTS hashes. Native `.cmxs` packages were
rebuilt against the integrated compiler; their hashes are recorded rather than
assumed equal across compiler builds and source paths.

[build.json](build.json) records commands, compiler/package/source/dependency pins,
and old/new artifact hashes. [proof.json](proof.json) records every Wasm section's
hash and size, function-body counts, raw WAT hashes and exact reconstruction checks.
Each actor directory contains its **unmodified full-WAT unified diff**, produced
by WABT 1.0.41 with `wasm2wat --enable-all`; no executable instructions or metadata
differences are filtered out. [actors.json](actors.json) locates the preserved
original binaries and raw trials. [audit.md](audit.md) records the independent
review.

Integrated validation passed: compiler build, 46 SDK fixtures, 54 Motoko plugin
fixtures, 57 Rust tests (23 CandidX, 11 CBOR, 20 JSON, 3 SHA256), and SDK/plugin
packaging checks. The repository archive verification passed for 621 files without
changing inputs. [validation.json](validation.json) records the copied log hashes;
the logs are in [validation/](validation/).

To repeat the proof after rebuilding the pinned compiler and packages, preserve
the historical binaries at the paths in `actors.json`, then run from the canonical
compiler root:

```sh
nix develop /srv/shared/code/motoko_experiments/motoko_sha --command bash -c '
  cd /srv/shared/code/motoko_experiments/plugins
  python3 benchmarks/results/optimization-round-2/integrated/compile.py
  python3 benchmarks/results/optimization-round-2/integrated/compare.py
'
```

Generated Wasm, native packages and complete WAT disassemblies remain in private
build directories; they are retained by hash and are not committed. The archive
contains text proofs, diffs, scripts and validation logs. `manifest.json` identifies
the committed text files separately from the generated artifacts.
