//! Directly exercise both exact vendored backends on the same native target.
//! The separate Motoko suite covers selection and execution on Wasm64.
#![allow(dead_code)]
pub type FieldBytes = k256::FieldBytes;
#[path = "../../../../../../plugins/secp256k1/runtime/vendor/k256/src/arithmetic/field/field_10x26.rs"]
mod field26;
#[path = "../../../../../../plugins/secp256k1/runtime/vendor/k256/src/arithmetic/field/field_5x52.rs"]
mod field52;

#[cfg(test)]
mod tests {
    use super::{field26::FieldElement10x26 as F26, field52::FieldElement5x52 as F52};
    use elliptic_curve::zeroize::Zeroize;
    use num_bigint::BigUint;
    use sha2::{Digest, Sha256};

    fn bytes(n: &BigUint) -> [u8; 32] {
        let mut out = [0; 32];
        let raw = n.to_bytes_be();
        out[32 - raw.len()..].copy_from_slice(&raw);
        out
    }
    fn modulus() -> BigUint {
        (BigUint::from(1u8) << 256usize) - (BigUint::from(1u8) << 32usize) - BigUint::from(977u32)
    }
    fn check(a: F26, b: F52, expected: &BigUint) {
        assert_eq!(&a.normalize().to_bytes()[..], bytes(expected));
        assert_eq!(&b.normalize().to_bytes()[..], bytes(expected));
        assert_eq!(a.normalize_weak().normalize().to_bytes(), a.normalize().to_bytes());
        assert_eq!(b.normalize_weak().normalize().to_bytes(), b.normalize().to_bytes());
        assert_eq!(bool::from(a.normalizes_to_zero()), *expected == BigUint::from(0u8));
        assert_eq!(bool::from(b.normalizes_to_zero()), *expected == BigUint::from(0u8));
    }

    #[test]
    fn full_width_boundaries_and_magnitude_eight_against_bigints() {
        let p = modulus();
        let mut values = vec![BigUint::from(0u8), BigUint::from(1u8), &p - 1u8, &p - 2u8];
        for bit in 0..256usize {
            let n = BigUint::from(1u8) << bit;
            values.extend([&n - 1u8, n.clone(), (&n + 1u8) % &p]);
        }
        for i in 0..2048u32 {
            let digest = Sha256::new().chain_update(b"round3-independent-field26").chain_update(i.to_be_bytes()).finalize();
            values.push(BigUint::from_bytes_be(&digest) % &p);
        }
        for (i, a) in values.iter().enumerate() {
            let b = &values[(i * 983 + 761) % values.len()];
            let a26 = Option::<F26>::from(F26::from_bytes(&bytes(a).into())).unwrap();
            let a52 = Option::<F52>::from(F52::from_bytes(&bytes(a).into())).unwrap();
            let b26 = Option::<F26>::from(F26::from_bytes(&bytes(b).into())).unwrap();
            let b52 = Option::<F52>::from(F52::from_bytes(&bytes(b).into())).unwrap();
            check(a26, a52, a);
            check(a26.add(&b26), a52.add(&b52), &((a + b) % &p));
            check(a26.negate(1), a52.negate(1), &((&p - a) % &p));
            for magnitude in [1u32, 2, 4, 8] {
                let wide26 = a26.mul_single(magnitude);
                let wide52 = a52.mul_single(magnitude);
                let other26 = b26.mul_single(8);
                let other52 = b52.mul_single(8);
                let wide = (a * magnitude) % &p;
                check(wide26, wide52, &wide);
                check(wide26.square(), wide52.square(), &((&wide * &wide) % &p));
                check(wide26.mul(&other26), wide52.mul(&other52), &((&wide * b * 8u8) % &p));
                check(wide26.negate(magnitude), wide52.negate(magnitude), &((&p - &wide) % &p));
            }
        }
        eprintln!("checked {} full-width pairs, four input magnitudes each", values.len());
    }

    #[test]
    fn parse_range_from_u64_and_zeroization() {
        let p = modulus();
        for n in [&p - 1u8, p.clone(), &p + 1u8, (BigUint::from(1u8) << 256usize) - 1u8] {
            assert_eq!(bool::from(F26::from_bytes(&bytes(&n).into()).is_some()), n < p);
            assert_eq!(bool::from(F52::from_bytes(&bytes(&n).into()).is_some()), n < p);
        }
        for n in [0u64, 1, (1 << 26) - 1, 1 << 26, (1 << 52) - 1, 1 << 52, u64::MAX] {
            let mut a = F26::from_u64(n);
            let mut b = F52::from_u64(n);
            check(a, b, &BigUint::from(n));
            a.zeroize(); b.zeroize();
            assert_eq!(a.0, [0u32; 10]);
            assert_eq!(b.0, [0u64; 5]);
        }
    }
}
