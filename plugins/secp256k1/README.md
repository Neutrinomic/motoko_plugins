# secp256k1

`mo:fast/Secp256k1` supplies SEC1 public keys, point arithmetic, RFC6979 ECDSA,
and BIP340 Schnorr. It requires only this plugin; SHA256/HMAC are internal kernel
dependencies and do not require another compiler plugin.

The Wasm64 runtime uses RustCrypto `k256` 0.13.4 with `default-features = false`
and `ecdsa,schnorr`. Its [pinned source and exact patch](runtime/vendor/k256/VENDOR.md)
reuse the public point already computed during Schnorr key normalization,
eliminating a duplicate scalar multiplication while preserving constant-time
selection and zeroization. It has no allocator, randomness source, imported operating
system APIs, mutable global state, callbacks, retained input pointers or GC calls.
Secret-key generation and BIP340 auxiliary randomness are caller responsibilities.
The portable OCaml interpreter implements matching semantics using the host Num library and a
SHA256 reference; this interpreter reference uses variable-time arithmetic.

## Encodings and results

- Secret keys: exactly 32 big-endian bytes, `1 <= d < n`.
- Arithmetic/tweak scalars: exactly 32 big-endian bytes, `0 <= k < n`.
- Public keys: canonical SEC1 compressed (33 bytes) or uncompressed (65 bytes).
  Hybrid encodings, invalid points and infinity are rejected. Point operations
  return compressed keys; an identity result is `#err(#pointAtInfinity)`.
- ECDSA input: exactly 32 already-hashed bytes; no implicit message hashing.
  Compact signatures are 64-byte `r || s`, with `1 <= r,s < n`.
  Signing is deterministic RFC6979/HMAC-SHA256 and returns low-S signatures.
  Verification accepts mathematically valid high-S signatures, too.
  DER decoding requires minimal positive integers and consumes the entire input.
- BIP340: x-only public keys are 32 bytes; signatures are 64 bytes; messages
  may have any length. Auxiliary randomness is explicitly supplied as 32 bytes.
  `xOnlyPublicKey` takes a SEC1 public key. `tweakXOnlyPublicKey` lifts to even Y
  before tweaking and returns compressed SEC1 with the output parity retained.
  `tweakXOnlySecretKey` applies the same even-Y normalization and scalar tweak
  inside the plugin for local Taproot signing; zero output is rejected.

All operations return `{ #ok : T; #err : Error }`. Malformed encodings produce
specific typed errors; correctly encoded signatures that fail verification
produce `#ok(false)`. Invalid BIP340 `r >= p` or `s >= n` are encoding errors;
in-range zero components are evaluated according to the BIP340 equation.

The ECDSA wrapper performs RFC6979 `bits2octets` reduction explicitly and uses
the upstream scalar signer, avoiding an unused cached public-key derivation.
Copied secret scalars are zeroized after signing; Taproot secret-tweak scratch
is zeroized after copying the result to its caller-owned Blob.

Direct and prepared BIP340 verification share k256's point/scalar equation.
The patched signer reduces its nonce hash modulo n before rejecting zero and
permits a computed zero S, matching BIP340. Its signature parser accepts zero
components while rejecting noncanonical values and incorrect lengths.

## Validation

Native Rust tests cover SEC2 generator/doubling, scalar boundaries, eight
independent ECDSA/RFC6979 answers (including hashes at and above the order),
strict DER, all 19 official BIP340 vectors, seven official BIP341 secret tweaks,
unaligned output and input immutability.
Public Motoko tests exercise the interpreter and generated Wasm, including every
official BIP340 vector and independently generated ECDSA answers.

Specifications: [SEC2](https://www.secg.org/sec2-v2.pdf),
[RFC6979](https://www.rfc-editor.org/rfc/rfc6979),
[BIP340](https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki),
[BIP340 vectors](https://github.com/bitcoin/bips/blob/master/bip-0340/test-vectors.csv).
