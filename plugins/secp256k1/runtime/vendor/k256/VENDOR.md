# Pinned k256 source and local performance patches

This is the complete published source of RustCrypto `k256` 0.13.4, including its
original Apache-2.0 and MIT licenses. The `.cargo-ok` local extraction marker is
omitted. The crate archive SHA-256 is
`f6e3919bbaa2945715f0bb6d3934a173d1e9a59ac23767fbaaef277265a7411b`;
the archive records upstream commit `5ac8f5d77f11399ff48d87b0554935f6eddda342`.
`upstream-source.json` records every original file's hash, changed files'
before/after hashes, and the hash of `exact.patch`.

Four upstream files differ:

- `Cargo.toml` adds an empty workspace to keep upstream development targets
  outside the enclosing plugin workspace. Dependencies, features and package
  identity retain the published values.
- `src/schnorr/signing.rs` reuses the affine point already computed by
  `SigningKey::from(NonZeroScalar)` and adds one constructor regression test.
  Previously, the constructor calculated `dG` to obtain parity, normalized the
  scalar, and calculated the normalized scalar's public point a second time.
  It now conditionally negates the existing point using the same parity bit.

- `src/arithmetic/field.rs` and `src/arithmetic/field/field_impl.rs` select
  upstream's unchanged 10x26 coordinate field backend on Wasm64 in release
  and debug builds. Its products fit in native Wasm `u64` multiplication;
  5x52 uses `u128` products that need software expansion on this target.
  Other targets and scalar arithmetic retain their upstream selection.

The original secret multiplication, scalar conditional assignment, nonce/signing
implementation, hashing, and `SigningKey` zeroization remain unchanged. Point
negation and selection use existing upstream `AffinePoint` implementations.
Both scalar and point normalization use `ConditionallySelectable`; no branch
depends on the parity bit. `PublicKey::from_affine` checks nonidentity. Its
failure is impossible here because the input is a `NonZeroScalar` smaller than
the prime group order, and negation preserves nonidentity. The additional
local contains the public point rather than another secret scalar.

The change removes a duplicate multiplication from each constructor call,
including construction of the nonce key inside the existing Schnorr signer.
This is a structural observation, not an instruction-count or timing result.
Plugin performance evidence is maintained by the enclosing benchmark workflow.

Validation completed:

- The added upstream constructor test passed over 64 `d` / `n-d` keys, covering
  32 originally even and 32 originally odd public points. It compares the
  reused point with the previous recomputation path.
- The library compiles with default features disabled and only `ecdsa,schnorr`
  enabled. Upstream unit tests require `std` for their existing vector helpers,
  so the constructor unit-test run additionally enables `std`.
- The independent `audit/comparator` uses both the untouched registry crate and
  this path crate. Its release run passed 8 official BIP340 signing vectors and
  32 deterministic `d` / `n-d` pairs across 14 message lengths (0 through 4096
  bytes) and 4 auxiliary inputs: 3,592 exact signature comparisons, 7,184 cross
  verifications, and 72 public-key/normalized-secret comparisons. The result and
  original execution hashes are retained beside its source.

From this directory, reproduce the comparison with:

```sh
cargo run --release --locked --manifest-path audit/comparator/Cargo.toml \
  --target-dir /tmp/motoko-secp256k1-vendor-comparator
```

Reproduce the focused upstream test and the `no_std` library check with:

```sh
cargo test --no-default-features --features ecdsa,schnorr,std --lib \
  --target-dir /tmp/motoko-secp256k1-vendor-tests constructor_tests
cargo check --no-default-features --features ecdsa,schnorr --lib \
  --target-dir /tmp/motoko-secp256k1-vendor-tests
```

Keep Cargo build products outside this directory: the plugin builder hashes all
files beneath `runtime/` for provenance. The example target directories above
are temporary build locations and are not part of the vendored source.

The exact upstream delta is `exact.patch`; it can be applied with `patch -p1`
from an untouched extracted 0.13.4 crate. Additional files in this directory
are provenance, this document, the patch, and the standalone comparator audit.
