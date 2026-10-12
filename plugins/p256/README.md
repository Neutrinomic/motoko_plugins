# P-256

`mo:fast/P256` supplies NIST P-256 (`secp256r1`, `prime256v1`) public-key
operations and ECDSA, backed by RustCrypto `p256` 0.13.2. Load only the `p256`
plugin; hashing a message is a separate caller choice.

```motoko
import P256 "mo:fast/P256";
let publicKey = P256.derivePublicKey(secretKey);
let signature = P256.signPrehash(secretKey, digest);
```

Every operation returns `P256.Result<T> = { #ok : T; #err : P256.Error }`.
Errors are `#invalidSecretKey`, `#invalidPublicKey`, `#invalidDigest`, and
`#invalidSignature`; malformed caller data does not trap.

| Operation | Arguments | Successful result |
| --- | --- | --- |
| `publicKey` | secret Blob, compressed Bool | SEC1 key, 33 or 65 bytes |
| `derivePublicKey` | secret Blob | Compressed SEC1 key, 33 bytes |
| `convertPublicKey` | SEC1 key Blob, compressed Bool | SEC1 key, 33 or 65 bytes |
| `signPrehash` | secret Blob, digest Blob | Compact `r || s`, 64 bytes |
| `verifyPrehash` | SEC1 key Blob, digest Blob, compact signature Blob | Bool |
| `signatureToDer` | compact signature Blob | Minimal ASN.1 DER, 8–72 bytes |
| `signatureFromDer` | DER signature Blob | Compact signature, 64 bytes |
| `normalizeSignature` | compact signature Blob | Compact signature with `s = min(s, n-s)` |

Secrets and prehashes must be exactly 32 bytes. Scalars are fixed-width,
big-endian integers in `[1, n)`. Public keys must be compressed SEC1 (`02`/`03`,
33 bytes) or uncompressed SEC1 (`04`, 65 bytes), with canonical coordinates on
the curve. The point at infinity, hybrid encodings, and raw XY are rejected.
DER decoding rejects nonminimal/negative INTEGERs, trailing data, zero and
out-of-range signature components.

Signing uses deterministic RFC6979 HMAC-SHA256 and preserves the published
RFC6979 `s` value. The prehash is reduced modulo the scalar order before nonce
generation, including the `digest >= n` boundary required by `bits2octets`. Verification accepts high-S and low-S signatures. Applications
whose protocols require low-S can call `normalizeSignature`. A well-formed but
incorrect signature returns `#ok(false)`; malformed arguments return `#err`.
Verification validates the public key, digest, then signature, in that order.
Signing validates the secret before the digest. No message hashing or domain
separation is implicit in the prehash API.

The native kernel borrows input Blobs synchronously and has no allocator,
retained pointers, or mutable state between calls. Secret signing scalars are
explicitly zeroized after the upstream signing primitive returns. Generated code allocates
managed output Blobs and constructs typed result variants through the SDK.
Fixed-size operations write directly to their result payload. DER encoding
uses a zero-initialized 72-byte scratch Blob. A 72-byte encoding returns that
managed Blob directly; shorter encodings copy only the encoded bytes to an
exact-sized result. Verification needs only its result variant.

Portable OCaml interpreter semantics share the generic curve implementation
with secp256k1 through `compiler/p256_curve.ml` and `.mli` symlinks. The builder
hashes their dereferenced contents and packs each plugin into its own namespace;
loading P256 does not require the secp256k1 plugin. The reference uses
variable-time arbitrary-precision arithmetic for interpreter correctness; the
canister runtime uses the separate RustCrypto implementation.

Public-key derivation uses a fixed-base comb with 64 iterations and a full,
constant-time scan of all 15 table entries on each iteration. Its public table
is independently checked against Python arithmetic and exact OpenSSL scalar
multiplication. Secret bytes and the copied scalar are explicitly zeroized.
Verification combines the two public scalar multiplications with width-5
nonadjacent forms and performs one affine normalization. Its variable-time
branches depend only on the supplied public key, digest and signature. Signing
retains the upstream constant-time nonce multiplication. Targeted source and
emitted-Wasm inspection found no secret-dependent branch or address in the
added comb loop; this review is not a formal constant-time proof.

Validation includes exact RFC6979 A.2.5 SHA-256 signatures, all 484 cases in a
pinned Wycheproof P-256/SHA-256 corpus, SEC1/scalar/DER edge cases, and unaligned
pointer/sentinel tests. Exact prehash boundary signatures are independently
checked against Python RFC6979 and OpenSSL deterministic ECDSA. Public Motoko
fixtures exercise interpreter and Wasm
semantics; the Ash suite exercises public aliases, validation precedence,
retained values, representative Wycheproof flags, and a 72-byte DER output
retained across asynchronous continuations and observed garbage collection.
Native differential tests additionally compare 1,284 comb inputs and 147
verification linear combinations with upstream arithmetic. See
[vector provenance](tests/vectors/README.md) and
[public API coverage](../../packages/fast/tests/ash/coverage/P256.md).

Primary references: [RFC6979](https://www.rfc-editor.org/rfc/rfc6979),
[RustCrypto p256](https://github.com/RustCrypto/elliptic-curves/tree/p256/v0.13.2/p256),
and [Wycheproof](https://github.com/C2SP/wycheproof).


## Performance

The second performance pass compares the delivered implementation with the
combined comb, verification and DER allocation changes. All 25 cases passed
exact-output checks in three fresh PocketIC canisters per case with the same
fixtures and toolchain; setup and output validation are outside measurement.

| Operation | Delivered instructions | Current instructions | Reduction | Allocation change |
| --- | ---: | ---: | ---: | ---: |
| Compressed public key | 11,201,615 | 5,207,139 | 53.51% | None |
| Compressed-key verification | 22,609,363 | 12,873,756 | 43.06% | None |
| Uncompressed-key verification, low S | 22,046,908 | 12,311,308 | 44.16% | None |
| DER encoding, both integers padded | 6,404 | 6,077 | 5.11% | 224 → 128 bytes |
| RFC6979 signing | 13,457,023 | 13,458,880 | −0.014% | None |

The tested zero/order digest verification cases improve by 49.41%. Ordinary
DER encoding costs five more instructions, while SEC1 conversions cost 47–54
more (0.01–0.28%). Other allocation counts are unchanged. Benchmark canisters
grow by 4,768 bytes, or 4,780 bytes for DER-encoding fixtures; the runtime object
grows by 4,887 bytes. These numbers describe the recorded inputs and toolchain,
not every key or digest. See the [strict comparison](../../benchmarks/crypto/round2/comparisons/p256-combined.json),
[delivered baseline](../../benchmarks/crypto/results/round2-p256-hotspots-baseline/results.json),
and [current results](../../benchmarks/crypto/results/round2-p256-combined/results.json)
for exact source, artifact and toolchain provenance.

The earlier signing improvement remains in place: signing skips `SigningKey`'s
eager computation of an unused cached verifying key and calls the same upstream
RFC6979 primitive directly on the secret scalar. Against the corrected baseline
with matching dependency versions, this reduced signing from 24,655,157 to
13,457,023 instructions (45.4%) with unchanged allocation. See the
[corrected signing baseline](../../benchmarks/crypto/results/curves-p256-fixed-baseline/results.json)
and [first-pass results](../../benchmarks/crypto/results/curves-p256-candidate/results.json).
