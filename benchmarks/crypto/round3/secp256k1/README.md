# Secp256k1 optimization round three

The first candidate selects k256 0.13.4's unchanged 10x26 coordinate field
backend for Wasm64 instead of its 5x52 backend. Wasm has no native 128-bit
multiply. Scalar arithmetic, constant-time multiplication and signing remain
unchanged. The first candidate is retained as a standalone checkpoint.

Seven identical public API fixtures were compiled with the frozen baseline
and candidate artifacts using the existing `benchmarks/crypto/build.py` and
`run.mjs` protocol, three fresh PocketIC canisters per case. All 42 oracle
checks passed; instruction counts were identical across each three trials.
Both variants include all normal input decoding/validation. Allocation below
is cumulative Motoko allocation during the measured call, not retained heap.

| Operation | Baseline instructions | Field26 instructions | Allocated bytes, both |
|---|---:|---:|---:|
| derivePublicKey | 6,351,616 | 2,525,775 | 128 |
| verifyPrehash | 10,093,629 | 4,358,915 | 56 |
| signPrehash | 7,452,214 | 3,626,759 | 120 |
| schnorrSign | 12,762,954 | 5,114,993 | 120 |
| schnorrVerify | 9,920,617 | 4,187,087 | 56 |

`baseline/` and `field26/` retain full build manifests, raw trial results and
compressed exact source snapshots. Total canister Wasm sizes appear in each
build manifest. The source snapshots also contain the compiler/plugin hashes
and fixture source. Executable artifacts remain under local ignored
`benchmarks/crypto/results/round3-secp-{baseline-v2,field26}/`.

## Selected verifier optimization

The second candidate adds public-only GLV plus width-five non-adjacent-form
multiplication to ECDSA and BIP340 verification. It reuses the upstream scalar
split and complete point formulas, skips zero digits, and derives the second
point table through the curve endomorphism. Signing, key derivation, generic
scalar operations and tweaks retain their existing constant-time paths.
The public API and all input validation remain unchanged.

| Operation | Original instructions | Field26 only | Selected field26 + NAF | Allocated bytes, all |
|---|---:|---:|---:|---:|
| derivePublicKey | 6,351,616 | 2,525,775 | 2,517,833 | 128 |
| verifyPrehash | 10,093,629 | 4,358,915 | 2,735,252 | 56 |
| signPrehash | 7,452,214 | 3,626,759 | 3,618,815 | 120 |
| schnorrSign | 12,762,954 | 5,114,993 | 5,099,105 | 120 |
| schnorrVerify | 9,920,617 | 4,187,087 | 2,519,369 | 56 |

All 63 observations across the three stages pass exact independent output
checks. The selected ECDSA and Schnorr verifiers use 72.9% and 74.6% fewer
instructions than the original. NAF alone saves 37.2% and 39.8% relative to
field26. The selected `verifyPrehash` canister is 378,020 bytes, compared with
446,693 original and 376,916 field26-only. Minor instruction changes in secret
operations arise from the rebuilt artifact; their algorithms do not use NAF.
These are deterministic examples, not worst-case bounds or timing claims.

`field26-wnaf/` retains the raw third stage. `native-tests.txt` records all
eight runtime tests passing, including 1,283 direct multiplication comparisons.
`wnaf-recoding-check.py` checks independent integer reconstruction over 180,208
inputs; its JSON output explicitly distinguishes this model from Rust/Wasm
execution. The full independent Wasm audit is retained separately under
`tests/crypto-audit/round3/secp256k1/`.

The algorithmic background is the [libsecp256k1 multiplication design](https://github.com/bitcoin-core/secp256k1/blob/master/src/ecmult_impl.h),
which also uses endomorphism splitting and non-adjacent digits. This patch
uses the existing RustCrypto point operations rather than importing new
field formulas or C implementations.

The final rebuild refreshes the vendor patch ledger and documentation;
`final-build.json` pins the final source. `final-artifact.json` verifies its
runtime and native plugin bytes are identical to the measured NAF stage.
Frozen screen archives preserve their original metadata rather than being
rewritten after measurement.

Final independent audit passed against those exact artifacts: eight fixtures
through source, IR, lowered IR, Wasm execution and Wasm validation, covering
476 Wycheproof vectors, all 19 BIP340 vectors, 18 RFC6979 boundary cases,
32 additional random ECDSA/Schnorr cases, arithmetic and malformed-key cases,
and constructed ECDSA infinity and rare X-coordinate reduction cases.
Independent 10x26 versus 5x52 versus BigUint tests passed in debug and release.
See [the retained audit](../../../../tests/crypto-audit/round3/secp256k1/).

## Final predicate allocation cleanup

The final bridge omits an unused zero-length output Blob for the two predicate
operations. Their output pointer is null, and the native bridge explicitly
skips the output copy when its capacity is zero (Rust requires this guard even
for a zero-length copy). Argument evaluation, validation, typed errors and
arithmetic are unchanged. This is a plugin compiler-component change; the
SDK, compiler and RTS were not changed.

| Operation | Final instructions | Final allocated bytes |
|---|---:|---:|
| derivePublicKey | 2,517,833 | 128 |
| verifyPrehash | 2,735,069 | 32 |
| signPrehash | 3,618,817 | 120 |
| schnorrSign | 5,099,108 | 120 |
| schnorrVerify | 2,519,189 | 32 |

Both predicates save 24 allocated bytes per call. Signing changes by only
+2/+3 instructions from the native copy guard; those differences are retained
rather than rounded away in the raw results. All 21 new measurements pass
independent exact-output checks. `predicate/` retains the final build,
source snapshot, three trials per case, native test log and plugin manifest.
The preceding stages and audit evidence remain immutable checkpoints.

All nine native tests pass, including null-output valid/false/error paths.
The [independent followup audit](../../../../tests/crypto-audit/round3/secp256k1/predicate/)
passes nine fixtures through all five execution/validation modes and nine Ash
methods, including eager argument/error ordering, aliases and retained
predicate result variants across more than 16 MiB of confirmed GC activity.
