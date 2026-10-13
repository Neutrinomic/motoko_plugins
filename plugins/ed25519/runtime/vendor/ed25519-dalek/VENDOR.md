# Pinned ed25519-dalek prepared signing helper

This is the complete published `ed25519-dalek` 2.2.0 crate, including its original
BSD-3-Clause license. `upstream-source.json` records the published archive hash,
upstream revision, all original file hashes, changed file hashes and the exact
patch hash. Apply `exact.patch` with `patch -p1` from the original crate archive.

Two upstream files differ:

- `Cargo.toml` adds an empty workspace and points normal/development curve25519
  dependencies at the adjacent pinned `../curve25519-dalek` source. Versions,
  dependency features and package identity are unchanged.
- `src/signing.rs` factors the existing `raw_sign_byupdate` body into
  `raw_sign_byupdate_bytes`, whose public-key input is the compressed bytes it
  already hashed. Existing signing calls pass `verifying_key.as_bytes()`.
  `ExpandedSecretKey::sign_prepared` calls the same implementation using the
  immutable compressed public key bound to a prepared secret. No point
  decompression is needed for this already checked association. All nonce
  generation, hashing, scalar multiplication and signing arithmetic retain the
  original code. This helper does not add cryptographic formulas.

The plugin must create the expanded secret and compressed public key together
from the same seed and protect the association from modification or forgery.
Permitting an attacker to choose the public key for an existing expanded secret
can reveal the secret scalar. The helper's Rust documentation states this
requirement. Ordinary Ed25519 requires the SHA-512 digest type.

A prepared secret contains the canonical **already reduced** scalar (32 bytes),
nonce prefix (32 bytes), and compressed public key (32 bytes). Restore the scalar
with `Scalar::from_bytes_mod_order` (which leaves canonical bytes unchanged),
or with `Scalar::from_canonical_bytes`, and initialize `ExpandedSecretKey` from
its public scalar/prefix fields. Do not pass the stored scalar through
`ExpandedSecretKey::from_bytes`, which would clamp it again. The `zeroize` feature
continues to clear the temporary `ExpandedSecretKey` on drop. It does not erase
immutable Motoko heap payloads, caller-owned seeds, or all compiler/hash
intermediates.

The standalone `audit/prepared-comparator` resolves untouched registry crates
and these path crates as separate Cargo package identities. It checks 6,380
prepared/restored table results against the original algorithm, including all
torsion classes and mixed-order points; checks 4,640 canonical field encodings;
and compares 576 exact direct/prepared signatures over 32 seeds and 9 message
lengths, with 576 cross-verifications. Seven explicit regressions reject the
incorrect `(-k mod L)A` substitution. The prepared secret roundtrip restores the
stored scalar without clamping.

Run both configurations from this directory:

```sh
python3 audit/prepared-comparator/run.py --bits 32
python3 audit/prepared-comparator/run.py --bits 64
```

The runner pins the serial backend, keeps Cargo build output outside this
source tree, and records source/lock/configuration hashes with the results.
Build products must remain outside `runtime/`, which the plugin builder hashes.
Native comparison costs are not PocketIC instruction measurements. This patch
has regression tests and independent source review, but no external
cryptographic audit.
