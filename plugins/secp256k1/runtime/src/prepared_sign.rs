//! Factory-owned Schnorr signing cache: normalized scalar || public X.
//!
//! The wrapper must keep this representation opaque and accept only caches made
//! by `prepare`; `sign` does not rederive or authenticate the cached public key.
//! Its 64-byte value contains the secret scalar. Motoko-managed copies remain
//! until GC and have no erasure guarantee; zeroizing local Rust temporaries does
//! not erase managed values, previous copies, or guarantee removal from registers.

use k256::{schnorr::SigningKey, FieldBytes, NonZeroScalar};
use k256::elliptic_curve::zeroize::Zeroizing;

use super::{Result, AUXILIARY, SECRET, SIGNATURE};

pub(super) fn prepare(secret: &[u8], out: &mut [u8]) -> Result<i64> {
    if secret.len() != 32 || out.len() < 64 {
        return Err(SECRET);
    }
    let key = SigningKey::from_bytes(secret).map_err(|_| SECRET)?;
    let normalized = Zeroizing::new(key.to_bytes());
    out[..32].copy_from_slice(&normalized);
    out[32..64].copy_from_slice(&key.verifying_key().to_bytes());
    Ok(64)
}

pub(super) fn sign(prepared: &[u8], msg: &[u8], aux: &[u8], out: &mut [u8]) -> Result<i64> {
    if prepared.len() != 64 {
        return Err(SECRET);
    }
    let secret = Zeroizing::new(NonZeroScalar::try_from(&prepared[..32]).map_err(|_| SECRET)?);
    let aux: &[u8; 32] = aux.try_into().map_err(|_| AUXILIARY)?;
    if out.len() < 64 {
        return Err(SIGNATURE);
    }
    let public_x: FieldBytes = <[u8; 32]>::try_from(&prepared[32..]).map_err(|_| SECRET)?.into();
    let signature = SigningKey::sign_raw_prepared(&secret, &public_x, msg, aux)
        .map_err(|_| SIGNATURE)?;
    out[..64].copy_from_slice(&signature.to_bytes());
    Ok(64)
}

#[cfg(test)]
mod tests {
    use super::*;
    use k256::{Scalar, SecretKey};
    use k256::elliptic_curve::point::AffineCoordinates;
    use k256::schnorr::signature::hazmat::PrehashVerifier;
    use k256::sha2::{Digest, Sha256};

    fn hex(text: &str) -> Vec<u8> {
        text.as_bytes().chunks_exact(2).map(|pair| {
            u8::from_str_radix(core::str::from_utf8(pair).unwrap(), 16).unwrap()
        }).collect()
    }

    fn cache(secret: &[u8]) -> [u8; 64] {
        let mut out = [0; 64];
        assert_eq!(prepare(secret, &mut out), Ok(64));
        out
    }

    #[test]
    fn prepared_matches_all_official_bip340_signing_vectors() {
        let mut count = 0;
        for row in include_str!("../../tests/vectors/bip340.csv").lines().skip(1) {
            let fields: Vec<_> = row.split(',').collect();
            if fields[1].is_empty() { continue; }
            let secret = hex(fields[1]);
            let public = hex(fields[2]);
            let aux = hex(fields[3]);
            let message = hex(fields[4]);
            let expected = hex(fields[5]);
            let prepared = cache(&secret);
            assert_eq!(&prepared[32..], public, "public key vector {}", fields[0]);
            let mut signature = [0; 64];
            assert_eq!(sign(&prepared, &message, &aux, &mut signature), Ok(64));
            assert_eq!(signature.as_slice(), expected, "signature vector {}", fields[0]);
            count += 1;
        }
        assert_eq!(count, 8);
    }

    #[test]
    fn normalization_caches_the_same_key_for_opposite_scalars() {
        let mut parities = [0; 2];
        for value in 1..=16u64 {
            let scalar = Scalar::from(value);
            for scalar in [scalar, -scalar] {
                let bytes = scalar.to_bytes();
                let raw = SecretKey::from_slice(&bytes).unwrap();
                let odd = bool::from(raw.public_key().as_affine().y_is_odd());
                parities[usize::from(odd)] += 1;
                let prepared = cache(&bytes);
                assert_eq!(prepared, cache(&(-scalar).to_bytes()));
                assert_eq!(prepared, cache(&prepared[..32]));
                let normalized = SecretKey::from_slice(&prepared[..32]).unwrap();
                assert!(!bool::from(normalized.public_key().as_affine().y_is_odd()));
            }
        }
        assert_eq!(parities, [16, 16]);
    }

    #[test]
    fn deterministic_random_cross_signing_reuses_the_cache() {
        for case in 0..32u64 {
            let secret = Sha256::new().chain_update(b"prepared-schnorr-key")
                .chain_update(case.to_be_bytes()).finalize();
            let key = SigningKey::from_bytes(&secret).unwrap();
            let prepared = cache(&secret);
            let original = prepared;
            for length in [0, 1, 17, 32, 65, 129] {
                let message = vec![case as u8; length];
                let aux: [u8; 32] = Sha256::new().chain_update(b"prepared-schnorr-aux")
                    .chain_update(case.to_be_bytes()).chain_update((length as u64).to_be_bytes())
                    .finalize().into();
                let expected = key.sign_raw(&message, &aux).unwrap();
                let mut output = [0xa5; 66];
                assert_eq!(sign(&prepared, &message, &aux, &mut output[1..65]), Ok(64));
                assert_eq!(&output[1..65], expected.to_bytes());
                assert_eq!((output[0], output[65]), (0xa5, 0xa5));
                assert_eq!(prepared, original);
                key.verifying_key().verify_prehash(&message, &expected).unwrap();
            }
        }
    }

    #[test]
    fn rejects_invalid_secrets_cache_lengths_and_aux_without_writing_output() {
        let mut out = [0xa5; 66];
        let mut secret = [0; 32];
        secret[31] = 1;
        for length in [0, 1, 31, 33, 64] {
            assert_eq!(prepare(&vec![1; length], &mut out), Err(SECRET));
        }
        let order = hex("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141");
        for invalid in [&[0; 32][..], &order, &[0xff; 32][..]] {
            assert_eq!(prepare(invalid, &mut out), Err(SECRET));
        }
        assert_eq!(prepare(&secret, &mut out[..63]), Err(SECRET));
        let prepared = cache(&secret);
        for length in [0, 1, 32, 63, 65] {
            assert_eq!(sign(&vec![1; length], b"message", &[0; 32], &mut out), Err(SECRET));
        }
        for invalid in [&[0; 32][..], &order, &[0xff; 32][..]] {
            let mut malformed = prepared;
            malformed[..32].copy_from_slice(invalid);
            assert_eq!(sign(&malformed, b"message", &[0; 32], &mut out), Err(SECRET));
        }
        for length in [0, 31, 33] {
            assert_eq!(sign(&prepared, b"message", &vec![0; length], &mut out), Err(AUXILIARY));
        }
        assert_eq!(sign(&prepared, b"message", &[0; 32], &mut out[..63]), Err(SIGNATURE));
        assert_eq!(out, [0xa5; 66]);
    }
}
