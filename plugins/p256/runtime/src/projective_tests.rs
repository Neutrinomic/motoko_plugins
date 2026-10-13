//! Regressions for the inversionless public ECDSA verification predicate.

use super::*;

fn hex(value: &str) -> Vec<u8> {
    (0..value.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&value[i..i + 2], 16).unwrap())
        .collect()
}

fn scalar(value: &str) -> Scalar {
    let bytes: [u8; 32] = hex(value).try_into().unwrap();
    Scalar::from_repr(bytes.into()).unwrap()
}

fn affine_x_matches_scalar(point: &ProjectivePoint, r: &p256::NonZeroScalar) -> bool {
    let affine = point.to_affine();
    !bool::from(affine.is_identity()) && **r == <Scalar as Reduce<U256>>::reduce_bytes(&affine.x())
}

#[test]
fn projective_boundary_vectors_direct_and_prepared() {
    // Generated independently with Python integer affine arithmetic. In each
    // fixture hash=0, s=1, and Q=r^-1 R, so verification reconstructs R exactly.
    let fixtures: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../benchmarks/crypto/round4/p256/projective-check/vectors.json"
    ))
    .unwrap();
    let fixtures = fixtures["vectors"].as_array().unwrap();
    assert_eq!(fixtures.len(), 4);
    for fixture in fixtures {
        let label = fixture["label"].as_str().unwrap();
        let key_bytes = hex(fixture["public_key"].as_str().unwrap());
        let hash = hex(fixture["digest"].as_str().unwrap());
        let sig_bytes = hex(fixture["signature"].as_str().unwrap());
        let target = hex(fixture["computed_point"].as_str().unwrap());
        let expected = fixture["expected_valid"].as_bool().unwrap();
        let key = public(&key_bytes).unwrap();
        let sig = signature(&sig_bytes).unwrap();
        let (r, s) = sig.split_scalars();
        let z = <Scalar as Reduce<U256>>::reduce_bytes(hash.as_slice().into());
        let inverse = *s.invert_vartime();
        let u1 = z * inverse;
        let u2 = *r * inverse;

        for encoded in [key.to_encoded_point(true), key.to_encoded_point(false)] {
            let key_bytes = encoded.as_bytes();
            assert_eq!(
                verify_prehash(key_bytes, &hash, &sig_bytes),
                Ok(expected),
                "direct {label}"
            );
            let mut prepared = [0u8; prepared_table::BYTES];
            assert_eq!(
                prepare_public_key(key_bytes, &mut prepared),
                Ok(prepared_table::BYTES),
                "prepare {label}"
            );
            assert_eq!(
                verify_prehash_prepared(&prepared, &hash, &sig_bytes),
                Ok(expected),
                "prepared {label}"
            );
            for point in [
                verification_lincomb(&u1, &ProjectivePoint::from(*key.as_affine()), &u2),
                verification_prepared(&u1, &prepared, &u2),
            ] {
                assert_eq!(
                    point.to_affine().to_encoded_point(true).as_bytes(),
                    target.as_slice(),
                    "reconstructed point {label}"
                );
                assert_eq!(projective_x_matches_scalar(&point, &r), expected, "{label}");
                assert_eq!(affine_x_matches_scalar(&point, &r), expected, "{label}");
            }
        }
    }
}

#[test]
fn projective_identity_equation_and_zero_r_are_rejected() {
    let key = AffinePoint::GENERATOR.to_encoded_point(true);
    let mut prepared = [0u8; prepared_table::BYTES];
    prepare_public_key(key.as_bytes(), &mut prepared).unwrap();
    // Q=G, z=n-1, r=s=1 gives (n-1)G+G=infinity.
    let hash = (-Scalar::ONE).to_bytes();
    let mut sig = Signature::from_scalars(Scalar::ONE, Scalar::ONE)
        .unwrap()
        .to_bytes();
    assert_eq!(verify_prehash(key.as_bytes(), &hash, &sig), Ok(false));
    assert_eq!(verify_prehash_prepared(&prepared, &hash, &sig), Ok(false));
    let r = p256::NonZeroScalar::new(Scalar::ONE).unwrap();
    for point in [
        ProjectivePoint::IDENTITY,
        verification_lincomb(&-Scalar::ONE, &ProjectivePoint::GENERATOR, &Scalar::ONE),
        verification_prepared(&-Scalar::ONE, &prepared, &Scalar::ONE),
    ] {
        assert!(bool::from(point.to_affine().is_identity()));
        assert!(!projective_x_matches_scalar(&point, &r));
    }

    // The predicate accepts NonZeroScalar; public parsing enforces this invariant.
    sig[..32].fill(0);
    assert_eq!(
        verify_prehash(key.as_bytes(), &hash, &sig),
        Err(INVALID_SIGNATURE)
    );
    assert_eq!(
        verify_prehash_prepared(&prepared, &hash, &sig),
        Err(INVALID_SIGNATURE)
    );
}

#[test]
fn projective_predicate_matches_affine_for_scalar_boundaries() {
    let coefficients = [
        Scalar::ZERO,
        Scalar::ONE,
        Scalar::from(2u64),
        -Scalar::ONE,
        scalar("8000000000000000000000000000000000000000000000000000000000000000"),
        scalar("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"),
    ];
    let boundaries = [
        Scalar::ONE,
        -Scalar::ONE,
        // Immediately below, at, and above the r+n=p boundary.
        scalar("000000000000000000000000000000004319055358e8617b0c46353d039cdaad"),
        scalar("000000000000000000000000000000004319055358e8617b0c46353d039cdaae"),
        scalar("000000000000000000000000000000004319055358e8617b0c46353d039cdaaf"),
        // Immediately below, at, and above the r+n=2^256 boundary.
        scalar("00000000ffffffff00000000000000004319055258e8617b0c46353d039cdaae"),
        scalar("00000000ffffffff00000000000000004319055258e8617b0c46353d039cdaaf"),
        scalar("00000000ffffffff00000000000000004319055258e8617b0c46353d039cdab0"),
    ];
    let mut saw_nonunit_z = false;
    for coefficient in coefficients {
        let point = ProjectivePoint::GENERATOR * coefficient;
        let affine = point.to_affine();
        let matching = <Scalar as Reduce<U256>>::reduce_bytes(&affine.x());
        // Compare the same affine point in normalized and arithmetic-produced
        // representations. A test restricted to Z=1 misses a mistaken Z^2 check.
        for point in [point, ProjectivePoint::from(affine)] {
            let (_, _, z) = point.to_field_coordinates();
            saw_nonunit_z |= !bool::from(z.is_zero()) && z != FieldElement::ONE;
            for candidate in boundaries.into_iter().chain([
                matching,
                matching + Scalar::ONE,
                matching - Scalar::ONE,
            ]) {
                if candidate == Scalar::ZERO {
                    continue;
                }
                let r = p256::NonZeroScalar::new(candidate).unwrap();
                assert_eq!(
                    projective_x_matches_scalar(&point, &r),
                    affine_x_matches_scalar(&point, &r),
                    "coefficient={coefficient:?}, r={candidate:?}"
                );
            }
        }
    }
    assert!(
        saw_nonunit_z,
        "differential cases must include finite Z != 1"
    );
}
