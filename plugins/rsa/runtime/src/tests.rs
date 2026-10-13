use super::*;
fn hex(text: &str) -> Vec<u8> {
    text.as_bytes().chunks_exact(2).map(|v| {
        u8::from_str_radix(core::str::from_utf8(v).unwrap(), 16).unwrap()
    }).collect()
}
fn fixture() -> serde_json::Value {
    serde_json::from_str(include_str!("../../vectors/openssl3072.json")).unwrap()
}
#[test]
fn openssl_fixed_salt_signature_and_key_validation() {
    let f = fixture();
    let secret = hex(f["privateKey"].as_str().unwrap());
    let public = hex(f["publicKey"].as_str().unwrap());
    let message = hex(f["message"].as_str().unwrap());
    let digest = hex(f["digest"].as_str().unwrap());
    let salt = hex(f["salt"].as_str().unwrap());
    let signature = hex(f["signature"].as_str().unwrap());
    let mut out = [0u8; 384];
    unsafe {
        assert_eq!(rsa_public_key(secret.as_ptr(), secret.len(), out.as_mut_ptr()), 384);
        assert_eq!(&out[..], public);
        assert_eq!(rsa_validate_private_key(secret.as_ptr(), secret.len()), 1);
        assert_eq!(rsa_validate_public_key(public.as_ptr(), public.len()), 1);
        assert_eq!(rsa_sign(secret.as_ptr(), secret.len(), message.as_ptr(), message.len(), salt.as_ptr(), salt.len(), out.as_mut_ptr()), 384);
        assert_eq!(&out[..], signature);
        assert_eq!(rsa_sign_prehash(secret.as_ptr(), secret.len(), digest.as_ptr(), digest.len(), salt.as_ptr(), salt.len(), out.as_mut_ptr()), 384);
        assert_eq!(&out[..], signature);
        assert_eq!(rsa_verify(public.as_ptr(), public.len(), message.as_ptr(), message.len(), signature.as_ptr(), signature.len()), 1);
        assert_eq!(rsa_verify_prehash(public.as_ptr(), public.len(), digest.as_ptr(), digest.len(), signature.as_ptr(), signature.len()), 1);
        assert_eq!(rsa_verify(public.as_ptr(), public.len(), b"wrong".as_ptr(), 5, signature.as_ptr(), signature.len()), 0);
        assert_eq!(rsa_verify(public.as_ptr(), public.len(), message.as_ptr(), message.len(), public.as_ptr(), public.len()), -5);
        assert_eq!(rsa_sign_prehash(secret.as_ptr(), secret.len(), digest.as_ptr(), 31, salt.as_ptr(), 31, out.as_mut_ptr()), -3);
        assert_eq!(rsa_sign_prehash(secret.as_ptr(), secret.len(), digest.as_ptr(), 32, salt.as_ptr(), 31, out.as_mut_ptr()), -4);
        assert_eq!(rsa_sign_prehash(secret.as_ptr(), 959, digest.as_ptr(), 31, salt.as_ptr(), 31, out.as_mut_ptr()), -1);
        assert_eq!(rsa_verify_prehash(public.as_ptr(), 383, digest.as_ptr(), 31, signature.as_ptr(), 383), -2);
        assert_eq!(rsa_verify_prehash(public.as_ptr(), 384, digest.as_ptr(), 31, signature.as_ptr(), 383), -3);
    }
}
#[test]
fn malformed_components_and_persisted_input_immutability() {
    let f = fixture();
    let key = hex(f["privateKey"].as_str().unwrap());
    let public = hex(f["publicKey"].as_str().unwrap());
    for component in 0..5 {
        let mut malformed = key.clone();
        malformed[component*192+191] ^= 1;
        let before = malformed.clone();
        assert_eq!(unsafe { rsa_validate_private_key(malformed.as_ptr(), malformed.len()) }, -1);
        assert_eq!(malformed, before);
    }
    for component in 2..5 {
        let mut malformed = key.clone();
        malformed[component*192..(component+1)*192].fill(0);
        assert_eq!(unsafe { rsa_validate_private_key(malformed.as_ptr(), malformed.len()) }, -1);
    }
    let mut same = key.clone(); same[192..384].copy_from_slice(&key[..192]);
    assert_eq!(unsafe { rsa_validate_private_key(same.as_ptr(), same.len()) }, -1);
    for index in [0, 383] {
        let mut malformed = public.clone();
        if index == 0 { malformed[index] &= 127; } else { malformed[index] &= 254; }
        assert_eq!(unsafe { rsa_validate_public_key(malformed.as_ptr(), malformed.len()) }, -2);
    }
}
