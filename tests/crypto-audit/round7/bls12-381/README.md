# BLS arithmetic review, round seven

Scope: the selected limb helpers, quadratic and cubic extension multiplication,
and fixed multiplication by the signed BLS parameter. This is an independent
review of these changes, not a full formal cryptographic audit.

**PASS:** frozen integration `56baf39e72d5e80fe0df19affab1f5d46ba6e2d6`,
runtime `d75badd132b617ef215a24e0106a9de823490376f6479ab88baace690e6feb86`,
matching compiler ELF `24d8d0b9…`. The independent run passed **138 vendor
tests, 32 runtime tests, six Motoko programs and six Ash methods**. All 404
plugin build inputs matched in both the integration and audit checkouts;
292 compiler source pins and both plugin artifacts also matched after testing.

## Algebra and input bounds

`sbb(a,b,borrow)` consumes only `borrow >> 63`, a bit `c`. For arbitrary
64-bit `a,b`, the integer difference `a-b-c` lies in `[-2^64,2^64-1]`.
The high half of its wrapped 128-bit representation is therefore either zero
or all ones. If `a<b`, the first subtraction borrows and its wrapped result is
at least one, so subtracting `c` cannot borrow again. Otherwise the second
subtraction borrows exactly when `a=b` and `c=1`. OR-ing the two flags produces
the original high half, including the boundary `0-(2^64-1)-1=-2^64`.
This identity has no reduced-field precondition and also covers Scalar callers.

For multiply-add, write each 64-bit operand in base `q=2^32`. The new sequence is
`L=b0*c0+a0+k0`, `M=b1*c0+floor(L/q)+a1`,
`C=b0*c1+(M mod q)+k1`, and `H=b1*c1+floor(M/q)+floor(C/q)`.
Each sum is at most `(q-1)^2+2(q-1)=q^2-1`, so none overflows a 64-bit word.
Recombining `q^2*H+q*(C mod q)+(L mod q)` cancels the intermediate carries and
gives exactly `b*c+a+k`. No narrower field-specific operand bound is assumed.

Fp2 Karatsuba expands directly in `Fp[u]/(u^2+1)`. Fp6 uses six Fp2 products
in `Fp2[v]/(v^3-(1+u))`. Expanding the three cross products gives the same
coefficients as polynomial multiplication followed by reduction of `v^3` and
`v^4`. These are general-ring identities: they do not assume a nonzero input,
a pairing subgroup, or a cyclotomic element. The previous interleaved formulas
are retained only under `cfg(test)` as differential oracles.

The group schedule starts at integer one, repeatedly shifts by
`[1,2,3,9,32]` and adds one, then shifts by sixteen. Its result is exactly
`0xd201000000010000`; the existing negative sign is preserved. This integer
identity holds on the whole curve. Testing only scalar multiplication modulo
the prime subgroup order would be insufficient because subgroup checks and
cofactor clearing also call this method on points outside that subgroup.

The independent [algebra script](algebra.py) checks all five extension
coefficients symbolically, the exact integer schedule, 131,072 exhaustive
small-word borrow cases and 65,536 exhaustive small-word multiply-add cases.
The small-word tests complement the all-width arguments above; they are not
an exhaustive proof of the 64-bit implementation.

## Preserved contracts

No canonical point decoding, subgroup/nonidentity check, proof-of-possession
requirement, profile domain, batch bound or error-order rule was removed or
reordered. Public APIs, SDK, compiler and prepared payload formats are unchanged.
The prepared readers still rely on validated immutable factory output and
nominal SDK types; arbitrary forged payloads are outside their unsafe contract.
The arithmetic preserves reduced Montgomery representations and remains valid
for the immutable generator table and unaligned prepared readers.

The new arithmetic has no input-dependent branches or table indices. Fixed
group loops depend only on the public curve parameter. Source and isolated
lowering review are not formal timing proofs for every execution engine.
The retained helper assembly contains no branches, loops, calls or selects in
`sbb_new` or `mac_comba`. The complete probe module also contains rejected
screen alternatives; those are not part of the selected runtime.

## Validation

Final commands, source and artifact pins, logs and result counts are recorded
in [the evidence summary](evidence/summary.json). Tests include:

- The complete vendored arithmetic/group suite and plugin runtime suite using
  the original matching Rust 1.99 toolchain.
- Independent whole-curve tests with 32 random on-curve points per group,
  confirmed nonsubgroup coverage, negatives, homogeneous rescaling,
  cofactor-cleared points and identity. The reference is signed integer
  double-and-add, not multiplication by a reduced Scalar.
- Fp2/Fp6 differential oracles on zero, signed basis elements and random fields;
  arbitrary-limb borrow and multiply-add edge/random cases; existing full
  final-exponentiation and domain/decoding/prepared-layout regressions.
- Six public Motoko programs through interpreters and compiled Wasm, plus
  the two public Ash BLS suites on PocketIC.

Performance measurements are maintained separately in the round-seven
benchmark report. Passing algebra and correctness tests does not establish
an instruction-cost improvement.
