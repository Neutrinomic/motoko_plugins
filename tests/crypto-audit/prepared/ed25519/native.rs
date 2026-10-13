//! Prepared entry points audited against independent vectors and direct calls.
#[path = "../../../../plugins/ed25519/runtime/src/lib.rs"]
mod kernel;

#[cfg(test)]
mod audit {
    use super::kernel;

    fn bytes(hex: &str) -> Vec<u8> {
        (0..hex.len()).step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i+2],16).unwrap()).collect()
    }
    fn less_than_le(value: &[u8], bound: &[u8]) -> bool {
        value.iter().rev().cmp(bound.iter().rev()).is_lt()
    }
    fn verify(prepared: &[u8;1056], message: &[u8], signature: &[u8]) -> i64 {
        unsafe { kernel::ed25519_verify_prepared(prepared.as_ptr(), message.as_ptr(), message.len(),
                                                signature.as_ptr(), signature.len()) }
    }
    fn sign(prepared: &[u8;96], message: &[u8]) -> [u8;64] {
        let mut output=[0xa5;66];
        unsafe { kernel::ed25519_sign_prepared(prepared.as_ptr(), message.as_ptr(), message.len(),
                                              output.as_mut_ptr().add(1)) };
        assert_eq!(output[0],0xa5); assert_eq!(output[65],0xa5);
        output[1..65].try_into().unwrap()
    }
    fn public(raw: &[u8]) -> Result<[u8;1056],i64> {
        let mut first=[0x5a;1058];let mut second=[0xa5;1058];
        let a=unsafe { kernel::ed25519_prepare_public_key(raw.as_ptr(),raw.len(),first.as_mut_ptr().add(1)) };
        let b=unsafe { kernel::ed25519_prepare_public_key(raw.as_ptr(),raw.len(),second.as_mut_ptr().add(1)) };
        assert_eq!(a,b);
        assert_eq!((first[0],first[1057]),(0x5a,0x5a));
        assert_eq!((second[0],second[1057]),(0xa5,0xa5));
        if a!=0 { return Err(a) }
        // Different prior contents produce identical complete payloads: no
        // padding/uninitialized byte or process-local pointer is serialized.
        assert_eq!(&first[1..1057],&second[1..1057]);
        assert_eq!(&first[1..33],raw);
        let modulus=bytes("edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f");
        for field in first[33..1057].chunks_exact(32) {
            assert!(less_than_le(field,&modulus),"noncanonical cached field");
        }
        Ok(first[1..1057].try_into().unwrap())
    }
    fn secret(seed: &[u8]) -> Result<[u8;96],i64> {
        let mut first=[0x5a;98];let mut second=[0xa5;98];
        let a=unsafe { kernel::ed25519_prepare_secret_key(seed.as_ptr(),seed.len(),first.as_mut_ptr().add(1)) };
        let b=unsafe { kernel::ed25519_prepare_secret_key(seed.as_ptr(),seed.len(),second.as_mut_ptr().add(1)) };
        assert_eq!(a,b);
        assert_eq!((first[0],first[97]),(0x5a,0x5a));
        assert_eq!((second[0],second[97]),(0xa5,0xa5));
        if a!=0 { return Err(a) }
        assert_eq!(&first[1..97],&second[1..97]);
        let order=bytes("edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010");
        assert!(less_than_le(&first[1..33],&order));
        Ok(first[1..97].try_into().unwrap())
    }

    #[test]
    fn all_290_independent_cases_keep_strict_prepared_semantics() {
        let corpus:serde_json::Value=serde_json::from_str(include_str!("../../round3/ed25519/vectors/cases.json")).unwrap();
        let mut counts=[0;4];
        for row in corpus["cases"].as_array().unwrap() {
            let key=bytes(row["publicKey"].as_str().unwrap());
            let message=bytes(row["message"].as_str().unwrap());
            let signature=bytes(row["signature"].as_str().unwrap());
            let expected=match row["expected"].as_str().unwrap() {
                "true"=>{counts[0]+=1;1},"false"=>{counts[1]+=1;0},
                "invalidPublicKey"=>{counts[2]+=1;-2},"invalidSignature"=>{counts[3]+=1;-3},_=>unreachable!(),
            };
            match public(&key) {
                Err(error)=>assert_eq!(error,expected,"{}",row["name"]),
                Ok(prepared)=>{
                    let saved=prepared;
                    assert_eq!(verify(&prepared,&message,&signature),expected,"{}",row["name"]);
                    let other=public(&bytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")).unwrap();
                    assert_eq!(verify(&prepared,&message,&signature),expected);
                    assert_eq!(prepared,saved);
                    assert_eq!(verify(&other,&[],&[]),-3);
                }
            }
        }
        assert_eq!(counts,[96,22,59,113]);
    }

    #[test]
    fn all_rfc_and_openssl_signatures_and_secret_codec_are_exact() {
        let mut retained=Vec::new();
        for fixture in [
            include_str!("../../../../benchmarks/crypto/round3/ed25519/fixtures/rfc8032.json"),
            include_str!("../../../../benchmarks/crypto/round3/ed25519/fixtures/openssl.json"),
        ] {
            let vectors:serde_json::Value=serde_json::from_str(fixture).unwrap();
            for row in vectors["vectors"].as_array().unwrap() {
                let seed=bytes(row["seed"].as_str().unwrap());
                let public_key=bytes(row["publicKey"].as_str().unwrap());
                let message=bytes(row["message"].as_str().unwrap());
                let signature=bytes(row["signature"].as_str().unwrap());
                let prepared=secret(&seed).unwrap();
                assert_eq!(&prepared[64..],public_key);
                assert_eq!(sign(&prepared,&message).as_slice(),signature,"{}",row["name"]);
                retained.push((prepared,public(&public_key).unwrap(),message,signature));
            }
        }
        assert_eq!(retained.len(),15);
        for (secret,public,message,signature) in retained.iter().rev() {
            assert_eq!(sign(secret,message).as_slice(),signature);
            assert_eq!(verify(public,message,signature),1);
        }
    }

    #[test]
    fn invalid_factories_and_overlapping_read_inputs_do_not_poison_handles() {
        let seed=[41u8;32];let prepared=secret(&seed).unwrap();
        let public=public(&prepared[64..]).unwrap();let saved=prepared;
        for length in [0,1,31,33,64,96,1056] {
            assert_eq!(secret(&vec![0;length]),Err(-1));
        }
        let signature=sign(&prepared,&seed);
        assert_eq!(verify(&public,&seed,&signature),1);
        // Prepared buffers themselves are immutable; overlapping readonly input
        // addresses are safe even though the Motoko API never exposes payloads.
        let alias_signature=sign(&prepared,&prepared);
        assert_eq!(verify(&public,&prepared,&alias_signature),1);
        assert_eq!(prepared,saved);
        assert_eq!(verify(&public,&[],&[]),-3);
        assert_eq!(verify(&public,&seed,&signature),1);
    }
}
