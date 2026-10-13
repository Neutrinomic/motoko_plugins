# Ed25519 projective equality review

Source review of the round4 candidate based on `0e1e96a`.
Reviewed runtime SHA-256: `f4cd810a2765967f9ebf9de4db86b5890288634f8b977aca2fb5c49b43c95829`.
This review made no production edits and ran no builds or tests. The regression
checks below remain gates for the implementation owner and independent auditor.

The candidate retains the decoded `R` point and canonical `S` scalar from
signature validation. Both direct and prepared verification then compare the
computed Edwards point with `R`, using Dalek's existing equality implementation.
It removes a discarded scalar parse/reduction and the final point compression;
it does not remove input validation or change the verification equation.

## Why the comparisons are equivalent

Let `r` be the signature's first 32 bytes, `D` be Edwards decompression, and `C`
be canonical compression. Before either comparison the existing parser requires
exactly 64 signature bytes, canonical `y < 2^255 - 19`, successful decompression,
a non-small-order `R`, and `0 <= S < L`.

For every accepted `r`, `C(D(r)) = r`: canonical `y` excludes field-reduction
aliases; the sign bit selects one root; and `x = 0` points have small order and
are rejected, including their invalid negative-zero encodings. Therefore for a
valid computed point `P`, `C(P) == r` holds exactly when `P == D(r)`. The original
comparison and the candidate have identical truth values. This argument depends
on keeping the canonical and small-order checks; permissive ZIP-215 decoding
alone would not suffice.

Dalek's `EdwardsPoint::PartialEq` delegates to its existing projective equality:
it compares `X1*Z2` with `X2*Z1`, and `Y1*Z2` with `Y2*Z1`. This uses four field
multiplications without inversion. Its `compress` method instead inverts `Z`
before extracting affine coordinates. Valid input points and Dalek's complete
point operations preserve the projective-coordinate invariants needed by this
comparison. The prepared table remains trusted constructor-produced data.
[Upstream Edwards implementation](https://raw.githubusercontent.com/dalek-cryptography/curve25519-dalek/curve25519-4.1.3/curve25519-dalek/src/edwards.rs).

## Scalars, errors and mixed-order points

The candidate keeps the actual `Scalar` returned by `from_canonical_bytes`,
whose successful result already proves `S < L`. The previous parser discarded
this value, then direct verification parsed it again or prepared verification
reduced its bytes again. Keeping the successful result preserves `S` exactly;
replacing validation with unconditional modular reduction would be incorrect.
[Upstream scalar implementation](https://raw.githubusercontent.com/dalek-cryptography/curve25519-dalek/curve25519-4.1.3/curve25519-dalek/src/scalar.rs).

The challenge is still `SHA512(r || A || message) mod L`, using the original
validated compressed bytes. Direct verification computes `[k](-A) + [S]B`;
prepared verification uses its existing table of odd multiples of `-A`. No
cofactor multiplication or subgroup restriction is introduced. In particular,
it must not substitute `[(-k mod L)]A`: that is different on accepted mixed-order
keys. Point equality tests the full Edwards group equation, including torsion,
so strict-valid mixed-order signatures remain valid and cofactored-only
signatures remain `#ok(false)`.
[Dalek verification contract](https://docs.rs/ed25519-dalek/2.2.0/ed25519_dalek/struct.VerifyingKey.html#method.verify_strict).

Direct verification still validates the public key first, preserving
`#err(#invalidPublicKey)` when both key and signature are malformed. Signature
length, noncanonical/off-curve/small-order `R`, and noncanonical `S` still produce
`#err(#invalidSignature)`. A well-formed equation mismatch remains `#ok(false)`.
Prepared keys already passed the same public-key checks in their factory.

## Required regression checks

Use the unchanged [290-case independent corpus](../../../../tests/crypto-audit/round3/ed25519/vectors/cases.json)
through direct and prepared APIs, including:

- `mixed-order-0-True` through `mixed-order-7-True`, and every corresponding
  `False` case: full-group equality and point-negation semantics.
- `small-order-r-0` through `small-order-r-7`, every `noncanonical-r-*`,
  `zero-x-sign-r-*`, and `off-curve-r`: canonical-encoding prerequisites.
- `scalar-0`, scalar `L-1`, `L`, `L+1`, `2L`, maximal 256-bit scalar, and
  `scalar-malleation-add-L`: preserve false-versus-error classification.
- `bad-key-before-bad-sig` and all key/signature length cases: error precedence.

Retain all five RFC8032 vectors, independent OpenSSL signing/verification,
existing signature-byte mutations, and portable interpreter parity. Add an
explicit high sign-bit flip of the `R` component of a valid RFC signature:
its opposite point is well-formed and must remain a mismatch, not an error.
For every successfully parsed signature in the corpus, compare the candidate's
point predicate with the previous compressed-byte predicate in an independent
native check; this directly tests the changed identity on ordinary and
mixed-order points. Keep the recorded signature-error checks separate rather
than collapsing both errors and mismatches into a single boolean.

Measure direct and prepared verification on the same fixtures after correctness
gates. No speedup is claimed by this source review. Prepared table decoding and
its explicit byte format are unchanged in this candidate; apparent stack-copy
cleanup there should be measured separately because LLVM may already remove it.
