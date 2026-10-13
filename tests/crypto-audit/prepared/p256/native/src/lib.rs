#[cfg(test)]
#[path = "../../../../../../plugins/p256/runtime/src/lib.rs"]
mod candidate;

#[cfg(test)]
mod audit {
    use super::candidate;

    fn hex(value: &str) -> Vec<u8> {
        assert_eq!(value.len() % 2, 0);
        value.as_bytes().chunks_exact(2).map(|v| {
            u8::from_str_radix(core::str::from_utf8(v).unwrap(), 16).unwrap()
        }).collect()
    }

    fn corpus() -> serde_json::Value {
        serde_json::from_str(include_str!("../../vectors.json")).unwrap()
    }

    fn prepare(key: &[u8], expected: &[u8]) -> Vec<u8> {
        // Offset by one byte intentionally: codecs must not assume u64 alignment.
        let mut buffer = vec![0xa5; expected.len() + 2];
        let copy = key.to_vec();
        let status = unsafe {
            candidate::p256_prepare_public_key(key.as_ptr(), key.len(), buffer.as_mut_ptr().add(1))
        };
        assert_eq!(status, expected.len() as i64);
        assert_eq!(buffer[0], 0xa5);
        assert_eq!(buffer[buffer.len() - 1], 0xa5);
        assert_eq!(&buffer[1..buffer.len() - 1], expected);
        assert_eq!(key, copy);
        buffer
    }

    #[test]
    fn exact_prepared_bytes_match_independent_integer_arithmetic() {
        let corpus = corpus();
        let size = corpus["payload_bytes"].as_u64().unwrap() as usize;
        for key in corpus["keys"].as_array().unwrap() {
            let expected = hex(key["prepared"].as_str().unwrap());
            assert_eq!(expected.len(), size);
            let compressed = hex(key["compressed"].as_str().unwrap());
            let uncompressed = hex(key["uncompressed"].as_str().unwrap());
            assert_eq!(prepare(&compressed, &expected), prepare(&uncompressed, &expected));
        }
    }

    #[test]
    fn direct_and_prepared_equations_match_independent_oracle() {
        let corpus = corpus();
        let keys = corpus["keys"].as_array().unwrap();
        let prepared: Vec<_> = keys.iter().map(|key| {
            prepare(&hex(key["compressed"].as_str().unwrap()), &hex(key["prepared"].as_str().unwrap()))
        }).collect();
        for case in corpus["verify"].as_array().unwrap() {
            let index = case["key"].as_u64().unwrap() as usize;
            let public = hex(keys[index]["compressed"].as_str().unwrap());
            let digest = hex(case["digest"].as_str().unwrap());
            let signature = hex(case["signature"].as_str().unwrap());
            let expected = i64::from(case["expected"].as_bool().unwrap());
            let before = prepared[index].clone();
            unsafe {
                assert_eq!(candidate::p256_verify_prehash_prepared(
                    prepared[index].as_ptr().add(1), digest.as_ptr(), digest.len(),
                    signature.as_ptr(), signature.len()), expected, "{}", case["label"]);
                assert_eq!(candidate::p256_verify_prehash(
                    public.as_ptr(), public.len(), digest.as_ptr(), digest.len(),
                    signature.as_ptr(), signature.len()), expected, "{}", case["label"]);
            }
            assert_eq!(prepared[index], before);
        }
    }

    #[test]
    fn preparation_rejects_malformed_keys_and_initializes_full_output() {
        let corpus = corpus();
        let size = corpus["payload_bytes"].as_u64().unwrap() as usize;
        for key in corpus["invalid_keys"].as_array().unwrap() {
            let key = hex(key.as_str().unwrap());
            let mut buffer = vec![0xa5; size + 2];
            let ptr = if key.is_empty() { core::ptr::null() } else { key.as_ptr() };
            assert_eq!(unsafe {
                candidate::p256_prepare_public_key(ptr, key.len(), buffer.as_mut_ptr().add(1))
            }, -2);
            assert_eq!(buffer[0], 0xa5);
            assert_eq!(buffer[size + 1], 0xa5);
            assert!(buffer[1..size + 1].iter().all(|b| *b == 0));
        }
    }

    #[test]
    fn prepared_validation_order_lengths_and_scalar_bounds() {
        let corpus = corpus();
        let key = &corpus["keys"][0];
        let prepared = prepare(&hex(key["compressed"].as_str().unwrap()), &hex(key["prepared"].as_str().unwrap()));
        let valid_signature = hex(corpus["verify"][0]["signature"].as_str().unwrap());
        let digest = [0u8; 32];
        let order = hex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
        let mut invalid = vec![vec![], vec![0u8; 63], vec![0u8; 65], vec![0u8; 64]];
        for component in 0..2 {
            for value in [[0u8; 32].to_vec(), order.clone(), vec![0xff; 32]] {
                let mut sig = valid_signature.clone();
                sig[component * 32..(component + 1) * 32].copy_from_slice(&value);
                invalid.push(sig);
            }
        }
        for sig in &invalid {
            let ptr = if sig.is_empty() { core::ptr::null() } else { sig.as_ptr() };
            unsafe {
                assert_eq!(candidate::p256_verify_prehash_prepared(
                    prepared.as_ptr().add(1), digest.as_ptr(), digest.len(), ptr, sig.len()), -4);
                assert_eq!(candidate::p256_verify_prehash_prepared(
                    prepared.as_ptr().add(1), core::ptr::null(), 0, ptr, sig.len()), -3);
            }
        }
        for length in [0, 1, 31, 33, 64] {
            let hash = vec![0u8; length];
            assert_eq!(unsafe { candidate::p256_verify_prehash_prepared(
                prepared.as_ptr().add(1), hash.as_ptr(), length,
                valid_signature.as_ptr(), valid_signature.len()) }, -3);
        }
    }
}
