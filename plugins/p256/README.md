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
retained pointers, or mutable state between calls. Secret signing scalar copies, serialized secret and nonce bytes, nonce and
inverse scalars, and intermediate secret products use zeroizing wrappers.
This does not claim complete erasure of upstream arithmetic or HMAC stack copies. Generated code allocates
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

Public-key derivation and signing nonce multiplication share a fixed-base comb
with four immutable tables of 15 affine points each. Its 16 rounds perform
16 doublings and 64 complete mixed additions. Every selection scans all 15
entries in a fixed order, including zero digits, using upstream constant-time
selection and complete mixed addition's identity handling. The 3,840 bytes of
public Montgomery coordinates are independently checked against Python
arithmetic and exact OpenSSL scalar multiplication. Restoring these constants
does not require SEC1 decoding on each call. Secret bytes and the copied
scalar are explicitly zeroized.

Signing keeps upstream RFC6979 nonce generation and uses a fixed scalar
inversion chain with 254 squarings and 38 multiplications. Its exponent is
independently verified as `n - 2`; loop counts and the multiplication schedule
do not depend on the secret. Scalar squares use the pinned `crypto-bigint`
symmetric wide-square operation followed by the existing Barrett reduction.
The ECDSA equation, exact signature bytes and nonzero validation are preserved.
The vanishingly rare zero-r or zero-s result returns `#invalidSignature`; it does
not silently change deterministic signing by retrying with another nonce.

Direct verification combines the two public scalar multiplications with
width-5 nonadjacent forms. Direct and prepared verification then compare the
homogeneous result `(X,Y,Z)` with `r` without affine normalization: infinity
is rejected, and `X = r*Z` or `X = (r+n)*Z` must hold in the field. The second
comparison is permitted only when the integer `r+n` is below the field prime
`p`; since `n < p < 2n`, these are the only possible representatives.
Verification's variable-time branches depend only on the supplied public
key, digest and signature. The table and exponent proofs establish arithmetic
values; constant-time behavior additionally requires source and emitted-code
review.

Validation includes exact RFC6979 A.2.5 SHA-256 signatures, all 484 cases in a
pinned Wycheproof P-256/SHA-256 corpus, SEC1/scalar/DER edge cases, and unaligned
pointer/sentinel tests. Exact prehash boundary signatures are independently
checked against Python RFC6979 and OpenSSL deterministic ECDSA. Public Motoko
fixtures exercise interpreter and Wasm
semantics; the Ash suite exercises public aliases, validation precedence,
retained values, representative Wycheproof flags, and a 72-byte DER output
retained across asynchronous continuations and observed garbage collection.
Native differential tests additionally compare 1,284 comb inputs and 147
verification linear combinations with upstream arithmetic. Another 530
exact-byte signing comparisons cover boundary secrets and digests, all
256 single-bit secrets, and deterministic SHA-256-derived inputs. Scalar
inversion is separately compared with generic binary exponentiation, and
squaring with multiplication. Verification fixtures cover both possible
X-coordinate representatives, the `r+n = p` boundary and infinity. See
[vector provenance](tests/vectors/README.md) and
[public API coverage](../../packages/fast/tests/ash/coverage/P256.md).

Primary references: [RFC6979](https://www.rfc-editor.org/rfc/rfc6979),
[RustCrypto p256](https://github.com/RustCrypto/elliptic-curves/tree/p256/v0.13.2/p256),
and [Wycheproof](https://github.com/C2SP/wycheproof).


## Repeated verification

`preparePublicKey` validates a compressed or uncompressed SEC1 public key and
returns `Result<PreparedPublicKey>`. Pass the resulting handle to
`verifyPrehashPrepared(key, digest, signature)` for repeated checks. The digest
and compact signature keep the same rules as `verifyPrehash`: malformed
arguments return typed errors, valid but incorrect signatures return
`#ok(false)`, and both high-S and low-S signatures are accepted. Prepared
verification checks the digest before the signature because preparation has
already validated the key.

A prepared key is immutable, caller-owned and garbage-collected. It can live
in transient records, arrays or maps and survive asynchronous calls. It cannot
be serialized, shared in an actor interface, used as stable data, inspected as
a Blob, or reconstructed from arbitrary bytes. Drop all references to release
it normally; there is no native cache or manual cleanup operation. Upgrades
must prepare fresh handles from the application's stored SEC1 public keys.

The native representation stores an affine public-key comb as explicit
little-endian canonical Montgomery coordinates. Preparation uses upstream
batch normalization with one field inversion. The runtime borrows the managed
payload synchronously and retains no pointers. Fixed generator tables are
shared immutable Wasm data, not duplicated in each handle. Direct verification
also uses a fixed odd-multiple generator table; comparisons include that
optimization in both paths. Signing and derivation use the separate constant-time
comb described above. The interpreter independently stores validated
SEC1 and evaluates the same public operation with portable curve arithmetic.
See the [narrow vendor hooks](runtime/vendor/README.md) for provenance and the
supported 64-bit targets. The pinned upstream crates emit generic-array deprecation
and trait-implementation attribute warnings when built as path dependencies;
the archived build logs preserve them. The selected width-eight format uses 16,320 payload bytes per key; it is not
a portable prepared-key encoding.

## Prepared verification performance before the fourth pass

The prepared-key pass selected a width-eight table, reducing repeated RFC6979
sample verification
from 12,541,922 to 3,802,871 IC instructions (69.68%), against direct verification
in the same plugin/compiler build. Both calls allocate 32 bytes. Preparation
costs 19,688,675 instructions and allocates 16,376 bytes, including the 16,320-byte
key payload. Its modeled total cost becomes cheaper than direct calls from
three verifications. Use direct verification for one-off keys.

That build passed all 111 PocketIC trials across seven independent
fixtures. Including preparation, ten RFC sample verifications cost 57,714,287
instructions versus 125,416,988 for direct calls (53.98% fewer); 100 cost
399,943,697 versus 1,254,167,648 (68.11% fewer). The bounded
width-four/six/eight comparison also passed all 81 trials;
width eight is 20.95% cheaper per repeated call than width six, using about four times
the payload. The public API has one chosen format. See the
[prepared-key report](../../benchmarks/crypto/prepared/p256/README.md) for
preparation, reuse, code-size and memory details. Payload size and cumulative
allocation are distinct from the separately sampled occupied heap and Wasm
capacity.

## Performance

The fourth pass adds the scalar inversion chain and symmetric scalar square,
splits the secret generator comb into four static tables, and removes the
final field inversion from direct and prepared verification. These changes
preserve the public API, deterministic signature outputs and prepared-key
payload format. The measurements below record earlier passes.

The third pass reuses the fixed-base comb for signing and switches its table to
complete affine mixed addition. All 30 workloads passed exact-output checks in
three fresh PocketIC canisters for each version.

| Operation | Previous instructions | Round-three instructions | Reduction | Allocation change |
| --- | ---: | ---: | ---: | ---: |
| RFC6979 signing | 13,458,880 | 7,225,034 | 46.32% | None |
| Compressed public key | 5,207,139 | 4,968,732 | 4.58% | None |
| Compressed-key verification | 12,873,756 | 12,873,756 | 0% | None |

In that comparison, all verification, key-conversion, DER and normalization
cases have exactly
unchanged instruction counts. Allocation and sampled memory are unchanged for
all cases. Whole-canister Wasm grows by 8,416 bytes and the runtime by 8,535 bytes.
See the [round-three report](../../benchmarks/crypto/round3/p256/README.md) for
all results, frozen toolchain/artifact hashes, memory definitions and the
independent source, emitted-Wasm and functional audit.

### Earlier passes

The second performance pass compares the delivered implementation with the
combined comb, verification and DER allocation changes. All 25 cases passed
exact-output checks in three fresh PocketIC canisters per case with the same
fixtures and toolchain; setup and output validation are outside measurement.

| Operation | Delivered instructions | Round-two instructions | Reduction | Allocation change |
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

The earlier signing improvement also remains in place: signing skips
`SigningKey`'s eager computation of an unused cached verifying key. The first
pass called the upstream RFC6979 primitive directly on the secret scalar. Against the corrected baseline
with matching dependency versions, this reduced signing from 24,655,157 to
13,457,023 instructions (45.4%) with unchanged allocation. See the
[corrected signing baseline](../../benchmarks/crypto/results/curves-p256-fixed-baseline/results.json)
and [first-pass results](../../benchmarks/crypto/results/curves-p256-candidate/results.json).
