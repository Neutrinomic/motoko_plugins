# Independent P-256 round 3 review

**Approved.** Source review, generated-Wasm inspection, independent execution
and paired PocketIC measurement parity passed with no blocking issues.

## Change reviewed

The candidate reuses the existing fixed-base generator comb for the RFC6979
nonce multiplication and stores the comb table as affine points. The signing
equation, key validation, digest reduction, error behavior and signature format
remain unchanged. In particular, signing preserves high S; normalization is
still explicit.

The direct signature equation matches `ecdsa 0.16.9`'s `hazmat::sign_prehashed`.
The unused recovery-ID computation is omitted. `rfc6979 0.4.0` receives the
secret scalar, exact group order and the digest reduced modulo that order, as
required by its API. Its nonzero in-range nonce guarantee makes the nonce parse
and inversion assertions unreachable for a valid upstream implementation.
`Signature::from_scalars` retains the previous zero-r/zero-s rejection behavior.

## Secret-dependent execution

The comb performs 64 doubles, 64 complete mixed additions and a complete scan of
all 15 nonidentity table entries at every step. Scalar bits select points with
constant-time masks. The 15 encoded points and table size are unchanged.

P-256 selects `primeorder 0.13.6`'s `EquationAIsMinusThree`. Its mixed addition is
the complete Renes–Costello–Batina Algorithm 5 plus a constant-time selection for
the affine identity. Thus zero comb digits do not introduce an exceptional
branch. Nonce inversion uses `Scalar::invert`, whose exponent is the fixed
public value n−2; it does not use `invert_vartime`'s secret-dependent GCD.

The emitted comb retains 17 conditional branches: 15 inspect decoding results
for compile-time table constants; the remaining two control the fixed table
scan and fixed 64-step outer loop. Point selection remains bitwise masking and
fixed-address loads. See [inspection evidence](wasm-inspection.json) and the
[compressed emitted function](generator-comb.wat.gz).

The upstream RFC6979 rejection loop is unchanged. This is a focused source and
emitted-code review, not a formal whole-program side-channel proof. Zeroizing
wrappers erase their explicit scalar/nonce/intermediate copies; neither this
review nor the implementation claims complete erasure of every upstream stack
copy or caller-owned secret Blob.

## Independent execution

[The standalone audit crate](native/Cargo.toml) calls the runtime's exported ABI
against 43 signatures generated without RustCrypto or the Motoko reference.
[The oracle](generate-independent-vectors.py) uses Python HMAC-SHA256 for
RFC6979, Python modular integer arithmetic for the scalar equation, and OpenSSL
for nonce/public-key curve multiplication. It checks its own result against
RFC6979 Appendix A.2.5 before retaining vectors.

Cases include keys 1, n−1 and 2^255; digests 0, 1, n−1, n, n+1 and 2^256−1;
24 additional independent key/digest pairs; and the published RFC sample.
Exported signing bytes, public-key bytes, verification and output canaries all
passed in [the independent run](native-test.txt). This supplements the owner's 530 upstream signing comparisons, 1,284
comb cases, 147 verification linear-combination cases and 484 Wycheproof cases.

## Reproduction

```sh
python3 benchmarks/crypto/round3/p256/audit/generate-independent-vectors.py \
  --openssl /path/to/openssl \
  --output benchmarks/crypto/round3/p256/audit/independent-vectors.json
cargo test --offline --manifest-path \
  benchmarks/crypto/round3/p256/audit/native/Cargo.toml \
  --lib audit::independent_openssl_points_and_python_rfc6979 -- --exact
python3 benchmarks/crypto/round3/p256/audit/check-measurements.py \
  --results-root benchmarks/crypto/results --candidate-root . \
  --output benchmarks/crypto/round3/p256/audit/measurement-review.json
```

## Measured candidate

[The independent measurement check](measurement-review.json) rehashed all 562
baseline and 565 candidate frozen inputs, every source-archive member and every
canister binary. All 180 fresh-canister measurements (30 cases × 3 trials × 2
builds) have the expected output digest. Compiler, RTS, benchmark sources and
Motoko dependencies match between builds. The measured candidate runtime and
Rust source match the independently reviewed and tested artifacts.

| Operation | Before instructions | After instructions | Reduction |
|---|---:|---:|---:|
| RFC6979 signing | 13,458,880 | 7,225,034 | 46.32% |
| Compressed public-key derivation | 5,207,095 | 4,968,688 | 4.58% |

Verification, conversion and DER instruction counts are unchanged. No measured
case regressed. Per-operation allocation and all before/after/after-GC sampled
memory records are identical between builds. The canister binary grows by
8,416 bytes and the plugin runtime grows by 8,535 bytes; these are code-size
costs, not increases in managed heap allocation.

The audit does not change the runtime, compiler component, SDK or public module.

Primary references: [RFC6979](https://www.rfc-editor.org/rfc/rfc6979),
[RustCrypto ECDSA hazmat source](https://docs.rs/ecdsa/0.16.9/src/ecdsa/hazmat.rs.html),
[RustCrypto primeorder point arithmetic](https://docs.rs/primeorder/0.13.6/src/primeorder/point_arithmetic.rs.html).
