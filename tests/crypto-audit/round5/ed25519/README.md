# Ed25519 round-five regression audit

No production defect found; no runtime, compiler bridge, vendored dependency or
public module changed. Baseline: `cf55e909`. This review covered the full public
module, OCaml reference/bridge, Rust exports and vendored prepared-key patches.

The earlier corpus already covers canonical/noncanonical encodings, negative
zero, all small-order points, scalar bounds, error precedence, large messages,
nominal handles and actual GC retention. New tests target uncovered behavior:

- **26 independent signing answers:** 24 message lengths immediately around
  SHA-512 padding and full-block transitions after Ed25519's internal 32-byte
  nonce and 64-byte challenge prefixes, plus pure-mode answers for two RFC keys.
- **72 independent verification cases:** 18 accepted signatures with mixed-order
  keys containing order-two, order-four or order-eight torsion; 32 signatures
  satisfying only the cofactored equation; 18 opposite-sign public keys; four
  RFC Ed25519ctx/Ed25519ph signatures presented to the pure API using both the
  original message and context-prefixed/prehashed bytes.
- **Four new native tests:** exact signing/verification, every exported entry
  point with input/output offsets 1 through 7 and guard bytes, unaligned prepared
  handles, read-only prepared/message aliases, null empty messages, and completely
  untouched failure buffers over lengths 0 through 160 and the earlier corpus's
  59 invalid-public-key cases.
- **Two normal Motoko fixtures and two Ash methods:** direct/prepared parity,
  independent expected bytes, same-length wrong messages, unrelated keys, and
  handle reuse after failed/interleaved calls. Silent fixtures intentionally have
  no `.ok` files.

`generate.py` uses Node 24.11.1 / OpenSSL 3.4.3 for signing. It reuses the earlier
independent affine oracle instead of copying curve formulas or consulting the
plugin. The mixed-order cases check the full equation and the cofactored equation
separately. The [RFC 8032 sections 7.2/7.3](https://www.rfc-editor.org/rfc/rfc8032.html#section-7.2)
vectors are also checked in their intended domains, and their literal public
keys are checked against OpenSSL derivation, preventing vacuous negative tests.
The generator verifies every unrelated-key expectation used by the Motoko suite.

## Executed validation

From the pinned SDK's `nix develop` environment, with `PATH` beginning with its
`bin` directory and `MOTOKO_ROOT` set to the SDK:

```sh
python3 "$PLUGINS/tests/crypto-audit/round5/ed25519/generate.py"
bash "$PLUGINS/tests/crypto-audit/round5/ed25519/run-native.sh"
test-runner -b -j2 "$PLUGINS/plugins/ed25519/tests/run"
```

Results: **9/9 native tests passed** (four new plus five existing runtime unit
tests); **2/2 Motoko fixtures passed** through source, IR and lowered interpreters,
Wasm validation and compiled Wasm. All ten execution/validation outputs were
empty and successful. Initial test-only syntax and Nat-subtraction warning were
corrected before the successful run; there was no production failure. Native
flags match `plugin.json`: `curve25519_dalek_bits="32"` and
`curve25519_dalek_backend="serial"`. The native wrapper is discovered by the
shared test script; public fixtures and `Ed25519Audit5.ash.json` are also normally
discovered. The integration lane owns the Ash execution/results.

The exact baseline `dist/ed25519` was copied without rebuilding; all recorded
Ed25519 source/artifact hashes and the compiler hash matched before testing:

| Input | SHA-256 |
| --- | --- |
| SDK `src/moc` | `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2` |
| `plugin.cmxs` | `139e8baec1768f390398204460580bec28de77cf4f2ac839a1b97f086a45c98b` |
| `runtime.wasm` | `32d76fa35196fcce7933a7e3c21ea171366e3d2acfac156f8f857dead42c97ac` |
| `vectors.json` | `cf408ac4b54afcd2818a502c8a6eae4db1c0e3d3d47ab0ccd40c9c55729c8a35` |

Review conclusions: canonical validation makes point equality equivalent to the
compressed comparison; prepared tables retain `-A` rather than reducing a
negated challenge modulo L; factories bind their secret scalar, prefix and public
key. The bridge roots evaluated arguments and allocates output before borrowing
pointers, and the runtime makes no allocation/GC callbacks. The immutable managed
secret payload is not erased on collection, as already documented; transient
expanded state uses upstream zeroization. This is source review and regression
coverage, not timing analysis, erasure proof or professional cryptographic audit.
Existing large corpora and actual GC tests were not duplicated. Main/default
installations were not modified, and no performance claim changed.
