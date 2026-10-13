# Independent prepared Secp256k1 audit

Approved implementation `f9e650e`, with a 512-byte public cache and 64-byte
Schnorr secret cache. Final runtime SHA256:
`68fb9f6ca1994c01b844cf11f995f17fb20603063ebfa26f7062f691e4353ad0`.
No production correctness defect was found.

Passed: 17 native tests in each of debug/release, 17 fixtures in the source/IR/
lowered interpreters and actual Wasm, nine nominal misuse checks, and the Ash
GC actor. Independent Python expectations cover 32 key sets and 512 serialized
public points; the native differential suite covers 1,283 scalar-boundary pairs.
Published corpora include 476 Wycheproof cases, 19 BIP340 vectors, and 18 RFC6979
boundary cases, plus rare ECDSA infinity and x >= group-order cases.

[Assessment and matched performance screen](evidence/assessment.json),
[engine/native evidence](evidence/evidence.json),
[confirmed Blob-forgery checks](evidence/confirmed-blob-forgery.json), and
[GC evidence](evidence/ash-evidence.json) pin the tested artifacts and logs.
Three initial forging fixtures accidentally inferred Text literals; they were
strengthened to explicitly typed Blob variables and successfully rerun. The
corrected generator is retained alongside the initial and follow-up evidence.

The selected-format screen uses these exact compiler/plugin artifacts and passes
all 27 observations. Per-call instructions fall from 2,618,931 to 2,367,381 for
ECDSA verification, 2,413,083 to 2,161,197 for Schnorr verification, and 5,099,447
to 2,584,269 for Schnorr signing. Setup is separate: 484,693 / 485,205 / 2,517,394
instructions respectively. These fixture-specific counters justify the cache;
the integration report owns the larger reuse/cold-call benchmark cohort.

This directory owns only audit fixtures, generators, reports and their native
harness. [Vendor provenance](vendor-evidence.json) independently checks all 34
original files and reapplies the exact patch from the pinned crate archive.

The source review checks the factory-only trust boundary: three distinct nominal
managed types, canonical field encodings instead of native layouts, initialized
bounded output scratch, complete existing curve formulas, GLV signs and table
indices, immutable inputs, and the absence of mutable key/nonce state. Prepared
Schnorr signing retains the even-Y scalar/public-X correspondence and the existing
auxiliary-randomness, nonce and challenge inputs. New variable-time helpers are
called only by public verification. The private cache consumer deliberately does
not authenticate arbitrary raw tables; Motoko cannot construct those values from
Blobs or cross scheme types.

`check_generator.py` independently verifies all 16 embedded generator entries
against Python integer affine multiplication and the explicit beta endomorphism.
`generate.py` replays the prior published and independently generated direct
corpus through prepared factories/verifiers/signing while keeping a direct
regression copy for the new shared-generator path. It adds eager argument/alias,
factory-error and malformed signature/digest/auxiliary checks, plus nine negative
nominal-type fixtures. Factory errors are checked with pattern matching; opaque
handles do not expose backing-Blob equality.

The native harness includes the exact production runtime and its owner tests,
and separately compares factory bytes and signatures against 32 Python-generated
key sets. It checks canonical cache coordinates, even-Y normalization, compressed
versus uncompressed inputs, output canaries, zeroed failure output, null predicate
output, input immutability and reverse-order key reuse. The same tests run in debug
and release. The all-engine suite exercises the Wasm field backend, rather than
relying on native arithmetic alone.

Run from the frozen SDK's Nix shell, after the coordinator grants a slot:

```sh
python3 /absolute/plugin-checkout/tests/crypto-audit/prepared/secp256k1/run.py \
  --plugin /absolute/plugin-checkout/dist/secp256k1 \
  --motoko /srv/shared/code/motoko_experiments/prepared-crypto/sdk \
  --out /absolute/plugin-checkout/_build/prepared-secp-audit-final \
  --pause-file /absolute/plugin-checkout/_build/pause-secp-audit
```

The optional pause file suspends execution between individual all-engine
fixtures for exclusive benchmark waves. Source, compiler and artifact hashes
must match before and after execution. [The GC actor](gc/README.md) separately
retains every prepared type across confirmed collection and interleaved key use,
then drops roots and prepares fresh handles.

These are correctness and memory-lifetime tests, not a formal side-channel
certification. Prepared secret payloads are managed secret data with no secure
heap-erasure guarantee; clearing local Rust temporaries does not change that.
