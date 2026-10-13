# Motoko prepared-key hooks

This directory vendors `bls12_381` **0.8.0** from the crates.io archive:

- Upstream: <https://github.com/zkcrypto/bls12_381>
- Archive: <https://crates.io/api/v1/crates/bls12_381/0.8.0/download>
- Archive SHA-256: `d7bc6d6292be3a19e6379786dac800f551e5865a5bb51ebbe3064ab80433f403`
- Upstream commit recorded by the archive: `7de7b9d9c509b9973b35a3241b74bbbea95e700a`
- Original licenses, copyright notice, source, fixtures, and metadata are retained.
- `UPSTREAM-SHA256.json` records SHA-256 for every original archive file.
  The Cargo registry's generated `.cargo-ok` marker is not part of the archive.

The optional `plugin-prepared` feature adds the `plugin_prepared` module. It
requires `pairings` and `alloc`, matching the plugin's existing dependency
features. The existing upstream public APIs are unchanged; the field optimizations
below also apply when the prepared feature is disabled.

The prepared-hook edits to existing files are the feature and example declarations in
both Cargo manifests, the public module export in `src/lib.rs`, its child-module declaration
in `src/pairings.rs`, and a feature-gated crate-private finite G1 constructor in
`src/g1.rs`. `src/plugin_prepared.rs` contains the hooks and
`src/plugin_prepared_tests.rs` contains their unit tests. The hooks reuse
existing field, curve, Miller-loop and final-exponentiation formulas.

## Fixed field exponentiation

The existing upstream `chain_pm3div4` addition chain is also used by Fp square
root/inversion and Fp2 square root. A private statically dispatched field trait
shares the exact chain body between Fp and Fp2. For `e = (p - 3) / 4`, the
required exponents are `e + 1`, `4e + 1` and `2e + 1`; these integer identities
also preserve the result at zero. Existing zero, nonresidue, root-selection and
final-square predicates are unchanged. The chain module is compiled with the
groups feature; the unrelated hash-to-curve chain remains experimental.

The binary exponent implementations are test-only differential oracles. Tests
compare exact roots and inverses on edge cases and seeded random fields,
including pure-real/imaginary Fp2 values and both valid and invalid roots.
No prepared payload, external point format or group-validation rule changes.

## Final exponentiation

The six initial Frobenius maps are replaced by one conjugation. Since Fp12 is
a quadratic extension over Fp6, the p^6 Frobenius fixes the base coefficient
and negates the extension coefficient for every field value. Tests compare
both transforms on zero, basis values and general random fields, then compare
the complete result with the original final-exponentiation formula for
nonzero values. The nonzero Miller-result invariant is unchanged.

The hard part follows the equivalent, shorter schedule in
[ePrint 2020/875](https://eprint.iacr.org/2020/875), as implemented by
[arkworks at `4a19a1c`](https://github.com/arkworks-rs/algebra/blob/4a19a1c50606ae4a0e96ccce107f6281aa0be38e/ec/src/models/bls12/mod.rs).
With signed parameter `x`, both the original and replacement schedules have
the exact exponent `3 + (x - 1)^2 * (p + x) * (p^2 + x^2 - 1)`.
This preserves exact pairing outputs, not just equality-to-one checks.
Exponentiation by the fixed BLS parameter starts at the top set bit and follows
its five remaining set-bit gaps, removing the identity multiplication.

The two required p-squared Frobenius maps scale each Fp2 coefficient directly
by an Fp constant, instead of applying the general p-map twice. In basis
`1, v, v^2, w, vw, v^2w`, where `w^2 = v` and `v^3 = u + 1`, the factors
are `(u + 1)^(j * (p^2 - 1) / 6)` for `j = 0, 2, 4, 1, 3, 5`.
The `j = 0` and `j = 3` cases are identity and negation. The other four
constants use the existing reduced Montgomery representation.
Tests compare the direct map with two original p-maps on each real and
imaginary basis coefficient, their negatives, zero and seeded random inputs;
the full final exponent is compared with the isolated original schedule.

## Two-term streaming pairing

`two_term_miller_loop` computes each dynamic G2 coefficient immediately before
the existing `ell` operation, using the upstream Miller loop, doubling and
addition formulas. Fixed G2 generator operands borrow the immutable generator
table. Identity G2 operands substitute generator state and mask their
contribution exactly as upstream preparation does; G1 identity also remains
neutral. The runtime uses this path for two-term pairing equality checks.
General aggregate products and prepared IC verification retain their existing
owned/borrowed paths. No public Motoko API, prepared payload or validation rule
changes.

The driver owns exactly two curve states, bounded to 1,024 bytes by a unit test,
and allocates no coefficient tables. This bounds Rust driver state, not the
total compiled Wasm stack frame or peak stack use. Tests compare both raw
Miller results and final pairings with the existing owned and borrowed/mixed
loops across generators, all identity positions, negatives and cancellation,
seeded subgroup points and hash-derived points with the experimental feature.

## Payload contract

These hooks implement a private payload for the matching Motoko plugin build.
They do not define a wire format or a general point-deserialization API. The
plugin factory must validate canonical external point encoding, curve
membership, subgroup membership, and the profile's nonidentity/proof rules.
Only its protected, immutable, nonshared, nonstable result may reach a trusted
reader. The compiler enforces that users cannot manufacture those values from
raw bytes or extract their private payload. Rebuilding after upgrade recreates
tables under the current compiled plugin; no format migration is provided.

`write_g1_affine` and `write_g2_prepared` require already validated points. Both
reject identity before touching the destination. A successful write initializes
every output byte. `read_g1_affine_trusted` and
`G2PreparedSource::TrustedBytes` deliberately skip validation; feeding them
arbitrary bytes can produce invalid cryptographic results. The type boundary
protects this invariant. The crate's `#![deny(unsafe_code)]` remains enabled.

The representation contains only explicit little-endian `u64` Montgomery limbs.
It never contains native structs, padding, vectors, allocation metadata,
addresses, handles, or function pointers. Each field consists of six reduced
limbs (48 bytes). Byte readers use `from_le_bytes`, so unaligned slices work.
The SDK may still guarantee 8-byte alignment for its payload allocation.

| Payload | Order | Bytes |
|---|---|---:|
| Nonidentity G1 affine | x then y; six LE limbs per field | 96 |
| Nonidentity G2 preparation | 68 coefficients in the existing Miller-loop order; tuple 0/1/2; Fp2 c0/c1; six LE limbs per field | 19,584 |

The plugin may prepend the canonical compressed public key to support key
comparison: 48 bytes before G1 coordinates, or 96 bytes before G2 coefficients.
Those prefixes are outside these hooks. There is no infinity flag in these
payloads because only nonidentity points are encoded. Owned `G2Prepared` sources
retain upstream identity handling in mixed loops.

Preparation writes each coefficient directly into the output buffer without an
intermediate table allocation. The mixed Miller loop reads one coefficient at
a time into stack values and invokes the existing `ell` operation; it does not
copy a complete table. Existing `miller_loop`, doubling, addition, field, and
final-exponentiation implementations supply all cryptographic arithmetic.
There is no mutable cache or state retained between calls.

## Validation

Run the vendor unit tests independently: ordinary plugin package tests do not
execute dependency tests. From the plugins repository, with the vendored crate
excluded from the root workspace:

```sh
cargo test --manifest-path plugins/bls12-381/runtime/vendor/bls12_381/Cargo.toml \
  --no-default-features --features plugin-prepared --release \
  --target-dir _build/prepared-vendor-target
```

Standalone Cargo invocations generate a vendor-local `Cargo.lock` for upstream
dev dependencies. Preserve it with the test evidence and remove that generated
copy before the plugin build; the plugin uses the repository root lockfile.
Build products belong in `_build`, outside the runtime source tree.

Focused tests are selected with `plugin_prepared`. Coverage includes exact
upstream coefficient parity for both signs of several independently stored
valid point fixtures, reduced field limbs, full initialization under different
fill bytes, identity rejection with an unchanged output buffer, offsets 0–7
with prefix/suffix guards, and borrowed/mixed upstream pairing parity at
0/1/2/8/127/128 terms. Neutral and cancelling terms cover both G1 identity and
owned G2 identity. Tests do not treat self-roundtrips as the only oracle.

## Fixed generator table

The example writes the generator's coefficients through the same explicit
encoder, with no native layout conversion or mutable cache. Run from the
plugins repository (choose the output path explicitly):

```sh
cargo run --manifest-path plugins/bls12-381/runtime/vendor/bls12_381/Cargo.toml \
  --no-default-features --features plugin-prepared --release \
  --target-dir _build/prepared-vendor-target \
  --example motoko_g2_generator -- _build/g2-generator-prepared.bin
```

The plugin's immutable generator fixture must be tested byte-for-byte against
fresh `write_g2_prepared(G2Affine::generator())` output. Its owning runtime
supplies the 8-byte-aligned wrapper. Direct and prepared-key IC verification
must share this optimization so prepared-key benchmarks measure key reuse
separately from generator reuse.
