# fips204 prepared-key hooks

`fips204/` is the published `fips204` 0.4.6 crate, MIT OR Apache-2.0,
from upstream commit `8d456d989dce681233ef963d3c3306da8f76d7c7`.
Published crate SHA-256:
`c9fb5a367b9846933e271a3c2a992930743f82ae5e8cb7faa780715a80fa0b15`.

Local changes are confined to `src/lib.rs`, `src/ml_dsa.rs`, `src/hashing.rs`, and the new
`src/motoko_prepared.rs`. Arithmetic, NTT, hash functions, encoding,
rejection decisions, and acceptance rules are unchanged. SHAKE128 matrix
sampling reads one 168-byte rate block at a time instead of three bytes per
reader call. Every three-byte candidate is processed in its original order;
168 is divisible by three, so no cross-block carry or changed hash stream is
needed. The last partial block has no effect on the accepted coefficients. Existing entry points
call the same bodies with no cached matrix. The prepared factories retain the
matrix from key generation through an optional output (the direct path still
returns only its original key pair) or expand a public key once; consumers pass it to
those same algorithm bodies. One-shot seeded signing also reuses its already
computed matrix on the stack, with no managed cache or cache serialization.
Direct public-key derivation passes no matrix output and makes no such copy.
Direct verification still rejects malformed hints
before expanding a matrix.

The private cache encoding uses explicit signed LE32 coefficients in upstream
array order. Public: rho32, tr64, t1_d2_hat_mont4096, A16384 (20,576 bytes).
Secret: rho32, K32, tr64, s1_hat_mont4096, s2_hat_mont4096,
t0_hat_mont4096, A16384 (28,800 bytes). The matrix is in the upstream NTT
representation; key polynomials retain their Montgomery representation.

Caches contain no pointer, padding, message, randomness, or evolving state.
No Rust structs are cast onto managed memory. Consumers decode into ordinary
initialized stack objects; upstream zeroization of those temporary objects is
preserved. The protected managed secret cache itself is not securely erased by
GC. Cache bytes are neither an import/export API nor a persistent wire format.
