# P256 prepared field-hook sub-review

Static review found no current-source blocker in the final selected width-eight implementation. Exact current source hashes and scope limits are recorded in `report.json`. This reviewer ran no builds or execution tests and edited no production files. Final native, all-engine and GC runs remain the parent audit responsibility.

The vendor diff against the pinned local registry crates is limited to two P256 Montgomery limb methods, a thin P256 `Invert` trait adapter, two primeorder affine coordinate methods, and production/development dependency paths to local primeorder. The upstream 32-bit/64-bit arithmetic and projective normalization are unchanged.

Field values remain canonical residues below p in Montgomery form with R = 2^256. The accessors copy typed integer limbs without interpreting Rust object bytes. They exist only on 64-bit targets, matching the Wasm64/native64 support scope. The untouched 32-bit backend has the same mathematical R but does not expose these accessors.

The selected layout has WIDTH=8, ROWS=32 and POINTS=255: 16,320 payload bytes, matching `compiler/prepared_layout.ml`. `compiler/key_type.ml` registers the same protected type used by the compiler wrappers. Preparation first validates SEC1 keys. Every nonempty table coefficient is a sum of selected powers 2^(32j), j=0..7, so 0 < coefficient < 2^225 < n. Multiplying a nonidentity prime-order P256 key by any such coefficient cannot produce identity. Coordinates use explicit little-endian u64 encoding and `from_le_bytes`, with no alignment or host-endianness assumption.

The direct `ODD_GENERATOR` table contains G, 3G, ..., 15G. The generator applies the same coordinate*2^256 mod p conversion and low-to-high numeric u64 limb ordering as the prepared table. `point_from_words` restores these immutable numeric constants directly. Public verification NAF digits have odd magnitudes 1..15, selecting indices 0..7; negative digits subtract the corresponding point. These nonzero coefficients are below n, so the affine hook's nonidentity precondition holds. Independent execution checks of generated constants belong to the parent audit.

The `Invert` adapter calls the inherent `FieldElement::invert(self)` method without recursive trait dispatch, retaining zero rejection and canonical arithmetic. Upstream batch normalization substitutes ONE for zero z-coordinates before inversion and restores identity afterward. The upstream empty-batch failure is unreachable with the positive selected table size.

Unchecked restoration is justified by immutable generated constants or the compiler-enforced nominal prepared value. The raw unsafe native export's provenance contract is not an arbitrary-Blob validation API. SDK type protection, complete runtime correctness and GC/persistence enforcement remain outside this scoped static review.
