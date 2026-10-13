# BLS verification arithmetic review

Scope: the direct Fp subtraction, widening multiply-add, final exponentiation
schedule, and direct second Frobenius map introduced in round six. No changes
to decoding, subgroup or identity validation, signature domains, prepared-key
layout, public API, or SDK are included.

Run the independent Python check against the candidate source:

```sh
python3 tests/crypto-audit/round6/bls12-381/algebra.py \
  plugins/bls12-381/runtime/vendor/bls12_381
```

The script uses Python integers and symbolic polynomials, not the Rust field
implementation. It checks exact equality of the previous and replacement hard
exponents, derives all four Montgomery constants by exponentiating `1+u` in
Fp2, checks the omitted `j=3` constant is `-1`, and checks the fixed exponent
bits. The signed curve parameter is `x = -0xd201000000010000`.

The extension basis is `[1,v,v²,w,vw,v²w]`, where `w²=v` and `v³=1+u`.
The exponents of `w` are therefore `[0,2,4,1,3,5]`. Since Fp2 is fixed by
the second Frobenius, each coefficient is scaled by
`(1+u)^(j*(p²-1)/6)`. All these factors are in Fp. The production basis
placement was also compared with this derivation; the Rust tests exercise all
twelve individual base-field coordinates, both signs, and random fields.

The hard-part schedule follows the
[pinned arkworks implementation](https://github.com/arkworks-rs/algebra/blob/4a19a1c50606ae4a0e96ccce107f6281aa0be38e/ec/src/models/bls12/mod.rs),
which cites [ePrint 2020/875](https://eprint.iacr.org/2020/875).
Both schedules have exactly the polynomial
`3 + (x-1)²*(p+x)*(p²+x²-1)` after the common easy part; equivalence is not
limited to equality tests against the group identity. The retained Rust oracle
compares complete final-exponentiation outputs on arbitrary nonzero fields.

For direct subtraction, reduced operands imply `-p < a-b < p`. Subtracting
six limbs and adding `p` under the borrow mask therefore returns a reduced
result. Arbitrary limbs in `from_bytes` and `from_u768` pass through Montgomery
multiplication by reduced R2/R3 before field subtraction. Other arithmetic,
production constants, and protected prepared-key readers preserve the reduced
representation. Prepared readers remain restricted to validated factory output.

For widening multiply-add, write each operand in base `q=2³²`. The four partial
products and the two intermediate cross sums fit in 64 bits. They reconstruct
the low and high halves of the exact product. Adding `a` and `carry` to the low
half contributes their two overflow bits to the high half. That final addition
cannot overflow: for arbitrary 64-bit inputs,
`a + b*c + carry <= (2⁶⁴-1)² + 2*(2⁶⁴-1) = 2¹²⁸-1`.
This helper is shared by Fp and Scalar, so validation includes the complete
vendor suite and runtime scalar/group operations, not only IC signatures.

The new field operations are fixed straight-line arithmetic without
input-dependent indexing. Exponentiation loops use only fixed public constants.
This is a source-level constant-time review, not a formal timing proof for every
compiler or execution engine. No validation check was removed for performance.

## Validation on the combined candidate

[Recorded results, commands and hashes](evidence/summary.json) identify clean
candidate `429eed269a58481be04cac7ef07097bc03261c54`, the original matching
compiler `9f6ebeedc` / ELF `24d8d0b9…`, and runtime `a2b0689d…`.
All 404 build source pins and both plugin artifact hashes were checked after
public tests completed.

- 133 vendored arithmetic/group tests and 32 plugin runtime tests passed on
  the runtime's Rust `1.99.0-nightly (da86f4d07 2026-07-24)` toolchain.
- Six Motoko programs passed through the interpreter, IR interpreters and
  compiled Wasm, with runtime sanity checks enabled.
- Six public BLS methods passed on PocketIC using the Ash source checkout.
  The installed Ash binary lacks `mocArgs` support and rejected configuration
  before execution; the source checkout supports the existing test configs.
- The independent algebra check passed.

An isolated lowering probe extracts the exact candidate multiply-add and
subtraction expressions and compiles them using the matching toolchain,
custom wasm64 target and release optimization settings. The retained
[Wasm text](evidence/lowering-probe.wat) contains no branches, loops, calls or
selects in either arithmetic body. This checks those expressions' lowering;
it is not a formal timing proof for the complete linked verifier.

The retained native logs include existing upstream `cfg(std)` and deprecated
`generic-array` warnings. This review did not update dependencies.
