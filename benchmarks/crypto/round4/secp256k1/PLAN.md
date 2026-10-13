# Secp256k1 optimization round four

Baseline plugins `0e1e96a`, compiler SDK `9f6ebeedc` / ELF SHA-256
`24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.
Prepared public/secret payloads stay 512/64 bytes; API and validation stay fixed.

Three bounded candidates are approved:

1. Immutable affine generator table using the existing k256 signed radix-16
   schedule. A 33 × 8 table holds `[1..8] * 2^(8*i) * G`. The exact upstream
   recoder and eight-entry constant-time scans select digits, and existing
   complete addition formulas combine them. No runtime setup or hidden cache.
   Canonical coordinate content is 16,896 bytes; actual runtime Wasm growth is
   measured. This replaces 128 doublings and per-call setup with four doublings
   for known-generator secret operations. Arbitrary-point scalar multiplication
   remains the unchanged generic GLV path for differential testing.
2. ECDSA verification compares its public homogeneous point X against `r*Z`
   and, only when `r < p-n`, `(r+n)*Z`, rejecting identity. Since `p < 2n`,
   these exhaust possible affine X coordinates with `X mod n = r`. K256 uses
   affine `X/Z` (not Jacobian `X/Z²`). This eliminates final field inversion.
   Rare `x >= n`, `r+n=p` and infinity fixtures must remain covered.

3. Scalar squaring uses pinned crypto-bigint's existing constant-time wide
   square, followed by the unchanged k256 reduction. The ECDSA secret inversion
   retains its fixed addition chain. No new limb/carry arithmetic is introduced;
   max-limb/order/carry boundaries are compared against general multiplication.

Sources:

- [RustCrypto k256 0.13.4 multiplication](https://raw.githubusercontent.com/RustCrypto/elliptic-curves/k256/v0.13.4/k256/src/arithmetic/mul.rs)
- [RustCrypto crypto-bigint 0.5.5 wide squaring](https://github.com/RustCrypto/crypto-bigint/blob/v0.5.5/src/uint/mul.rs)
- [libsecp256k1 ECDSA verification](https://github.com/bitcoin-core/secp256k1/blob/master/src/ecdsa_impl.h)

Measure each candidate's incremental instructions, allocation and Wasm bytes
with three fresh-canister trials. Keep immutable stage snapshots. Final
validation includes native differential scalar boundaries, official and
independent ECDSA/BIP340 vectors, existing input/error policies, all-engine
agreement and prepared-handle lifecycle regression where relevant. No new
field/scalar arithmetic, SDK changes or broad parameter sweep is planned.
