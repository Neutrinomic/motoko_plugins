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
