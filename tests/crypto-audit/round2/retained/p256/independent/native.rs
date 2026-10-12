use sha2::{Digest, Sha256};

fn bytes(text: &str) -> Vec<u8> {
    (0..text.len()).step_by(2)
        .map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap()).collect()
}

#[test]
fn complete_wycheproof_corpora_through_pointer_abi() {
    for (curve, path, expected_count) in [
        (0, env!("AUDIT_SECP_VECTORS"), 476),
        (1, env!("AUDIT_P256_VECTORS"), 484),
    ] {
        let corpus: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        let mut count = 0;
        for group in corpus["testGroups"].as_array().unwrap() {
            let public = bytes(group["publicKey"]["uncompressed"].as_str().unwrap());
            for vector in group["tests"].as_array().unwrap() {
                let msg = bytes(vector["msg"].as_str().unwrap());
                let digest = Sha256::digest(msg);
                let der = bytes(vector["sig"].as_str().unwrap());
                let mut compact = [0xa5; 66];
                let decoded = unsafe {
                    if curve == 0 {
                        secp::secp256k1_call(10, der.as_ptr(), der.len(), der.as_ptr(), 0,
                            der.as_ptr(), 0, compact.as_mut_ptr().add(1))
                    } else {
                        p256_kernel::p256_signature_from_der(der.as_ptr(), der.len(), compact.as_mut_ptr().add(1))
                    }
                };
                assert_eq!(compact[0], 0xa5);
                assert_eq!(compact[65], 0xa5);
                let valid = decoded == 64 && unsafe {
                    if curve == 0 {
                        secp::secp256k1_call(8, public.as_ptr(), public.len(), digest.as_ptr(), 32,
                            compact.as_ptr().add(1), 64, compact.as_mut_ptr().add(65)) == 1
                    } else {
                        p256_kernel::p256_verify_prehash(public.as_ptr(), public.len(), digest.as_ptr(), 32,
                            compact.as_ptr().add(1), 64) == 1
                    }
                };
                assert_eq!(valid, vector["result"] == "valid", "curve {curve} tcId {} {}", vector["tcId"], vector["comment"]);
                count += 1;
            }
        }
        assert_eq!(count, expected_count);
    }
}

#[test]
fn secp_every_opcode_initializes_exact_capacity_on_invalid_inputs() {
    let capacities = [33,33,65,33,33,33,33,64,0,72,64,64,32,64,0,33,32];
    let inputs = [0u8; 257];
    for (op, capacity) in capacities.into_iter().enumerate() {
        for length in [0,1,30,31,32,33,63,64,65,66,71,72,73,255] {
            let mut out = [0xa5; 75];
            let saved = inputs;
            let status = unsafe { secp::secp256k1_call(op, inputs.as_ptr().add(1), length,
                inputs.as_ptr().add(1), length, inputs.as_ptr().add(1), length, out.as_mut_ptr().add(1)) };
            assert!(status < 0, "op {op}, length {length}, status {status}");
            assert_eq!(out[0], 0xa5);
            assert!(out[1..1+capacity].iter().all(|&x| x == 0), "op {op} leaves uninitialized output");
            assert!(out[1+capacity..].iter().all(|&x| x == 0xa5), "op {op} overrun");
            assert_eq!(inputs, saved);
        }
    }
}

#[test]
fn p256_every_export_initializes_exact_capacity_on_invalid_inputs() {
    let input = [0u8; 257];
    for length in [0,1,30,31,32,33,63,64,65,66,71,72,73,255] {
        for (op, capacity) in [(0,33),(1,65),(2,33),(3,65),(4,64),(5,72),(6,64),(7,64)] {
            let mut out = [0xa5; 75];
            let p = unsafe { input.as_ptr().add(1) };
            let o = unsafe { out.as_mut_ptr().add(1) };
            let status = unsafe { match op {
                0 | 1 => p256_kernel::p256_public_key(p,length,if op==0 {1} else {0},o),
                2 | 3 => p256_kernel::p256_convert_public_key(p,length,if op==2 {1} else {0},o),
                4 => p256_kernel::p256_sign_prehash(p,length,p,length,o),
                5 => p256_kernel::p256_signature_to_der(p,length,o),
                6 => p256_kernel::p256_signature_from_der(p,length,o),
                _ => p256_kernel::p256_normalize_signature(p,length,o),
            }};
            assert!(status < 0);
            assert_eq!(out[0],0xa5);
            assert!(out[1..1+capacity].iter().all(|&x| x==0));
            assert!(out[1+capacity..].iter().all(|&x| x==0xa5));
        }
    }
}
