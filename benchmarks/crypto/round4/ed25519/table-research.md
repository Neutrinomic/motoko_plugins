# Ed25519 table candidates

Read-only research against plugins `0e1e96a`, pinned Dalek 4.1.3 and the existing
serial32 backend. No candidate builds or measurements were run for this note.
Finish the verification-equality screen first, then measure any table candidate
against the current winner. The counts below are source-level costs, not
predicted PocketIC instruction reductions.

## Smallest signing screen: upstream Fiat32

Before generating a larger table, a cheap separate screen can change only
`runtime_cfg` from `backend="serial"` to `backend="fiat"`, retaining `bits="32"`.
The workspace already locks `fiat-crypto` **0.2.9**; Dalek's existing conditional
Cargo dependency selects it, so no dependency or lock change is needed.
Fiat32 substitutes generated field arithmetic, retains the same serial32 scalar
arithmetic and table sizes, and preserves the canonical prepared encoding.
Its wrapper carries after field additions, whereas current serial32 additions
leave carries deferred. This makes a large gain unlikely from source inspection,
but generated multiplication/squaring may compile differently on Wasm; only a
screen decides. Include direct/prepared signing, preparation and verification
because all use field arithmetic. This is independent of the table experiment.
[Upstream backend configuration](https://github.com/dalek-cryptography/curve25519-dalek/blob/5312a0311ec40df95be953eacfa8a11b9a34bc54/curve25519-dalek/README.md),
[Fiat32 wrapper](https://github.com/dalek-cryptography/curve25519-dalek/blob/5312a0311ec40df95be953eacfa8a11b9a34bc54/curve25519-dalek/src/backend/serial/fiat_u32/field.rs).

## Constant-time fixed-base multiplication

**Try upstream radix32 first; keep radix64 as a fallback experiment.** Both use
Dalek's existing scalar recoding, full-table constant-time selection, and point
formulas. Wider tables remove field arithmetic but increase selection work.

| Per fixed-base multiplication | Current radix16 | Radix32 | Radix64 |
|---|---:|---:|---:|
| Affine additions | 64 | 52 | 43 |
| Doublings | 4 | 5 | 6 |
| Total table entries scanned | 512 | 832 | 1,376 |
| u32 limb conditional assignments in scans | 15,360 | 24,960 | 41,280 |
| Field arithmetic, excluding selection/recoding/compression | 461M + 16S | 380M + 20S | 320M + 24S |
| Full upstream serial32 table bytes | 30,720 | 61,440 | 122,880 |
| Rows actually accessed / rows stored | 32 / 32 | 26 / 32 | 22 / 32 |

M means field multiplication; S means field squaring. An affine addition followed
by conversion costs 7M. A serial32 affine table entry is three 40-byte fields;
selection scans all 30 limbs per entry. These counts exclude the sign adjustment
after selection. Radix32 saves 81M but adds 4S and 9,600 limb selections; its
instruction gain is uncertain. The full table is a Rust data size, not a promised
Wasm-size increase: linker retention and the old table's reachability must be
measured. Initially retain the existing 32-row types instead of changing their
layout. [Upstream multiplication/table implementation](https://github.com/dalek-cryptography/curve25519-dalek/blob/5312a0311ec40df95be953eacfa8a11b9a34bc54/curve25519-dalek/src/edwards.rs),
[constant-time table selection](https://github.com/dalek-cryptography/curve25519-dalek/blob/5312a0311ec40df95be953eacfa8a11b9a34bc54/curve25519-dalek/src/window.rs),
[serial32 field selection](https://github.com/dalek-cryptography/curve25519-dalek/blob/5312a0311ec40df95be953eacfa8a11b9a34bc54/curve25519-dalek/src/backend/serial/u32/field.rs).

A reproducible static table needs only a small offline generator:

1. Compile a development program against untouched, pinned upstream 4.1.3 with
   `curve25519_dalek_bits="32"` and `curve25519_dalek_backend="serial"`.
2. Call `EdwardsBasepointTableRadix32::create(&ED25519_BASEPOINT_POINT)` through
   the upstream `BasepointTable` trait. Its existing `Debug` formatter exposes
   every coordinate. Emit a checked-in Rust initializer, removing the quotes
   the formatter puts around table constructor names. No new arithmetic is
   needed; retain the generator, dependency lock and output checksum.
3. Add the generated static constant inside the vendored crate and select it
   from `EdwardsPoint::mul_base` only for the serial32 candidate. Other backends
   retain their original path. No runtime preparation, allocation, cache or
   Cargo build-time generator is needed.

This affects key derivation, secret preparation and prepared signing once per
call, and direct signing twice. Verification uses a separate NAF basepoint table.
Validate generator reproducibility, all scalar/carry boundaries including
unreduced 255-bit inputs supported by upstream, exact signatures and emitted
secret-independent table access. Never replace scans with secret-indexed loads.

## Prepared public-key multiplication

The current public-key table stores eight odd multiples of **-A** in projective
Niels form. The challenge remains the positive reduced `k`; verification computes
`[k](-A) + [s]B` without cofactor multiplication. Wider windows preserve this
integer scalar decomposition. Replacing it with `[-k mod L]A` would change
mixed-order acceptance.

| Candidate | Stored entries | Full prepared payload | Expected public-key additions | Preparation concern |
|---|---:|---:|---:|---|
| Current width5 projective | 8 | 1,056 B | ~42 | Existing baseline |
| Width8 projective | 64 | 8,224 B | ~28 | 56 extra odd-multiple construction steps |
| Width5 affine | 8 | 800 B | ~42 | Upstream constructor performs 8 inversions |
| Width8 affine | 64 | 6,176 B | ~28 | Upstream constructor performs 64 inversions |

The payload includes compressed A (32 B). Projective entries encode four fields;
affine entries encode three. Addition counts are approximate for ordinary
reduced challenges; scalar doublings remain roughly unchanged. Width8 projective
saves about 14 public-point additions but decodes 256 fields per call instead of
32. Width8 affine saves one further field multiplication per public-point
addition, while decoding 192 fields. Neither improvement removes hashing,
signature validation or the basepoint side of verification.
[Upstream odd-multiple constructors](https://github.com/dalek-cryptography/curve25519-dalek/blob/5312a0311ec40df95be953eacfa8a11b9a34bc54/curve25519-dalek/src/window.rs),
[projective/affine addition formulas](https://github.com/dalek-cryptography/curve25519-dalek/blob/5312a0311ec40df95be953eacfa8a11b9a34bc54/curve25519-dalek/src/backend/serial/curve_models/mod.rs).

**Width8 projective is the smaller implementation experiment:** reuse upstream
`NafLookupTable8`, `non_adjacent_form(8)` and the existing public-input loop;
expand the canonical codec and exact protected payload size. Keep direct
verification at width5 so one-off callers do not pay the larger setup cost.
Measure setup, warm calls, retained payload and actual reuse break-even.

Defer affine tables unless projective width8 warrants further work. A useful
affine implementation should reuse the existing batch-inversion algorithm with
fixed stack scratch: construct projective entries, batch-invert their Z values,
then normalize the three retained coordinates. Upstream's batch helper currently
requires `alloc` and a Vec, so this entails another reviewed refactor. Copying the
affine constructor unchanged would hide expensive repeated inversions in setup.
[Upstream batch inversion](https://github.com/dalek-cryptography/curve25519-dalek/blob/5312a0311ec40df95be953eacfa8a11b9a34bc54/curve25519-dalek/src/field.rs).

Retain all mixed-order/cofactor-only rejection cases and compare prepared results
with untouched upstream multiplication. Larger stack tables and exact GC payload
sizes need the existing native, Wasm, prepared-ownership and GC checks. No secret
operation should enter either variable-time verification path.
