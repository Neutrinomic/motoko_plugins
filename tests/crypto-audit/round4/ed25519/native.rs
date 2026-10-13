// Execute the existing initialization, aliasing, independent signing and strict
// prepared-key corpus against this worktree's runtime without modifying its log.
#[path = "../../prepared/ed25519/native.rs"]
mod prepared_regression;

#[cfg(test)]
mod equality {
    use curve25519_dalek::{edwards::{CompressedEdwardsY, EdwardsPoint, PreparedVartimeEdwardsTable}, scalar::Scalar};
    use ed25519_dalek::{Signature, VerifyingKey};
    use sha2::{Digest, Sha512};

    fn bytes(hex: &str) -> Vec<u8> {
        (0..hex.len()).step_by(2).map(|i| u8::from_str_radix(&hex[i..i+2],16).unwrap()).collect()
    }

    fn compare(key: &[u8], message: &[u8], signature: &[u8], expected: bool) {
        let key = VerifyingKey::from_bytes(key.try_into().unwrap()).unwrap();
        let r: [u8;32] = signature[..32].try_into().unwrap();
        let decoded = CompressedEdwardsY(r).decompress().unwrap();
        assert!(!key.is_weak() && !decoded.is_small_order());
        // This round-trip checks the prerequisite for replacing byte equality.
        assert_eq!(decoded.compress().to_bytes(), r);
        let s = Option::<Scalar>::from(Scalar::from_canonical_bytes(signature[32..].try_into().unwrap())).unwrap();
        let mut hash = Sha512::new();
        hash.update(r); hash.update(key.as_bytes()); hash.update(message);
        let k = Scalar::from_bytes_mod_order_wide(&hash.finalize().into());
        let minus_a = -key.to_edwards();
        let point = EdwardsPoint::vartime_double_scalar_mul_basepoint(&k, &minus_a, &s);
        let table = PreparedVartimeEdwardsTable::from_point(&minus_a);
        let restored = PreparedVartimeEdwardsTable::from_trusted_bytes(&table.to_bytes());
        let prepared_point = restored.vartime_double_scalar_mul_basepoint(&k, &s);
        assert_eq!(point, prepared_point);
        assert_eq!(point == decoded, point.compress().to_bytes() == r);
        assert_eq!(prepared_point == decoded, prepared_point.compress().to_bytes() == r);
        assert_eq!(point == decoded, expected);
        assert_eq!(key.verify_strict(message, &Signature::from_slice(signature).unwrap()).is_ok(), expected);
    }

    #[test]
    fn compressed_and_projective_predicates_agree_including_mixed_order() {
        let corpus: serde_json::Value = serde_json::from_str(include_str!("../../round3/ed25519/vectors/cases.json")).unwrap();
        let (mut accepted, mut mismatch, mut sign_flips) = (0, 0, 0);
        for row in corpus["cases"].as_array().unwrap() {
            let expected = match row["expected"].as_str().unwrap() {
                "true" => {accepted += 1; true}, "false" => {mismatch += 1; false}, _ => continue,
            };
            let key = bytes(row["publicKey"].as_str().unwrap());
            let message = bytes(row["message"].as_str().unwrap());
            let signature = bytes(row["signature"].as_str().unwrap());
            compare(&key, &message, &signature, expected);
            if expected {
                let mut opposite = signature;
                opposite[31] ^= 0x80;
                compare(&key, &message, &opposite, false);
                sign_flips += 1;
            }
        }
        assert_eq!((accepted, mismatch, sign_flips), (96, 22, 96));
    }
}
