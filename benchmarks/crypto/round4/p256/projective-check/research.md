# P-256 final projective x-coordinate comparison

The final affine inversion in public ECDSA verification can be removed without
changing the verification equation. This review covers the direct and prepared
verification paths. Secret signing and key derivation retain their existing
affine conversions.

## Coordinate convention and proof

The vendored `primeorder/src/projective.rs` represents affine coordinates as
`x = X/Z` and `y = Y/Z`: `to_affine_internal` multiplies both stored coordinates
by the same `zinv`. These are homogeneous coordinates, not Jacobian coordinates.
Consequently, the comparison uses `r*Z`, with no squaring of `Z`.

Let `p` be the P-256 field modulus, `n` the subgroup order, `R=(X:Y:Z)` the
verification result, and `r` a canonically parsed signature scalar. For a valid
signature encoding, `1 <= r < n`. Reject `Z=0` before any coordinate comparison.
For a nonidentity point let `x` be the canonical affine x-coordinate in `[0,p)`.
The P-256 parameters satisfy `n < p < 2n`. Therefore:

```text
r = x mod n
iff x = r OR (r+n < p AND x = r+n)
iff X = r*Z mod p OR (r+n < p AND X = (r+n)*Z mod p).
```

The second equivalence uses the invertibility of nonzero `Z`. It is independent
of which valid homogeneous representative the point arithmetic produces.

The exact difference is:

```text
p-n = 000000000000000000000000000000004319055358e8617b0c46353d039cdaae
```

It has 127 bits. The interval `[n,p)` occupies approximately `7.70e-40` of the
field, so ordinary random tests cannot realistically cover the second candidate.

## Established implementations

Bitcoin Core's [libsecp256k1 ECDSA verification implementation](https://github.com/bitcoin-core/secp256k1/blob/master/src/ecdsa_impl.h)
contains the two-candidate derivation and uses `r < p-n` to guard the second
comparison. Its Jacobian representation requires `Z^2`; only that coordinate
factor differs from this vendored homogeneous representation.

BoringSSL's [P-256 implementation](https://raw.githubusercontent.com/google/boringssl/master/crypto/fipsmodule/ec/p256.cc.inc)
implements `ec_GFp_nistp256_cmp_x_coordinate`, rejects infinity, compares the first
candidate, then adds the group order with a carry and an explicit field bound.
The same checks appear in this [pinned BoringSSL Montgomery implementation](https://boringssl.googlesource.com/boringssl/+/09f7078f953362d5c5afdd224118845327b60fb4/src/crypto/fipsmodule/ec/ec_montgomery.c.inc).
These are established implementation precedents; this document's algebra proves
the adaptation to the local coordinate convention.

## Required implementation details

- Obtain the stored `(X,Y,Z)` with a narrow accessor and reject `Z.is_zero()`.
  Existing `ProjectivePoint::is_identity()` calls projective equality, which
  converts both operands to affine and would reintroduce the inversion.
- Interpret canonical scalar bytes using `FieldElement::from_bytes`. Since
  `r<n<p`, the first conversion is always in range. The field implementation
  converts the integer into Montgomery representation before multiplication.
- Add `r+n` as an integer, using `U256::checked_add` or an equivalent explicit
  carry check. Do not add the order in the scalar field, where it equals zero.
- For the second candidate, require no integer overflow and require the sum
  strictly below `p`. `FieldElement::from_bytes(sum)` enforces the latter bound.
  Reducing the sum modulo `p`, or discarding its carry, accepts invalid signatures.
- The first comparison must remain available when `r+n` is out of range; the
  second-candidate bound cannot reject an otherwise valid first candidate.
- Field equality directly compares the canonical Montgomery limbs. The field
  arithmetic returns reduced values; the new accessor does not import raw input.
  Existing prepared-point imports retain their established canonical-limb
  precondition, which this change does not broaden.
- `r=0`, `s=0`, noncanonical scalars, malformed keys, and malformed digest lengths
  remain the responsibility of the unchanged input validation. The predicate's
  accepted-scalar precondition should be documented if it accepts `Scalar`.

For nonzero `Z`, a zero affine x-coordinate is possible on P-256 but cannot yield
a valid ECDSA signature because its required `r` would be zero. It supplies two
useful negative boundary fixtures below.

## Reproducible boundary vectors

Run from the repository root:

```sh
python3 benchmarks/crypto/round4/p256/projective-check/generate.py \
  --output benchmarks/crypto/round4/p256/projective-check/vectors.json
```

The generator is independent Python integer arithmetic, with no plugin,
RustCrypto, or third-party imports. It checks points on the curve, subgroup
membership, the construction equation, and ordinary affine ECDSA verification.
It does not replace end-to-end verification against the compiled implementations.

For a selected point `R`, choose `s=1`, an all-zero digest, and `Q=r^-1 R`.
Verification then reconstructs `R` exactly, without needing its discrete
logarithm or a signing key. All public keys use canonical compressed SEC1 encoding;
all compact signatures contain 32-byte big-endian `r` followed by `s`.

| Label | Reconstructed affine x | Signature r | Expected | Detects |
|---|---|---|---|---|
| `rare_n_plus_3` | `n+3` | `3` | true | Omitted second candidate, scalar-field addition of n |
| `near_p_minus_3` | `p-3` | `p-n-3` | true | Valid second candidate near field bound |
| `reject_field_wrap` | `0` | `p-n` | false | Reducing `r+n=p` modulo p |
| `reject_limb_wrap` | `0` | `2^256-n` | false | Discarding the carry from `r+n=2^256` |

The generator confirms that points exist at `x=n+3`, `x=p-3`, and `x=0`.
Their exact public keys, digests, signatures, target coordinates, expected results,
and generator SHA-256 are retained in `vectors.json`.

## Differential validation plan

1. Execute all four fixtures through both direct and prepared verification,
   preserving `true` and `false` as distinct outcomes from input errors. Check
   compressed and uncompressed encodings of each public key where practical.
2. Compare the new predicate with the old affine conversion plus scalar reduction
   on identity, generator, its negation, deterministic scalar multiples, and
   points produced by both verification multiplication routines. Include correct
   `r` and nearby incorrect nonzero scalars. Ensure tests include nonunit `Z`;
   affine imports alone have `Z=1` and cannot detect a mistaken `Z^2` formula.
3. Check a verification sum at infinity with `Q=G`, digest `n-1`, `r=1`, `s=1`.
   Both direct and prepared verification must return false.
4. Preserve malformed-input checks, all existing Wycheproof vectors, high-S
   behavior, and signing outputs. Run an independent final oracle against the
   four public fixtures in addition to the generator's affine checks.
5. Measure direct and prepared verification separately. Source inspection or
   emitted-code review should confirm that the final comparison no longer calls
   affine conversion, projective equality, or projective `is_identity()`.

## Expected field work removed

The local `FieldElement::invert_unchecked` addition chain executes exactly 255
squarings and 12 multiplications. `field64::fe_square` delegates to `fe_mul`, so
the inversion comprises 267 multiplication calls. The old affine conversion then
multiplies `X` and `Y` by the inverse and serializes affine x with one Montgomery
reduction; optimization may remove the unused Y multiplication.

The common new path requires one multiplication to convert canonical `r` into
Montgomery form and one for `r*Z`. Its expected savings are therefore 266–267
field multiplication calls plus one Montgomery reduction and scalar-reduction
overhead. A checked second candidate adds up to two more multiplications. These
are source-level counts, not measured instruction or cycle savings; benchmarking
and compiler optimization determine the actual improvement.
