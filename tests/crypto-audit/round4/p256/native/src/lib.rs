#[cfg(test)]
#[path = "../../../../../../plugins/p256/runtime/src/lib.rs"]
mod candidate;

#[cfg(test)]
mod audit {
    use super::candidate;
    use p256::elliptic_curve::ff::PrimeField;
    use p256::Scalar;

    fn hex(text: &str) -> Vec<u8> {
        text.as_bytes().chunks_exact(2).map(|v| {
            u8::from_str_radix(core::str::from_utf8(v).unwrap(), 16).unwrap()
        }).collect()
    }

    fn corpus() -> serde_json::Value {
        serde_json::from_str(include_str!("../../vectors.json")).unwrap()
    }

    #[test]
    fn scalar_inverse_matches_independent_integer_values() {
        for row in corpus()["inverse"].as_array().unwrap() {
            let bytes: [u8; 32] = hex(row["input"].as_str().unwrap()).try_into().unwrap();
            let scalar = Scalar::from_repr(bytes.into()).unwrap();
            assert_eq!(&scalar.square().to_repr()[..], hex(row["square"].as_str().unwrap()));
            let inverse = scalar.invert();
            if row["inverse"].is_null() {
                assert!(bool::from(inverse.is_none()));
            } else {
                assert_eq!(&inverse.unwrap().to_repr()[..], hex(row["inverse"].as_str().unwrap()));
                assert_eq!(scalar * inverse.unwrap(), Scalar::ONE);
            }
        }
    }

    #[test]
    fn generator_boundaries_match_independent_affine_arithmetic() {
        for (index, row) in corpus()["derive"].as_array().unwrap().iter().enumerate() {
            let secret = hex(row["secret"].as_str().unwrap());
            let compressed = index % 31 != 0;
            let expected = hex(row[if compressed { "public" } else { "uncompressed" }].as_str().unwrap());
            let mut out = vec![0xa5; expected.len() + 2];
            assert_eq!(unsafe { candidate::p256_public_key(
                secret.as_ptr(), secret.len(), u64::from(compressed), out.as_mut_ptr().add(1)) },
                expected.len() as i64, "{}", row["label"]);
            assert_eq!(&out[1..out.len() - 1], expected);
            assert_eq!(out[0], 0xa5);
            assert_eq!(out[out.len() - 1], 0xa5);
        }
    }

    #[test]
    fn signing_matches_independent_hmac_integer_and_openssl_vectors() {
        for row in corpus()["sign"].as_array().unwrap() {
            let secret = hex(row["secret"].as_str().unwrap());
            let digest = hex(row["digest"].as_str().unwrap());
            let expected = hex(row["signature"].as_str().unwrap());
            let mut out = [0xa5; 66];
            assert_eq!(unsafe { candidate::p256_sign_prehash(
                secret.as_ptr(), secret.len(), digest.as_ptr(), digest.len(), out.as_mut_ptr().add(1)) }, 64);
            assert_eq!(&out[1..65], expected, "{}", row["label"]);
            assert_eq!(out[0], 0xa5);
            assert_eq!(out[65], 0xa5);
        }
    }

    #[test]
    fn direct_and_prepared_equations_match_independent_integer_oracle() {
        for row in corpus()["verify"].as_array().unwrap() {
            let public = hex(row["public"].as_str().unwrap());
            let digest = hex(row["digest"].as_str().unwrap());
            let signature = hex(row["signature"].as_str().unwrap());
            let expected = i64::from(row["expected"].as_bool().unwrap());
            // Prepared layout is intentionally unchanged in this round.
            let mut prepared = vec![0xa5; 16_320 + 2];
            unsafe {
                assert_eq!(candidate::p256_prepare_public_key(public.as_ptr(), public.len(),
                    prepared.as_mut_ptr().add(1)), 16_320);
                assert_eq!(candidate::p256_verify_prehash(public.as_ptr(), public.len(),
                    digest.as_ptr(), digest.len(), signature.as_ptr(), signature.len()), expected, "{}", row["label"]);
                let before = prepared.clone();
                assert_eq!(candidate::p256_verify_prehash_prepared(prepared.as_ptr().add(1),
                    digest.as_ptr(), digest.len(), signature.as_ptr(), signature.len()), expected, "{}", row["label"]);
                assert_eq!(before, prepared);
            }
            assert_eq!(prepared[0], 0xa5);
            assert_eq!(prepared[16_321], 0xa5);
        }
    }
}
