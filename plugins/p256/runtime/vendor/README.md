# Narrow prepared-point accessors

These are source copies of RustCrypto `p256` 0.13.2 and `primeorder` 0.13.6
from crates.io. Their Apache-2.0 and MIT licenses are preserved in each directory.
The crate archive SHA-256 checksums are:

- p256: `c9863ad85fa8f4460f9c48cb909d38a0d689dba1f6f6988a5e3e0d31071bcd4b`
- primeorder: `353e1ca18966c16d9deb1c69278edbc5f194139612772bd9537af60ac231e1e6`

No field, scalar or point arithmetic is changed. Source additions are
`FieldElement::{to_montgomery_words,from_montgomery_words_unchecked}` and
`AffinePoint::{to_field_coordinates,from_field_coordinates_unchecked}`.
An `Invert` trait implementation delegates to the existing field inversion to
enable primeorder's upstream batch normalization. The p256 dependency metadata selects the adjacent primeorder source.

The field accessors support the repository's **64-bit native and Wasm64**
targets. They intentionally do not introduce a new 32-bit serialization path.
The private format is explicit little-endian canonical Montgomery limbs,
never a Rust struct dump or a native pointer. Its nonidentity affine points
come only from successful strict SEC1 validation and upstream batch
normalization, or independently checked immutable generated constants.
The unchecked restoration functions must not receive caller-supplied bytes.
Only the SDK's nominal, nonshared, nonstable prepared type exposes the runtime
operation; Motoko cannot construct or inspect its backing Blob.

Upstream package bookkeeping `.cargo-ok` and `.cargo_vcs_info.json` is omitted.
