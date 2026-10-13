use super::*;

fn hex(value: &str) -> Vec<u8> {
    (0..value.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&value[i..i + 2], 16).unwrap())
        .collect()
}
fn fixtures(json: &str) {
    let data: serde_json::Value = serde_json::from_str(json).unwrap();
    for vector in data["vectors"].as_array().unwrap() {
        let seed = hex(vector["seed"].as_str().unwrap());
        let key = hex(vector["publicKey"].as_str().unwrap());
        let message = hex(vector["message"].as_str().unwrap());
        let sig = hex(vector["signature"].as_str().unwrap());
        let mut output_key = [0; 32];
        let mut output_sig = [0; 64];
        assert_eq!(public_key(&seed, &mut output_key), Ok(()));
        assert_eq!(output_key.as_slice(), key, "{}", vector["name"]);
        assert_eq!(sign(&seed, &message, &mut output_sig), Ok(()));
        assert_eq!(output_sig.as_slice(), sig, "{}", vector["name"]);
        assert_eq!(verify(&key, &message, &sig), Ok(true));
        let mut wrong = message.clone();
        wrong.push(0);
        assert_eq!(verify(&key, &wrong, &sig), Ok(false));
        assert!(
            public(&key)
                .unwrap()
                .verify_strict(&message, &Signature::from_slice(&sig).unwrap())
                .is_ok()
        );
    }
}
#[test]
fn all_five_rfc8032_pure_ed25519_vectors() {
    fixtures(include_str!(
        "../../../../benchmarks/crypto/round3/ed25519/fixtures/rfc8032.json"
    ));
}
#[test]
fn independent_openssl_message_boundaries() {
    fixtures(include_str!(
        "../../../../benchmarks/crypto/round3/ed25519/fixtures/openssl.json"
    ));
}
#[test]
fn strict_decoding_small_order_and_scalar_boundaries() {
    let mut key = [0; 32];
    let mut sig = [0; 64];
    public_key(&[0; 32], &mut key).unwrap();
    sign(&[0; 32], b"", &mut sig).unwrap();
    // Every 32-byte seed is legal, including zero and all-ones.
    public_key(&[255; 32], &mut [0; 32]).unwrap();
    for length in [0, 1, 31, 33, 64] {
        assert_eq!(
            public_key(&vec![0; length], &mut [0; 32]),
            Err(INVALID_SECRET_KEY)
        );
        assert_eq!(
            sign(&vec![0; length], b"", &mut [0; 64]),
            Err(INVALID_SECRET_KEY)
        );
        assert_eq!(verify(&key, b"", &vec![0; length]), Err(INVALID_SIGNATURE));
    }
    for point in curve25519_dalek::constants::EIGHT_TORSION {
        let bytes = point.compress().to_bytes();
        assert!(matches!(public(&bytes), Err(INVALID_PUBLIC_KEY)));
        let mut bad = sig;
        bad[..32].copy_from_slice(&bytes);
        assert_eq!(verify(&key, b"", &bad), Err(INVALID_SIGNATURE));
    }
    // Noncanonical y=p..p+18, with both sign bits, even if dalek reduces them.
    for y in 0xed..=0xff {
        for sign_bit in [0, 0x80] {
            let mut bytes = [255; 32];
            bytes[0] = y;
            bytes[31] = 0x7f | sign_bit;
            assert!(matches!(public(&bytes), Err(INVALID_PUBLIC_KEY)));
            let mut bad = sig;
            bad[..32].copy_from_slice(&bytes);
            assert_eq!(verify(&key, b"", &bad), Err(INVALID_SIGNATURE));
        }
    }
    let order = hex("edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010");
    let mut bad = sig;
    bad[32..].copy_from_slice(&order);
    assert_eq!(verify(&key, b"", &bad), Err(INVALID_SIGNATURE));
    // S=0 is well-formed, although this ordinary signature does not verify.
    bad[32..].fill(0);
    assert_eq!(verify(&key, b"", &bad), Ok(false));
    assert_eq!(verify(b"", b"", b""), Err(INVALID_PUBLIC_KEY));
    assert_eq!(verify(&key, b"", &sig), Ok(true));
}
#[test]
fn strict_upstream_parity_and_input_immutability() {
    for case in 0..64u8 {
        let seed = [case; 32];
        let saved_seed = seed;
        let message = vec![case.wrapping_add(13); usize::from(case) * 17];
        let saved_message = message.clone();
        let mut key = [0; 32];
        let mut sig = [0; 64];
        public_key(&seed, &mut key).unwrap();
        sign(&seed, &message, &mut sig).unwrap();
        let saved_sig = sig;
        let saved_key = key;
        for index in [0, 15, 31, 32, 47, 63] {
            let mut changed = sig;
            changed[index] ^= 1;
            let ours = verify(&key, &message, &changed).unwrap_or(false);
            let upstream = public(&key)
                .unwrap()
                .verify_strict(&message, &Signature::from_bytes(&changed))
                .is_ok();
            assert_eq!(ours, upstream);
        }
        assert_eq!(seed, saved_seed);
        assert_eq!(message, saved_message);
        assert_eq!(key, saved_key);
        assert_eq!(sig, saved_sig);
    }
}
