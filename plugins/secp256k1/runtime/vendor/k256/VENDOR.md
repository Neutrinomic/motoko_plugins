# Pinned k256 source and local performance patches

This is the complete published source of RustCrypto `k256` 0.13.4, including its
original Apache-2.0 and MIT licenses. The `.cargo-ok` local extraction marker is
omitted. The crate archive SHA-256 is
`f6e3919bbaa2945715f0bb6d3934a173d1e9a59ac23767fbaaef277265a7411b`;
the archive records upstream commit `5ac8f5d77f11399ff48d87b0554935f6eddda342`.
`upstream-source.json` records every original file's hash, changed files'
before/after hashes, and the hash of `exact.patch`.

Nine upstream files differ, and three focused arithmetic files are added:

- `Cargo.toml` adds an empty workspace to keep upstream development targets
  outside the enclosing plugin workspace. Dependencies, features and package
  identity retain the published values.
- `src/schnorr/signing.rs` reuses the affine point already computed by
  `SigningKey::from(NonZeroScalar)` and adds one constructor regression test.
  Direct and prepared Schnorr signing share the nonce/sign equation
  through `sign_raw_prepared`, which accepts the normalized secret and matching
  public X created by a validated factory. Secret temporary buffers are zeroized.
  Previously, the constructor calculated `dG` to obtain parity, normalized the
  scalar, and calculated the normalized scalar's public point a second time.
  It now conditionally negates the existing point using the same parity bit.

- `src/schnorr.rs` permits zero signature scalars, as BIP340 requires, while
  rejecting noncanonical field/scalar values and incorrect lengths. The shared
  signer reduces the nonce hash modulo the group order before rejecting zero,
  and permits a computed zero S. These correct rare inherited upstream boundary
  errors; independently forced hash-output regressions exercise the actual signer
  and direct/prepared verification in debug and release. They are synthetic
  internal-branch tests, not naturally occurring SHA256 vectors.

- `src/arithmetic/field.rs` and `src/arithmetic/field/field_impl.rs` select
  upstream's unchanged 10x26 coordinate field backend on Wasm64 in release
  and debug builds. Its products fit in native Wasm `u64` multiplication;
  5x52 uses `u128` products that need software expansion on this target.
  Other targets and scalar arithmetic retain their upstream selection.

- `src/arithmetic/mul.rs` exposes its existing GLV scalar decomposition to
  the prepared module and retains the width-five non-adjacent recoder for
  **public verification inputs only**. Fixed-size arrays bound scratch space. The existing
  `LinearCombination` and `Mul` implementations are untouched.
  `MulByGenerator` uses the immutable affine fixed-generator table described below.

- `src/arithmetic/scalar.rs` selects pinned crypto-bigint's existing
  constant-time wide square instead of general multiplication for squaring.
  The existing k256 modular reduction and inversion addition chain are retained.

- `src/arithmetic/projective.rs` exposes its existing beta constant to the
  sibling prepared module; the endomorphism operation itself is unchanged.
  Its public ECDSA coordinate comparison skips inversion using homogeneous
  `X = r*Z` or `X = (r+n)*Z`, with explicit identity and strict `r < p-n`
  checks. Existing modular-difference normalization handles weak field values.

- `src/arithmetic.rs` registers the added `src/arithmetic/prepared.rs`. That
  module reuses the same GLV split and width-five recoder, with immutable affine
  generator constants shared by direct and prepared verification. A factory
  serializes validated public points/table entries as canonical X/Y bytes;
  hot verification trusts only opaque immutable handles created by that factory.
  Eight odd multiples occupy 512 bytes; their endomorphism images are derived
  with the existing beta multiplication when borrowed.
  Existing complete mixed-add formulas replace projective additions where an
  affine cached entry is available. No field or scalar formula is added.

The plugin calls the variable-time helpers only for ECDSA and BIP340 verification.
It never calls it for signing, secret key derivation, generic point/scalar
operations or tweaks. The ECDSA wrapper preserves the upstream verification
formula, full scalar/point validation, and acceptance of both low and high S.
BIP340 input-range, identity, parity and X-coordinate checks are unchanged.

The scalar conditional assignment, hash inputs, and `SigningKey` zeroization
remain unchanged. The round-five BIP340 corrections reduce the nonce digest
modulo n and allow a zero signature scalar; nonce zero still returns an error. Point
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

## Round-three validation and measurements

The round-three plugin native tests include 1,283 direct variable-time versus
unchanged constant-time linear-combination comparisons over zero, order and
bit boundaries, deterministic random scalars and identity/equal/opposite
points. The retained independent recoding model checks 180,208 values and
pins the exact Rust fragment. Actual Wasm verification additionally uses
independent published and generated vectors; see the separate audit evidence.

Matched PocketIC measurements and exact source snapshots are retained in
[`benchmarks/crypto/round3/secp256k1`](../../../../../benchmarks/crypto/round3/secp256k1/).
The backend-only checkpoint and the subsequent verifier optimization are
measured separately, including allocations and complete canister Wasm sizes.
This local patch has regression and independent source review coverage; it
has not received an external cryptographic audit.

## Prepared handles

Prepared public keys contain explicit initialized canonical field encodings,
with no pointers, padding or Rust-layout serialization. ECDSA and Schnorr handles
are separate nominal types; the latter is constructed only through the even-Y
BIP340 lift. The immutable generator table benefits direct calls as well.

The prepared Schnorr secret is normalized scalar32 || public-X32. Its factory
uses the existing constant-time key constructor, and signing reuses the shared
nonce/sign implementation without repeating long-term public-key derivation.
It accepts explicit caller auxiliary randomness exactly as the direct API does.
No variable-time table or verification helper is used by signing.
The factory clears its temporary stack output; managed secret values and their
copies can persist until collection and do not provide guaranteed erasure.

Prepared performance, format selection and independent executable audit are
recorded separately by the enclosing prepared-key workflow. These changes have
not received an external cryptographic audit.

## Round-four fixed-generator candidate

`fixed_base.rs` and the generated `fixed_base_table.rs` adapt the upstream
`precomputed-tables` radix-16 schedule to immutable affine constants. There is
no lazy initializer, runtime table setup or mutable cache. The existing signed
radix-16 recoder and complete mixed-add formulas are reused. Every scalar uses
65 full eight-entry scans, 65 additions and four doublings. Selection uses
`subtle` conditional assignment; scalar digits never index the table.

`plugins/secp256k1/tests/generate_fixed_base.py --check` reproduces all 264
points with independent Python integer affine arithmetic. Each row contains
`[1..8] * 2^(8*i) * G`, encoded canonically in source. The table contains
16,896 bytes of canonical coordinate data; Wasm size is measured separately.

Schnorr key construction, nonce derivation, and plugin known-generator
operations explicitly call `MulByGenerator`. Arbitrary-point multiplication
retains the upstream generic constant-time GLV implementation and serves as
an independent differential reference. Secret normalization, RFC6979,
BIP340 auxiliary randomness, hash inputs and signature equations are unchanged.

Round-four evidence is maintained under `benchmarks/crypto/round4/secp256k1`.
This implementation has not received an external cryptographic audit.
