# BLS round-four candidates

Baseline: plugins `0e1e96a`, compiler `9f6ebeedc` / ELF `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`, original RTS. Previous prepared tables, fused aggregate wrappers and the immutable G2 generator table are already included. No SDK change is proposed.

## 1. Reuse the existing fixed exponentiation chain

The vendored [upstream chain](https://github.com/zkcrypto/bls12_381/blob/7de7b9d9c509b9973b35a3241b74bbbea95e700a/src/hash_to_curve/chain.rs) already evaluates `x^e`, where `e = (p - 3) / 4`, with a fixed sequence of squarings and multiplications. The [field decoding implementation](https://github.com/zkcrypto/bls12_381/blob/7de7b9d9c509b9973b35a3241b74bbbea95e700a/src/fp.rs) currently uses binary exponentiation for other constant exponents. Reuse the chain for:

- Fp square root: `x^(e+1) = x^((p+1)/4)`.
- Fp inversion: `x^(4e+1) = x^(p-2)`.
- Fp2 square-root first power: `x^e`.
- Fp2 square-root second power: `x^(2e+1) = x^((p-1)/2)`.

These are exact nonnegative integer identities, including at zero; they do not depend on reducing the exponent modulo a group order. The existing zero/nonresidue predicates, Fp2 special branch and final root check remain unchanged. Exact root parity matters because compressed point decoding chooses a sign from the root.

The single chain body becomes statically generic over Fp/Fp2 square/multiply operations. Its module is available with the existing groups feature; the unrelated hash-to-curve-only chain remains experimental. Binary exponentiation survives only as a test oracle. No dynamic dispatch, heap allocation, prepared layout or public API changes are needed.

Symbolic inspection counts 377 squarings and 80 multiplications in the existing chain. Compared with each binary exponent, the replacements remove 148 field multiplications and 5–7 squarings. These are arithmetic counts, not measured IC instruction savings.

## 2. Conjugate directly in final exponentiation

The current final exponentiation computes six consecutive Frobenius maps. In the quadratic tower `Fp12 = Fp6[w] / (w²-v)`, the `p^6` map fixes Fp6 and sends `w` to `-w`: `(a+bw)^(p^6) = a-bw`. This holds for every Fp12 value, including zero and nonunitary values. A conjugation is therefore an exact replacement. Both [blst](https://github.com/supranational/blst/blob/master/src/pairing.c) and [arkworks](https://github.com/arkworks-rs/algebra/blob/master/ec/src/models/bls12/mod.rs) use this identity in their final-exponentiation entry.

Preserve all remaining inversion and final-exponentiation arithmetic. Test arbitrary field values, basis terms, zero and full old/new final-exponentiation outputs. Measure this increment separately after the chain candidate.

## 3. Stream temporary two-term pairing coefficients

The upstream [pairing implementation](https://github.com/zkcrypto/bls12_381/blob/7de7b9d9c509b9973b35a3241b74bbbea95e700a/src/pairings.rs) already supports a Miller driver that calculates and consumes line coefficients together. A narrow helper for `pair_equal` can hold two bounded projective states and reuse the same doubling/addition/ell/loop functions, retaining the immutable generator table when applicable.

This avoids materializing temporary 19,584-byte coefficient tables for fresh G2 points. Prepared IC and general aggregate table reuse stay unchanged. Anticipated allocation reductions are about 19.6 KB for direct IC and 39.2 KB for direct/prepared Ethereum verification or a PoP check. Actual instructions and allocation must be measured; no speedup is assumed. Reject the candidate if extra driver complexity is not justified.

## Gates and measurement

Screen at most these three candidates, incrementally. Keep each source/artifact stage frozen and compare against the current best baseline under the same compiler. Include direct calls, preparation, prepared calls, exact retained payload, allocated bytes and Wasm size. Final selected workloads require three fresh-canister trials.

Correctness includes independent symbolic chain replay; binary-exponent parity for exact roots, inverses, zero, nonresidues and seeded random fields; six-Frobenius/conjugation equality on general Fp12; raw Miller-result parity for streaming; official IC/Ethereum and independent py_ecc vectors; malformed encodings, subgroup/identity/proof/error-precedence cases; interpreter and validated Wasm parity. Prepared layouts are unchanged, so the existing GC/nominal contracts remain applicable. Independent audit reviews the final candidate before adoption.
