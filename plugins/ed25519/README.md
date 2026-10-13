# Ed25519

Pure Ed25519 signing and verification, exposed through `mo:fast/Ed25519`.
The Wasm runtime uses pinned `ed25519-dalek` 2.2.0 and `curve25519-dalek` 4.1.3.
The compiler component supplies independent portable OCaml interpreter semantics
and ABI 1 code generation. No other plugin is required.

The build manifest selects Dalek's documented `serial` backend with 32-bit
field/scalar limbs. Its widening products fit native Wasm `i64` operations;
Wasm64 pointers and the plugin ABI remain unchanged. The backend selection is
pinned in the manifest and recorded in `dist/ed25519/build.json`.

```motoko
import Ed25519 "mo:fast/Ed25519";

// Obtain 32 unpredictable secret bytes from your application's entropy source.
let pair = Ed25519.keyPairFromSeed(seed);
let signature = Ed25519.sign(seed, message);
let valid = Ed25519.verify(publicKey, message, signatureBytes);
```

| Function | Input | Successful result |
| --- | --- | --- |
| `derivePublicKey(seed)` | 32-byte secret seed | 32-byte public key |
| `keyPairFromSeed(seed)` | 32-byte secret seed | `{secretKey; publicKey}` |
| `validatePublicKey(key)` | 32-byte compressed key | `true` |
| `sign(seed, message)` | Seed and original message bytes | 64-byte signature |
| `verify(key, message, signature)` | Public key, original message, signature | `Bool` |

All return `#ok` or `#err` with `#invalidSecretKey`, `#invalidPublicKey`, or
`#invalidSignature`. Every 32-byte seed is accepted, including all-zero bytes;
acceptance does not imply adequate entropy. `keyPairFromSeed` returns the caller's
seed as its secret key without introducing another secret format or copying it.
The plugin never generates randomness and never retains a key.

## Exact verification policy

Signing uses [RFC8032 pure Ed25519](https://www.rfc-editor.org/rfc/rfc8032.html#section-5.1).
It signs the exact message bytes with internal SHA-512. Signing a digest blob
means signing that blob as a message; this is **not Ed25519ph or Ed25519ctx**.

Verification requires canonical compressed Edwards encodings for public key A
and signature point R, both on-curve and not small-order, and `0 <= S < L`.
It checks the uncofactored equation `[S]B = R + [k]A`.
These are deliberately stricter acceptance rules than cofactored/ZIP-215
verification; protocols requiring those rules must use a matching verifier.
Mixed-order points are not rejected solely for being outside the prime-order
subgroup. `validatePublicKey` does not prove ownership or subgroup membership.

The runtime performs encoding checks before the upstream verification equation.
[Dalek's strict verifier](https://docs.rs/ed25519-dalek/2.2.0/ed25519_dalek/struct.VerifyingKey.html#method.verify_strict)
uses the same equation and small-order checks. Since typed errors require us to
validate R first, using its ordinary verifier afterwards avoids decoding R a
second time. No strict check is omitted.

Validation order is public key then signature. Malformed, noncanonical or
small-order values return `#err`; well-formed values whose equation fails return
`#ok(false)`. Empty messages are valid. Signature formats are raw `R || S`, not
ASN.1 DER; no ECDSA scalars or prehashes are interchangeable with this API.

## Execution and secrets

The runtime uses fixed-size stack scratch and streams hashes over borrowed
message bytes. There is no message-sized copy, heap allocator, RNG, mutable
persistent state, retained pointer or GC call. Motoko owns all result blobs.
Derived keys and signatures allocate 32 and 64 payload bytes respectively;
verification allocates only the Motoko result wrapper.

Dalek's established signing implementation uses constant-time secret arithmetic.
Its `zeroize` features erase owned signing keys and expanded secret state on
drop; this is best-effort transient cleanup, not a guarantee that every compiler
or hashing temporary is erased. The caller's immutable seed remains its
responsibility. The portable OCaml interpreter reference is variable-time and
allocates big integers; it is for semantic execution/testing, not hardened secret
handling. This plugin has project tests and source review, not an independent
professional cryptographic audit.

## Validation

- All five RFC8032 pure-Ed25519 vectors, including the 1,023-byte message.
- Independent Node/OpenSSL signing/derivation fixtures at message lengths
  0, 1, 31, 32, 64, 127, 128, 129, 1,024 and 4,096 bytes.
- Native scalar, point, small-order and canonical encoding checks; mutation
  differential tests against pinned Dalek strict verification.
- Public Motoko interpreter/Wasm and Ash tests, malformed-input recovery,
  input immutability, aliases and retained values across actual forced GC.

Fixtures and their generation are in
[`benchmarks/crypto/round3/ed25519`](../../benchmarks/crypto/round3/ed25519/).
Public test inventory: [Ed25519 coverage](../../packages/fast/tests/ash/coverage/Ed25519.md).
