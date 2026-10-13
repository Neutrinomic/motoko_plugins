use super::*;
use crate::{multi_miller_loop as upstream_miller_loop, G1Projective, Gt, Scalar};
use alloc::vec::Vec;

fn assert_reduced_limbs(bytes: &[u8]) {
    // BLS12-381 base-field modulus, encoded big-endian independently of Fp.
    let modulus = hex::decode(concat!(
        "1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241",
        "eabfffeb153ffffb9feffffffffaaab"
    ))
    .unwrap();
    assert_eq!(modulus.len(), FP_BYTES);
    assert_eq!(bytes.len() % FP_BYTES, 0);
    for field in bytes.chunks_exact(FP_BYTES) {
        assert_eq!(
            field.iter().rev().cmp(modulus.iter()),
            core::cmp::Ordering::Less
        );
    }
}

fn table(point: G2Affine) -> [u8; G2_PREPARED_BYTES] {
    let mut bytes = [0xa5; G2_PREPARED_BYTES];
    assert!(write_g2_prepared(&point, &mut bytes));
    bytes
}

#[test]
fn identity_rejection_leaves_output_untouched() {
    let mut g1 = [0xa5; G1_AFFINE_BYTES];
    let mut g2 = [0x5a; G2_PREPARED_BYTES];
    assert!(!write_g1_affine(&G1Affine::identity(), &mut g1));
    assert!(!write_g2_prepared(&G2Affine::identity(), &mut g2));
    assert_eq!(g1, [0xa5; G1_AFFINE_BYTES]);
    assert_eq!(g2, [0x5a; G2_PREPARED_BYTES]);
}

#[test]
fn g1_coordinates_match_validated_wire_points() {
    let fixture: &[u8] = include_bytes!("tests/g1_compressed_valid_test_vectors.dat");
    for index in [1, 2, 3, 17, 999] {
        let compressed: &[u8; 48] = fixture[index * 48..(index + 1) * 48].try_into().unwrap();
        let point = G1Affine::from_compressed(compressed).unwrap();
        for point in [point, -point] {
            let mut a = [0xa5; G1_AFFINE_BYTES];
            let mut b = [0x5a; G1_AFFINE_BYTES];
            assert!(write_g1_affine(&point, &mut a));
            assert!(write_g1_affine(&point, &mut b));
            assert_eq!(a, b);
            assert_reduced_limbs(&a);
            let restored = read_g1_affine_trusted(&a);
            assert_eq!(restored, point);
            assert_eq!(restored.to_compressed(), point.to_compressed());
            for (field, expected) in a.chunks_exact(FP_BYTES).zip([point.x, point.y]) {
                for (word, expected) in field.chunks_exact(8).zip(expected.0) {
                    assert_eq!(word, expected.to_le_bytes());
                }
            }
        }
    }
    let point = G1Affine::from(G1Projective::generator() * -Scalar::one());
    let mut bytes = [0; G1_AFFINE_BYTES];
    assert!(write_g1_affine(&point, &mut bytes));
    assert_eq!(read_g1_affine_trusted(&bytes), point);
}

#[test]
fn all_coefficients_match_upstream_preparation() {
    let fixture: &[u8] = include_bytes!("tests/g2_compressed_valid_test_vectors.dat");
    for index in [1, 2, 3, 17, 999] {
        let compressed: &[u8; 96] = fixture[index * 96..(index + 1) * 96].try_into().unwrap();
        let point = G2Affine::from_compressed(compressed).unwrap();
        for point in [point, -point] {
            let owned = G2Prepared::from(point);
            let a = table(point);
            let mut b = [0x5a; G2_PREPARED_BYTES];
            assert!(write_g2_prepared(&point, &mut b));
            assert_eq!(a, b);
            assert_reduced_limbs(&a);
            assert_eq!(owned.coeffs.len(), COEFFICIENT_COUNT);
            for (chunk, expected) in a.chunks_exact(COEFFICIENT_BYTES).zip(&owned.coeffs) {
                assert_eq!(read_coefficient_trusted(chunk), *expected);
                let fields = [
                    expected.0.c0,
                    expected.0.c1,
                    expected.1.c0,
                    expected.1.c1,
                    expected.2.c0,
                    expected.2.c1,
                ];
                for (field, expected) in chunk.chunks_exact(FP_BYTES).zip(fields) {
                    for (word, expected) in field.chunks_exact(8).zip(expected.0) {
                        assert_eq!(word, expected.to_le_bytes());
                    }
                }
            }
        }
    }
}

#[test]
fn writers_and_readers_accept_every_alignment_without_overrun() {
    let p = G1Affine::generator();
    let q = G2Affine::from(G2Projective::generator() * Scalar::from(u64::MAX));
    let expected = upstream_miller_loop(&[(&p, &G2Prepared::from(q))]).final_exponentiation();
    for offset in 0..8 {
        let mut g1_guard = [0xa5; G1_AFFINE_BYTES + 16];
        let mut g2_guard = [0x5a; G2_PREPARED_BYTES + 16];
        let g1: &mut [u8; G1_AFFINE_BYTES] = (&mut g1_guard[offset..offset + G1_AFFINE_BYTES])
            .try_into()
            .unwrap();
        assert!(write_g1_affine(&p, g1));
        assert_eq!(read_g1_affine_trusted(g1), p);
        let g2: &mut [u8; G2_PREPARED_BYTES] = (&mut g2_guard[offset..offset + G2_PREPARED_BYTES])
            .try_into()
            .unwrap();
        assert!(write_g2_prepared(&q, g2));
        assert_eq!(
            multi_miller_loop(&[(&p, G2PreparedSource::TrustedBytes(g2))]).final_exponentiation(),
            expected
        );
        assert!(g1_guard[..offset].iter().all(|&byte| byte == 0xa5));
        assert!(g1_guard[offset + G1_AFFINE_BYTES..]
            .iter()
            .all(|&byte| byte == 0xa5));
        assert!(g2_guard[..offset].iter().all(|&byte| byte == 0x5a));
        assert!(g2_guard[offset + G2_PREPARED_BYTES..]
            .iter()
            .all(|&byte| byte == 0x5a));
    }
}

#[test]
fn borrowed_and_mixed_loops_match_upstream_across_batch_sizes() {
    let points = [
        G1Affine::generator(),
        G1Affine::from(G1Projective::generator() * Scalar::from(17)),
        -G1Affine::generator(),
    ];
    let qs = [
        G2Affine::generator(),
        -G2Affine::generator(),
        G2Affine::from(G2Projective::generator() * Scalar::from(u64::MAX)),
    ];
    let owned = qs.map(G2Prepared::from);
    let bytes = qs.map(table);
    for count in [0, 1, 2, 8, 127, 128] {
        let ordinary: Vec<_> = (0..count)
            .map(|i| (&points[i % 3], &owned[(i / 3) % 3]))
            .collect();
        let borrowed: Vec<_> = (0..count)
            .map(|i| {
                (
                    &points[i % 3],
                    G2PreparedSource::TrustedBytes(&bytes[(i / 3) % 3]),
                )
            })
            .collect();
        let mut mixed: Vec<_> = (0..count)
            .map(|i| {
                (
                    &points[i % 3],
                    if i % 2 == 0 {
                        G2PreparedSource::Owned(&owned[(i / 3) % 3])
                    } else {
                        G2PreparedSource::TrustedBytes(&bytes[(i / 3) % 3])
                    },
                )
            })
            .collect();
        let expected = upstream_miller_loop(&ordinary).final_exponentiation();
        assert_eq!(
            multi_miller_loop(&borrowed).final_exponentiation(),
            expected
        );
        assert_eq!(multi_miller_loop(&mixed).final_exponentiation(), expected);
        mixed.reverse();
        assert_eq!(multi_miller_loop(&mixed).final_exponentiation(), expected);
    }
}

#[test]
fn neutral_and_cancelling_terms_preserve_pairing_semantics() {
    let p = G1Affine::generator();
    let minus_p = -p;
    let zero_p = G1Affine::identity();
    let q = G2Affine::generator();
    let owned = G2Prepared::from(q);
    let zero_q = G2Prepared::from(G2Affine::identity());
    let bytes = table(q);
    assert_eq!(
        multi_miller_loop(&[]).final_exponentiation(),
        Gt::identity()
    );
    assert_eq!(
        multi_miller_loop(&[
            (&p, G2PreparedSource::TrustedBytes(&bytes)),
            (&minus_p, G2PreparedSource::Owned(&owned)),
            (&zero_p, G2PreparedSource::TrustedBytes(&bytes)),
            (&p, G2PreparedSource::Owned(&zero_q)),
        ])
        .final_exponentiation(),
        Gt::identity()
    );
    let expected = crate::pairing(&p, &q);
    assert_eq!(
        multi_miller_loop(&[
            (&zero_p, G2PreparedSource::Owned(&owned)),
            (&p, G2PreparedSource::Owned(&zero_q)),
            (&p, G2PreparedSource::TrustedBytes(&bytes)),
        ])
        .final_exponentiation(),
        expected
    );
}
