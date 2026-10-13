# Pinned curve25519-dalek prepared table helper

This is the complete published `curve25519-dalek` 4.1.3 crate, including its
original BSD-3-Clause license. `upstream-source.json` records the published
archive SHA-256, upstream revision, every original file hash, the exact changed
file hashes, and `exact.patch`. The patch applies with `patch -p1` to the original
crate archive. Nothing is copied from Rust object memory.

Three upstream files differ:

- `Cargo.toml` adds an empty workspace so upstream development targets are not
  included in the enclosing plugin workspace. Dependencies and features are
  unchanged.
- `src/backend/serial/scalar_mul/vartime_double_base.rs` factors the existing
  loop into `mul_with_table`. Ordinary multiplication still constructs the same
  width-five NAF lookup table. The prepared path supplies that table. Scalar
  recoding, point operations, basepoint table and the loop body are unchanged.
- `src/edwards.rs` adds `PreparedVartimeEdwardsTable`, with creation through the
  existing `NafLookupTable5::from`, a canonical field-byte codec, and an entry
  point to the factored loop. It does not add curve arithmetic.

The 1024-byte encoding contains eight projective Niels entries, for odd
multiples A, 3A, ..., 15A. Each entry contains Y+X, Y-X, Z and 2dT, in that order,
as four canonical 32-byte little-endian field elements. Arrays are fully
initialized. This encoding is independent of native pointers, field limbs,
Rust struct layout and the serial32/serial64 choice.

`from_trusted_bytes` is exclusively a storage codec for intact bytes previously
emitted by `to_bytes`. It deliberately does not perform public-key validation,
canonicality checks or table-relation checks. The plugin must ensure factory
ownership and immutability through its protected nominal handle. It must never
feed caller-supplied Blobs into this method. This trust assumption is part of
the prepared-handle interface; the method is not a general parser.

The plugin prepares the point **-A** and computes `[k](-A) + [s]B`, with the
positive reduced challenge `k`. It must not use A with `(-k mod L)`: these are
different for mixed-order public keys. Signature/public-key acceptance policy
belongs to the plugin and is unchanged by this helper. All inputs to this table
and variable-time multiplication are public verification data. Signing and
other secret scalar operations continue to use the unchanged constant-time
upstream implementation.

The standalone comparator in
`../ed25519-dalek/audit/prepared-comparator/` compares distinct original registry
and patched path dependencies. See its runner and retained results for serial32
and serial64 validation. Build products must remain outside this source tree,
because the plugin builder hashes everything below `runtime/`.

This local patch has regression tests and independent source review; it has not
received an external cryptographic audit. Native comparison costs are not
PocketIC instruction measurements.
