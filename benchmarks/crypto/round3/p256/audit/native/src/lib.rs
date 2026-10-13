#[cfg(test)]
#[path = "../../../../../../../plugins/p256/runtime/src/lib.rs"]
mod candidate;

#[cfg(test)]
mod audit {
    use super::candidate;

    fn hex(value: &str) -> Vec<u8> {
        value.as_bytes().chunks_exact(2).map(|v| {
            u8::from_str_radix(core::str::from_utf8(v).unwrap(), 16).unwrap()
        }).collect()
    }

    #[test]
    fn independent_openssl_points_and_python_rfc6979() {
        let corpus: serde_json::Value = serde_json::from_str(include_str!("../../independent-vectors.json")).unwrap();
        let vectors = corpus["vectors"].as_array().unwrap();
        assert_eq!(vectors.len(), 43);
        for v in vectors {
            let secret = hex(v["secret"].as_str().unwrap());
            let digest = hex(v["digest"].as_str().unwrap());
            let expected = hex(v["signature"].as_str().unwrap());
            let public = hex(v["public"].as_str().unwrap());
            let mut signature = [0xa5; 66];
            let mut key = [0x5a; 67];
            unsafe {
                assert_eq!(candidate::p256_sign_prehash(secret.as_ptr(), 32, digest.as_ptr(), 32,
                    signature.as_mut_ptr().add(1)), 64, "{}", v["label"]);
                assert_eq!(candidate::p256_public_key(secret.as_ptr(), 32, 1, key.as_mut_ptr().add(1)), 33);
                assert_eq!(candidate::p256_verify_prehash(public.as_ptr(), public.len(), digest.as_ptr(), 32,
                    signature.as_ptr().add(1), 64), 1);
            }
            assert_eq!(&signature[1..65], expected, "{}", v["label"]);
            assert_eq!(&key[1..34], public, "{}", v["label"]);
            assert_eq!((signature[0], signature[65], key[0], key[66]), (0xa5, 0xa5, 0x5a, 0x5a));
        }
    }
}
