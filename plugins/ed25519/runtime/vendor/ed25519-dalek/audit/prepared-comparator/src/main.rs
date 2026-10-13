//! Differential checks against the untouched registry crates, with distinct
//! Cargo source identities. Run with both serial32 and serial64 configurations.
use curve_candidate::{
    edwards::{CompressedEdwardsY, PreparedVartimeEdwardsTable},
    scalar::Scalar,
};
use curve_original::{constants::EIGHT_TORSION, edwards::EdwardsPoint, traits::Identity};
use ed_candidate::Signer;
use sha2::Sha512;

fn canonical_field(bytes: &[u8]) -> bool {
    let mut p = [255u8; 32];
    p[0] = 237;
    p[31] = 127;
    bytes.iter().rev().cmp(p.iter().rev()).is_lt()
}

fn table_checks() -> (usize, usize, usize) {
    let mut points = vec![EdwardsPoint::identity()];
    points.extend(EIGHT_TORSION);
    for i in 1..=8u64 {
        let prime_point = EdwardsPoint::mul_base(&curve_original::scalar::Scalar::from(i));
        points.push(prime_point);
        for torsion in EIGHT_TORSION {
            points.push(prime_point + torsion);
            points.push(-(prime_point + torsion));
        }
    }
    let mut scalars: Vec<curve_original::scalar::Scalar> =
        [0u64, 1, 2, 7, 8, 15, 16, 255, 256, u64::MAX]
            .into_iter()
            .map(curve_original::scalar::Scalar::from)
            .collect();
    scalars.push(-curve_original::scalar::Scalar::ONE);
    scalars.push(curve_original::scalar::Scalar::from_bytes_mod_order(
        [255; 32],
    ));
    for bit in [31, 32, 63, 64, 127, 128, 191, 192, 251, 252] {
        let mut bytes = [0u8; 32];
        bytes[bit / 8] = 1 << (bit % 8);
        scalars.push(curve_original::scalar::Scalar::from_bytes_mod_order(bytes));
    }
    let mut comparisons = 0;
    let mut canonical_fields = 0;
    for original_point in &points {
        let point = CompressedEdwardsY(original_point.compress().to_bytes())
            .decompress()
            .unwrap();
        let prepared = PreparedVartimeEdwardsTable::from_point(&point);
        let encoded = prepared.to_bytes();
        for field in encoded.chunks_exact(32) {
            assert!(canonical_field(field));
            canonical_fields += 1;
        }
        let restored = PreparedVartimeEdwardsTable::from_trusted_bytes(&encoded);
        assert_eq!(restored.to_bytes(), encoded);
        for (i, a_original) in scalars.iter().enumerate() {
            let b_original = &scalars[(i * 7 + 3) % scalars.len()];
            let a = Scalar::from_canonical_bytes(a_original.to_bytes()).unwrap();
            let b = Scalar::from_canonical_bytes(b_original.to_bytes()).unwrap();
            let expected = EdwardsPoint::vartime_double_scalar_mul_basepoint(
                a_original,
                original_point,
                b_original,
            )
            .compress()
            .to_bytes();
            assert_eq!(
                prepared
                    .vartime_double_scalar_mul_basepoint(&a, &b)
                    .compress()
                    .to_bytes(),
                expected
            );
            assert_eq!(
                restored
                    .vartime_double_scalar_mul_basepoint(&a, &b)
                    .compress()
                    .to_bytes(),
                expected
            );
            comparisons += 2;
        }
        assert_eq!(restored.to_bytes(), encoded);
    }
    // Reducing -k modulo L before multiplication loses the torsion component.
    // This catches the tempting but invalid substitution for mixed-order keys.
    for torsion in &EIGHT_TORSION[1..] {
        let point = curve_original::constants::ED25519_BASEPOINT_POINT + torsion;
        assert_ne!(
            ((-curve_original::scalar::Scalar::ONE) * point).compress(),
            (-point).compress()
        );
    }
    (points.len(), comparisons, canonical_fields)
}

fn signing_checks() -> (usize, usize) {
    let lengths = [0usize, 1, 31, 32, 127, 128, 129, 1024, 4096];
    let mut comparisons = 0;
    let mut public_keys = 0;
    for seed_index in 0..32u8 {
        let mut seed = [0u8; 32];
        for (i, byte) in seed.iter_mut().enumerate() {
            *byte = match seed_index {
                0 => 0,
                1 => 255,
                _ => seed_index
                    .wrapping_mul(47)
                    .wrapping_add((i as u8).wrapping_mul(29)),
            };
        }
        let original = ed_original::SigningKey::from_bytes(&seed);
        let candidate = ed_candidate::SigningKey::from_bytes(&seed);
        let expanded = ed_candidate::hazmat::ExpandedSecretKey::from(&seed);
        let public_key = candidate.verifying_key().to_bytes();
        assert_eq!(public_key, original.verifying_key().to_bytes());
        assert_eq!(
            public_key,
            curve_candidate::edwards::EdwardsPoint::mul_base(&expanded.scalar)
                .compress()
                .to_bytes()
        );
        public_keys += 2;

        // Model the protected 96-byte payload. The stored scalar is already
        // reduced, so restore it canonically; calling from_bytes would reclamp.
        let mut encoded = [0u8; 96];
        encoded[..32].copy_from_slice(&expanded.scalar.to_bytes());
        encoded[32..64].copy_from_slice(&expanded.hash_prefix);
        encoded[64..].copy_from_slice(&public_key);
        let scalar_bytes: [u8; 32] = encoded[..32].try_into().unwrap();
        let restored = ed_candidate::hazmat::ExpandedSecretKey {
            scalar: Scalar::from_canonical_bytes(scalar_bytes).unwrap(),
            hash_prefix: encoded[32..64].try_into().unwrap(),
        };
        let stored_public_key: &[u8; 32] = encoded[64..].try_into().unwrap();
        for length in lengths {
            let message: Vec<u8> = (0..length)
                .map(|i| (i as u8).wrapping_mul(131).wrapping_add(seed_index))
                .collect();
            let expected = original.sign(&message);
            let direct = candidate.sign(&message);
            let prepared = restored.sign_prepared::<Sha512>(&message, stored_public_key);
            assert_eq!(direct.to_bytes(), expected.to_bytes());
            assert_eq!(prepared.to_bytes(), expected.to_bytes());
            original
                .verifying_key()
                .verify_strict(&message, &prepared)
                .unwrap();
            candidate
                .verifying_key()
                .verify_strict(&message, &expected)
                .unwrap();
            comparisons += 2;
        }
    }
    (comparisons, public_keys)
}

fn main() {
    let (table_points, table_comparisons, canonical_fields) = table_checks();
    let (signature_comparisons, public_key_comparisons) = signing_checks();
    println!("{{\"status\":\"passed\",\"table_points\":{table_points},\"table_comparisons\":{table_comparisons},\"canonical_fields\":{canonical_fields},\"signature_comparisons\":{signature_comparisons},\"public_key_comparisons\":{public_key_comparisons},\"cross_verifications\":576,\"mixed_order_negation_regressions\":7}}");
}
