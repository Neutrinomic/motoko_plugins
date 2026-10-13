//! Audit the exact exported kernel entry points, including overlapping read inputs.
#[path = "../../../../plugins/ed25519/runtime/src/lib.rs"]
mod kernel;

#[cfg(test)]
mod audit {
    use super::kernel;
    use ed25519_dalek::{Signature, VerifyingKey};

    fn bytes(value: &str) -> Vec<u8> {
        (0..value.len()).step_by(2)
            .map(|i| u8::from_str_radix(&value[i..i + 2], 16).unwrap()).collect()
    }

    fn verify(key: &[u8], msg: &[u8], sig: &[u8]) -> i64 {
        unsafe { kernel::ed25519_verify(key.as_ptr(), key.len(), msg.as_ptr(), msg.len(), sig.as_ptr(), sig.len()) }
    }

    #[test]
    fn corpus_and_strict_dalek_parity() {
        let vectors: serde_json::Value = serde_json::from_str(include_str!("vectors/cases.json")).unwrap();
        let mut mixed = (0, 0);
        for vector in vectors["cases"].as_array().unwrap() {
            let key = bytes(vector["publicKey"].as_str().unwrap());
            let msg = bytes(vector["message"].as_str().unwrap());
            let sig = bytes(vector["signature"].as_str().unwrap());
            let expected = match vector["expected"].as_str().unwrap() {
                "true" => 1, "false" => 0, "invalidPublicKey" => -2, "invalidSignature" => -3,
                value => panic!("unexpected classification {value}"),
            };
            let saved = (key.clone(), msg.clone(), sig.clone());
            assert_eq!(verify(&key, &msg, &sig), expected, "{}", vector["name"]);
            assert_eq!((key.as_slice(), msg.as_slice(), sig.as_slice()),
                (saved.0.as_slice(), saved.1.as_slice(), saved.2.as_slice()));
            // The only deliberate difference from dalek strict is earlier
            // rejection of noncanonical A encodings. For admitted encodings,
            // strict and this optimized path must agree on the exact equation.
            if expected >= 0 {
                let upstream = VerifyingKey::from_bytes(key.as_slice().try_into().unwrap()).unwrap()
                    .verify_strict(&msg, &Signature::from_slice(&sig).unwrap()).is_ok();
                assert_eq!(expected == 1, upstream, "{}", vector["name"]);
            }
            if vector["category"] == "mixed-order" {
                if expected == 1 { mixed.0 += 1 } else { mixed.1 += 1 }
            }
        }
        assert_eq!(mixed, (8, 8));
    }

    #[test]
    fn readonly_inputs_can_alias_and_failures_do_not_poison_next_call() {
        let seed = [41_u8; 32];
        let saved_seed = seed;
        let mut key = [0_u8; 32];
        let mut sig = [0_u8; 64];
        unsafe {
            assert_eq!(kernel::ed25519_public_key(seed.as_ptr(), seed.len(), key.as_mut_ptr()), 0);
            // Same allocation borrowed twice read-only, a legal public API call.
            assert_eq!(kernel::ed25519_sign(seed.as_ptr(), seed.len(), seed.as_ptr(), seed.len(), sig.as_mut_ptr()), 0);
        }
        assert_eq!(verify(&key, &seed, &sig), 1);
        let mut aliased_sig = [0_u8; 64];
        unsafe {
            assert_eq!(kernel::ed25519_sign(seed.as_ptr(), 32, key.as_ptr(), 32, aliased_sig.as_mut_ptr()), 0);
        }
        assert_eq!(verify(&key, &key, &aliased_sig), 1);
        let before = (key, sig, aliased_sig);
        assert_eq!(verify(&sig[..32], &sig, &sig), 0);
        assert_eq!(verify(&[], &[], &[]), -2);
        assert_eq!(verify(&key, &[], &[]), -3);
        assert_eq!(verify(&key, &seed, &sig), 1);
        assert_eq!((key, sig, aliased_sig), before);
        assert_eq!(seed, saved_seed);
    }

    #[test]
    fn empty_message_null_pointer_and_error_output_is_not_written() {
        let seed = [17_u8; 32];
        let mut key = [0_u8; 32];
        let mut sig = [0_u8; 64];
        unsafe {
            assert_eq!(kernel::ed25519_public_key(seed.as_ptr(), 32, key.as_mut_ptr()), 0);
            assert_eq!(kernel::ed25519_sign(seed.as_ptr(), 32, std::ptr::null(), 0, sig.as_mut_ptr()), 0);
            assert_eq!(kernel::ed25519_verify(key.as_ptr(), 32, std::ptr::null(), 0, sig.as_ptr(), 64), 1);
            let mut output = [0xa5; 64];
            assert_eq!(kernel::ed25519_sign(std::ptr::null(), 0, std::ptr::null(), 0, output.as_mut_ptr()), -1);
            assert_eq!(output, [0xa5; 64]);
            assert_eq!(kernel::ed25519_public_key(std::ptr::null(), 0, output.as_mut_ptr()), -1);
            assert_eq!(output, [0xa5; 64]);
        }
    }
}
