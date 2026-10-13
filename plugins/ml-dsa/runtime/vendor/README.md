# fips204 prepared-key hooks

`fips204/` is the published `fips204` 0.4.6 crate, MIT OR Apache-2.0,
from upstream commit `8d456d989dce681233ef963d3c3306da8f76d7c7`.
Published crate SHA-256:
`c9fb5a367b9846933e271a3c2a992930743f82ae5e8cb7faa780715a80fa0b15`.

Local changes are confined to `src/lib.rs`, `src/ml_dsa.rs`, and the new
`src/motoko_prepared.rs`. The existing arithmetic, NTT, hashing, encoding,
rejection sampling, and acceptance rules are unchanged. Existing entry points
call the same bodies with no cached matrix. The prepared factories retain the
matrix from key generation through an optional output (the direct path still
returns only its original key pair) or expand a public key once; consumers pass it to
those same algorithm bodies. Direct verification still rejects malformed hints
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
