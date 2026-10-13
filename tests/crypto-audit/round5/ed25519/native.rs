//! Extra production entry-point coverage; expected bytes are independently generated.
#[path = "../../../../plugins/ed25519/runtime/src/lib.rs"]
mod kernel;

#[cfg(test)]
mod audit {
    use super::kernel::*;

    fn bytes(value: &serde_json::Value, name: &str) -> Vec<u8> {
        let hex = value[name].as_str().unwrap();
        (0..hex.len()).step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap()).collect()
    }
    fn vectors() -> serde_json::Value {
        serde_json::from_str(include_str!("vectors.json")).unwrap()
    }
    unsafe fn verify(key: &[u8], message: &[u8], signature: &[u8]) -> i64 {
        unsafe { ed25519_verify(key.as_ptr(), key.len(), message.as_ptr(), message.len(),
                               signature.as_ptr(), signature.len()) }
    }

    #[test]
    fn independent_prefix_boundaries_and_mode_separation_signing() {
        let data = vectors();
        assert_eq!(data["signing"].as_array().unwrap().len(), 26);
        for row in data["signing"].as_array().unwrap() {
            let seed = bytes(row, "seed");
            let key = bytes(row, "publicKey");
            let message = bytes(row, "message");
            let signature = bytes(row, "signature");
            let mut secret = [0; 96];
            let mut public = [0; 1056];
            let mut output = [0; 64];
            unsafe {
                assert_eq!(ed25519_prepare_secret_key(seed.as_ptr(), seed.len(), secret.as_mut_ptr()), 0);
                assert_eq!(ed25519_prepare_public_key(key.as_ptr(), key.len(), public.as_mut_ptr()), 0);
                assert_eq!(ed25519_sign(seed.as_ptr(), seed.len(), message.as_ptr(), message.len(), output.as_mut_ptr()), 0);
                assert_eq!(output.as_slice(), signature, "{}", row["name"]);
                ed25519_sign_prepared(secret.as_ptr(), message.as_ptr(), message.len(), output.as_mut_ptr());
                assert_eq!(output.as_slice(), signature, "{}", row["name"]);
                assert_eq!(verify(&key, &message, &signature), 1);
                assert_eq!(ed25519_verify_prepared(public.as_ptr(), message.as_ptr(), message.len(), signature.as_ptr(), signature.len()), 1);
            }
        }
    }

    #[test]
    fn independent_mixed_order_key_classes_key_signs_and_rfc_modes() {
        let data = vectors();
        assert_eq!(data["verification"].as_array().unwrap().len(), 72);
        for row in data["verification"].as_array().unwrap() {
            let key = bytes(row, "publicKey");
            let message = bytes(row, "message");
            let signature = bytes(row, "signature");
            let expected = i64::from(row["expected"].as_bool().unwrap());
            let mut prepared = [0; 1056];
            unsafe {
                assert_eq!(ed25519_validate_public_key(key.as_ptr(), key.len()), 1);
                assert_eq!(ed25519_prepare_public_key(key.as_ptr(), key.len(), prepared.as_mut_ptr()), 0);
                assert_eq!(verify(&key, &message, &signature), expected, "{}", row["name"]);
                assert_eq!(ed25519_verify_prepared(prepared.as_ptr(), message.as_ptr(), message.len(), signature.as_ptr(), signature.len()), expected, "{}", row["name"]);
            }
        }
    }

    #[test]
    fn all_ffi_inputs_and_outputs_allow_byte_alignment_and_preserve_guards() {
        let data = vectors();
        let row = &data["signing"][0];
        let seed = bytes(row, "seed");
        let key = bytes(row, "publicKey");
        let message = bytes(row, "message");
        let signature = bytes(row, "signature");
        for offset in 1..=7 {
            let pack = |input: &[u8]| { let mut v = vec![0xa5; offset]; v.extend(input); v.push(0x5a); v };
            let seed = pack(&seed);
            let key = pack(&key);
            let message = pack(&message);
            let signature = pack(&signature);
            let saved = (seed.clone(), key.clone(), message.clone(), signature.clone());
            let mut secret = vec![0xc3; 96 + offset + 1];
            let mut public = vec![0xc3; 1056 + offset + 1];
            let mut derived = vec![0xc3; 32 + offset + 1];
            let mut output = vec![0xc3; 64 + offset + 1];
            unsafe {
                assert_eq!(ed25519_public_key(seed.as_ptr().add(offset), 32, derived.as_mut_ptr().add(offset)), 0);
                assert_eq!(ed25519_validate_public_key(key.as_ptr().add(offset), 32), 1);
                assert_eq!(ed25519_prepare_secret_key(seed.as_ptr().add(offset), 32, secret.as_mut_ptr().add(offset)), 0);
                assert_eq!(ed25519_prepare_public_key(key.as_ptr().add(offset), 32, public.as_mut_ptr().add(offset)), 0);
                let original_secret = secret.clone();
                let original_public = public.clone();
                assert_eq!(ed25519_sign(seed.as_ptr().add(offset), 32, message.as_ptr().add(offset), message.len() - offset - 1, output.as_mut_ptr().add(offset)), 0);
                assert_eq!(&output[offset..offset + 64], &signature[offset..offset + 64]);
                ed25519_sign_prepared(secret.as_ptr().add(offset), message.as_ptr().add(offset), message.len() - offset - 1, output.as_mut_ptr().add(offset));
                assert_eq!(&output[offset..offset + 64], &signature[offset..offset + 64]);
                assert_eq!(ed25519_verify(key.as_ptr().add(offset), 32, message.as_ptr().add(offset), message.len() - offset - 1, signature.as_ptr().add(offset), 64), 1);
                assert_eq!(ed25519_verify_prepared(public.as_ptr().add(offset), message.as_ptr().add(offset), message.len() - offset - 1, signature.as_ptr().add(offset), 64), 1);
                // Prepared inputs may also be borrowed as overlapping read-only
                // messages. Null is permitted only for zero-length messages.
                ed25519_sign_prepared(secret.as_ptr().add(offset), secret.as_ptr().add(offset), 96, output.as_mut_ptr().add(offset));
                assert_eq!(ed25519_verify_prepared(public.as_ptr().add(offset), secret.as_ptr().add(offset), 96, output.as_ptr().add(offset), 64), 1);
                ed25519_sign_prepared(secret.as_ptr().add(offset), core::ptr::null(), 0, output.as_mut_ptr().add(offset));
                assert_eq!(ed25519_verify_prepared(public.as_ptr().add(offset), core::ptr::null(), 0, output.as_ptr().add(offset), 64), 1);
                assert_eq!(secret, original_secret);
                assert_eq!(public, original_public);
            }
            assert_eq!(&derived[offset..offset + 32], &key[offset..offset + 32]);
            for value in [&secret, &public, &derived, &output] {
                assert!(value[..offset].iter().all(|byte| *byte == 0xc3));
                assert_eq!(value.last(), Some(&0xc3));
            }
            assert_eq!((seed, key, message, signature), saved);
        }
    }

    #[test]
    fn malformed_factory_outputs_remain_completely_untouched() {
        let data = vectors();
        let valid_key = bytes(&data["signing"][0], "publicKey");
        let mut prepared = [0; 1056];
        unsafe { assert_eq!(ed25519_prepare_public_key(valid_key.as_ptr(), 32, prepared.as_mut_ptr()), 0) };
        for length in 0..=160 {
            let input = vec![0; length];
            if length != 32 {
                let mut key = [0xa5; 34];
                let mut signature = [0xa5; 66];
                let mut secret = [0xa5; 98];
                unsafe {
                    assert_eq!(ed25519_public_key(input.as_ptr(), length, key.as_mut_ptr().add(1)), -1);
                    assert_eq!(ed25519_sign(input.as_ptr(), length, core::ptr::null(), 0, signature.as_mut_ptr().add(1)), -1);
                    assert_eq!(ed25519_prepare_secret_key(input.as_ptr(), length, secret.as_mut_ptr().add(1)), -1);
                }
                assert_eq!(key, [0xa5; 34]);
                assert_eq!(signature, [0xa5; 66]);
                assert_eq!(secret, [0xa5; 98]);
            }
            // Zero-filled length 32 is also an invalid (small-order) public key.
            let mut output = [0xa5; 1058];
            unsafe {
                assert_eq!(ed25519_validate_public_key(input.as_ptr(), length), -2);
                assert_eq!(ed25519_prepare_public_key(input.as_ptr(), length, output.as_mut_ptr().add(1)), -2);
                assert_eq!(verify(&input, &[], &[]), -2);
                assert_eq!(ed25519_verify_prepared(prepared.as_ptr(), core::ptr::null(), 0, input.as_ptr(), length), -3);
            }
            assert_eq!(output, [0xa5; 1058]);
        }
        // Reuse the old independently classified encoding corpus, without
        // duplicating its vectors, to cover factory errors beyond length checks.
        let prior: serde_json::Value = serde_json::from_str(include_str!("../../round3/ed25519/vectors/cases.json")).unwrap();
        for row in prior["cases"].as_array().unwrap().iter().filter(|r| r["expected"] == "invalidPublicKey") {
            let key = bytes(row, "publicKey");
            let mut output = [0x5a; 1058];
            unsafe { assert_eq!(ed25519_prepare_public_key(key.as_ptr(), key.len(), output.as_mut_ptr().add(1)), -2) };
            assert_eq!(output, [0x5a; 1058], "{}", row["name"]);
        }
    }
}
