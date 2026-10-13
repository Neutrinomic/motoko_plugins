# ML-DSA-44

Pure [FIPS 204](https://doi.org/10.6028/NIST.FIPS.204) ML-DSA-44 key generation,
signing and verification, imported as `mo:fast/MLDSA`. Load only `--plugin dist/ml-dsa`.
This is the final standard, not the older Dilithium encoding.

```motoko
import MLDSA "mo:fast/MLDSA";

let publicKey = MLDSA.publicKey(secretSeed);
let signature = MLDSA.sign(secretSeed, message, "my-protocol-v1");
// Given the #ok values above:
let verified = MLDSA.verify(publicKeyBytes, message, signatureBytes, "my-protocol-v1");
```

| Function | Inputs | Successful result |
|---|---|---|
| `publicKey` | Secret seed, exactly 32 bytes | Public key, 1312 bytes |
| `sign` | Secret seed, message, context | Deterministic signature, 2420 bytes |
| `signRandomized` | Secret seed, message, context, exactly 32 random bytes | Hedged signature, 2420 bytes |
| `verify` | Public key, message, signature, context | `Bool` |
| `preparePublicKey` | Public key, exactly 1312 bytes | `PreparedPublicKey` |
| `prepareSecretKey` | Secret seed, exactly 32 bytes | `PreparedSecretKey` |
| `verifyPrepared` | Prepared public key, message, signature, context | `Bool` |
| `signPrepared` | Prepared secret key, message, context | Deterministic signature |
| `signRandomizedPrepared` | Prepared secret key, message, context, randomness | Hedged signature |

Every operation returns `#ok` or a typed `#err`. Contexts contain at most 255
bytes, and must match during verification. Empty messages and contexts work.
Incorrect key/signature lengths or overlong contexts are errors. A
length-correct malformed signature or an incorrect message, key or context
returns `#ok(false)`.

The caller supplies cryptographically secure entropy for the 32-byte secret
seed. `publicKey` deterministically performs FIPS 204 key generation from it.
No expanded private-key import is exposed: a seed is compact, unambiguous, and
cannot contain inconsistent precomputed secret components. Signing expands the
seed on every call; its benchmark includes that work. It reuses the matrix
computed during that call rather than expanding it twice. `sign` uses the standard's
deterministic all-zero `rnd`; `signRandomized` takes an explicit fresh 32-byte
`rnd` for hedged signing. The plugin neither calls an RNG nor maintains hidden key state.

These functions implement pure ML-DSA. Passing a digest as `message` signs that
byte string; it does not implement the distinct HashML-DSA domain.

## Repeated operations

Prepare a key once and keep the returned handle in a local record, map, or
transient actor field. Preparation validates the raw key and builds immutable
NTT and matrix tables. Subsequent calls reuse those tables and produce the
same signatures and verification results as the direct functions.

```motoko
let #ok(key) = MLDSA.preparePublicKey(publicKeyBytes) else return;
let first = MLDSA.verifyPrepared(key, message1, signature1, "my-protocol-v1");
let second = MLDSA.verifyPrepared(key, message2, signature2, "my-protocol-v1");
```

A prepared public payload is 20,576 bytes; a secret payload is 28,800 bytes,
plus managed object/container overhead. Callers explicitly choose this retained
heap cost for repeated operations. Handles are nominal, opaque, nonshared and
nonstable; they cannot be converted to raw Blobs, sent in Candid, or persisted
across upgrades. Retain the canonical public key or seed when rebuilding after
an upgrade is needed. Each handle is ordinary GC-managed memory: no native
pointer or hidden cache survives a call. The immutable prepared secret contains
secret material and is **not securely erased by GC**.

The interpreter privately retains the canonical public-key bytes or seed and
recomputes the independent reference algorithm; its heap/time costs are not the
compiled cache's costs. Prepared runtime bytes are private implementation data,
not a serialization format or an unchecked expanded-secret-key import.

## Implementation

The Wasm kernel pins [`fips204` 0.4.6](https://github.com/integritychain/fips204)
with only its `ml-dsa-44` feature, without default RNG or native heap allocation.
The [documented vendor patch](runtime/vendor/README.md) adds explicit byte caches
and narrow matrix-reuse hooks. It preserves the upstream arithmetic and
signature acceptance rules.
Expanded keys and polynomial scratch live on the synchronous stack. A fixed-size
output Blob and the result variant allocate Motoko heap; failed signing or key
derivation also discards that 2420- or 1312-byte output allocation. Prepared factories allocate their fixed-size cache even on input errors, where
that allocation becomes collectible garbage. Direct and prepared verification
only allocate their result variant. Expanded secret keys have upstream
zeroization on drop; this is not a promise to erase every intermediate byte. Input Blobs remain owned by the caller and are not modified. Prepared factories
copy initialized tables into a new protected managed Blob; they never retain
an input pointer. The plugin performs no GC, callbacks or IO.

The OCaml interpreter reference independently implements FIPS 204 polynomial
arithmetic and SHAKE. It is executable reference semantics for `moc -r`, not a
constant-time secret-key implementation. Both paths use ABI 1 and match the
same canonical signature bytes for a fixed seed, message, context and `rnd`.

Signing uses the standard's rejection sampling, so its instruction cost varies
with the inputs. The pinned upstream implementation uses a 16-bit nonce counter;
after 16,384 rejected candidates its release behavior repeats the nonce domain.
This vanishingly unlikely bound is inherited and mirrored by the reference,
not a guarantee of bounded signing instructions. Canister instruction limits
still apply to a synchronous call.

## Validation

Official NIST ACVP key-generation, deterministic/randomized signing and
verification vectors and provenance are retained under [tests](tests/).
The public module has interpreter/Wasm checks and an
[Ash suite](../../packages/fast/tests/ash/MLDSA.mo) covering errors, domain
separation, malformed hints, boundary lengths and GC composition.

Recorded PocketIC instruction and allocation costs will appear in
[the round-three benchmark](../../benchmarks/crypto/round3/ml-dsa/).

Prepared-key validation and matched reuse benchmarks are tracked under
[prepared ML-DSA](../../benchmarks/crypto/prepared/ml-dsa/). The native suite
checks every existing official signing/verification vector through the prepared
path, including deterministic/randomized exact signature parity and cache
immutability. Public interpreter/Wasm and Ash tests also cover typed errors,
key interleaving and retained handles across collection.
