//! Differential tests against the unchanged binary-exponent formulas.
use crate::{fp::Fp, fp2::Fp2};
use rand_core::SeedableRng;
use subtle::{Choice, ConstantTimeEq, CtOption};

const E: [u64; 6] = [
    0xee7f_bfff_ffff_eaaa, 0x07aa_ffff_ac54_ffff,
    0xd9cc_34a8_3dac_3d89, 0xd91d_d2e1_3ce1_44af,
    0x92c6_e9ed_90d2_eb35, 0x0680_447a_8e5f_f9a6,
];
const P_MINUS_2: [u64; 6] = [
    0xb9fe_ffff_ffff_aaa9, 0x1eab_fffe_b153_ffff,
    0x6730_d2a0_f6b0_f624, 0x6477_4b84_f385_12bf,
    0x4b1b_a7b6_434b_acd7, 0x1a01_11ea_397f_e69a,
];
const SEED: [u8; 16] = *b"bls-round4-proof";

fn check_fp(x: Fp) {
    assert_eq!(crate::fp_chain::chain_pm3div4(&x), x.pow_vartime(&E));
    let mut sqrt_exp = E;
    sqrt_exp[0] += 1;
    let old_root = x.pow_vartime(&sqrt_exp);
    let old_valid = old_root.square() == x;
    let root = x.sqrt();
    assert_eq!(bool::from(root.is_some()), old_valid);
    if old_valid { assert_eq!(root.unwrap(), old_root); }
    let inverse = x.invert();
    assert_eq!(bool::from(inverse.is_some()), x != Fp::zero());
    if x != Fp::zero() {
        assert_eq!(inverse.unwrap(), x.pow_vartime(&P_MINUS_2));
        assert_eq!(inverse.unwrap() * x, Fp::one());
    }
}

fn check_fp2(x: Fp2) {
    assert_eq!(crate::fp_chain::chain_pm3div4(&x), x.pow_vartime(&E));
    let old_root = old_fp2_sqrt(&x);
    let root = x.sqrt();
    assert_eq!(bool::from(root.is_some()), bool::from(old_root.is_some()));
    if bool::from(root.is_some()) {
        assert_eq!(root.unwrap(), old_root.unwrap());
        assert_eq!(root.unwrap().square(), x);
    }
}

#[test]
fn fixed_chain_matches_binary_for_edge_cases_and_random_fields() {
    for x in [Fp::zero(), Fp::one(), -Fp::one()] {
        check_fp(x);
        check_fp2(Fp2 { c0: x, c1: Fp::zero() });
        check_fp2(Fp2 { c0: Fp::zero(), c1: x });
    }
    let mut rng = rand_xorshift::XorShiftRng::from_seed(SEED);
    for _ in 0..128 {
        let x = Fp::random(&mut rng);
        check_fp(x);
        check_fp(x.square());
        let y = Fp2::random(&mut rng);
        check_fp2(y);
        check_fp2(y.square());
    }
}

fn old_fp2_sqrt(value: &Fp2) -> CtOption<Fp2> {
        // Algorithm 9, https://eprint.iacr.org/2012/685.pdf
        // with constant time modifications.

        CtOption::new(Fp2::zero(), value.is_zero()).or_else(|| {
            // a1 = value^((p - 3) / 4)
            let a1 = value.pow_vartime(&[
                0xee7f_bfff_ffff_eaaa,
                0x07aa_ffff_ac54_ffff,
                0xd9cc_34a8_3dac_3d89,
                0xd91d_d2e1_3ce1_44af,
                0x92c6_e9ed_90d2_eb35,
                0x0680_447a_8e5f_f9a6,
            ]);

            // alpha = a1^2 * value = value^((p - 3) / 2 + 1) = value^((p - 1) / 2)
            let alpha = a1.square() * value;

            // x0 = value^((p + 1) / 4)
            let x0 = a1 * value;

            // In the event that alpha = -1, the element is order p - 1 and so
            // we're just trying to get the square of an element of the subfield
            // Fp. This is given by x0 * u, since u = sqrt(-1). Since the element
            // x0 = a + bu has b = 0, the solution is therefore au.
            CtOption::new(
                Fp2 {
                    c0: -x0.c1,
                    c1: x0.c0,
                },
                alpha.ct_eq(&(&Fp2::one()).neg()),
            )
            // Otherwise, the correct solution is (1 + alpha)^((q - 1) // 2) * x0
            .or_else(|| {
                CtOption::new(
                    (alpha + Fp2::one()).pow_vartime(&[
                        0xdcff_7fff_ffff_d555,
                        0x0f55_ffff_58a9_ffff,
                        0xb398_6950_7b58_7b12,
                        0xb23b_a5c2_79c2_895f,
                        0x258d_d3db_21a5_d66b,
                        0x0d00_88f5_1cbf_f34d,
                    ]) * x0,
                    Choice::from(1),
                )
            })
            // Only return the result if it's really the square root (and so
            // value is actually quadratic nonresidue)
            .and_then(|sqrt| CtOption::new(sqrt, sqrt.square().ct_eq(value)))
        })
    }

