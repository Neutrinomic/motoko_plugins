//! Stateless, allocation-free secp256k1 operations using RustCrypto k256.
//! Inputs are borrowed Motoko Blobs; caller owns an operation-sized output.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

use k256::{ProjectivePoint, PublicKey, Scalar, SecretKey};
use k256::ecdsa::{Signature, hazmat::SignPrimitive};
use k256::elliptic_curve::{PrimeField, group::Group, sec1::ToEncodedPoint, bigint::U256, ops::{Reduce, Invert}};
use k256::sha2::{Digest, Sha256};
use k256::elliptic_curve::zeroize::Zeroize;
use k256::elliptic_curve::{point::AffineCoordinates, subtle::ConditionallySelectable};

const SECRET: i64 = -1;
const PUBLIC: i64 = -2;
const SCALAR: i64 = -3;
const DIGEST: i64 = -4;
const SIGNATURE: i64 = -5;
const AUXILIARY: i64 = -6;
const INFINITY: i64 = -7;

type Result<T> = core::result::Result<T, i64>;

fn scalar(bytes: &[u8]) -> Result<Scalar> {
    let bytes: [u8; 32] = bytes.try_into().map_err(|_| SCALAR)?;
    Option::<Scalar>::from(Scalar::from_repr(bytes.into())).ok_or(SCALAR)
}
fn public(bytes: &[u8]) -> Result<PublicKey> {
    // Reject identity, hybrid encodings, and all non-SEC1 lengths explicitly.
    if !matches!((bytes.len(), bytes.first()), (33, Some(2 | 3)) | (65, Some(4))) {
        return Err(PUBLIC);
    }
    PublicKey::from_sec1_bytes(bytes).map_err(|_| PUBLIC)
}
fn signature(bytes: &[u8]) -> Result<Signature> {
    Signature::from_slice(bytes).map_err(|_| SIGNATURE)
}
fn write(bytes: &[u8], output: &mut [u8; 72]) -> i64 {
    output[..bytes.len()].copy_from_slice(bytes);
    bytes.len() as i64
}
fn encoded(point: ProjectivePoint, compressed: bool, output: &mut [u8; 72]) -> Result<i64> {
    if bool::from(point.is_identity()) { return Err(INFINITY); }
    Ok(write(point.to_affine().to_encoded_point(compressed).as_bytes(), output))
}

// Successful blob operations return their byte length; successful predicates
// return 0 or 1. Negative results are stable typed input/identity errors.
fn operation(op: usize, a: &[u8], b: &[u8], c: &[u8], out: &mut [u8; 72]) -> Result<i64> {
    match op {
        0 => {
            let key = SecretKey::from_slice(a).map_err(|_| SECRET)?;
            // SecretKey::from_slice accepts short inputs. Public API requires 32 bytes.
            if a.len() != 32 { return Err(SECRET); }
            Ok(write(key.public_key().to_encoded_point(true).as_bytes(), out))
        }
        1 | 2 => {
            let key = public(a)?;
            if (op == 1 && a.len() == 33) || (op == 2 && a.len() == 65) {
                // SEC1 parsing above validates the canonical source encoding.
                Ok(write(a, out))
            } else {
                Ok(write(key.to_encoded_point(op == 1).as_bytes(), out))
            }
        },
        3 => encoded(public(a)?.to_projective() + public(b)?.to_projective(), true, out),
        4 => encoded(public(a)?.to_projective() * scalar(b)?, true, out),
        5 => encoded(ProjectivePoint::GENERATOR * scalar(a)?, true, out),
        6 => encoded(public(a)?.to_projective() + ProjectivePoint::GENERATOR * scalar(b)?, true, out),
        7 => {
            if a.len() != 32 { return Err(SECRET); }
            let key = SecretKey::from_slice(a).map_err(|_| SECRET)?;
            if b.len() != 32 { return Err(DIGEST); }
            // RFC6979 bits2octets reduces the 256-bit hash modulo n before
            // seeding HMAC. ecdsa 0.16's sign_prehash forwards its input without
            // that reduction; reduce explicitly (also equivalent for ECDSA z).
            let digest: [u8; 32] = b.try_into().map_err(|_| DIGEST)?;
            let reduced = <Scalar as Reduce<U256>>::reduce_bytes(&digest.into()).to_bytes();
            // Use the same upstream signer without SigningKey's cached verifying
            // key: constructing that cache performs an unnecessary multiplication.
            let mut secret_scalar = key.to_nonzero_scalar();
            let result = secret_scalar.as_ref()
                .try_sign_prehashed_rfc6979::<Sha256>(&reduced, &[]);
            secret_scalar.zeroize();
            let (sig, _) = result.map_err(|_| SIGNATURE)?;
            Ok(write(&sig.to_bytes(), out))
        }
        8 => {
            let key = public(a)?;
            let digest: [u8; 32] = b.try_into().map_err(|_| DIGEST)?;
            let sig = signature(c)?;
            // Same upstream verification equation and high-S acceptance; all
            // inputs to the variable-time multiplication are public here.
            let z = <Scalar as Reduce<U256>>::reduce_bytes(&digest.into());
            let (r, s) = sig.split_scalars();
            let inverse = *s.invert_vartime();
            let point = ProjectivePoint::lincomb_vartime(
                &ProjectivePoint::GENERATOR, &(z * inverse),
                &key.to_projective(), &(*r * inverse));
            Ok(i64::from(*r == <Scalar as Reduce<U256>>::reduce_bytes(&point.to_affine().x())))
        }
        9 => Ok(write(signature(a)?.to_der().as_bytes(), out)),
        10 => Ok(write(&Signature::from_der(a).map_err(|_| SIGNATURE)?.to_bytes(), out)),
        11 => {
            let sig = signature(a)?;
            Ok(write(&sig.normalize_s().unwrap_or(sig).to_bytes(), out))
        }
        12 => {
            let _validated = public(a)?;
            // Both supported canonical SEC1 encodings start with the X bytes.
            Ok(write(&a[1..33], out))
        },
        13 => {
            if a.len() != 32 { return Err(SECRET); }
            let key = k256::schnorr::SigningKey::from_bytes(a).map_err(|_| SECRET)?;
            let aux: &[u8; 32] = c.try_into().map_err(|_| AUXILIARY)?;
            let sig = key.sign_raw(b, aux).map_err(|_| SIGNATURE)?;
            Ok(write(&sig.to_bytes(), out))
        }
        14 => {
            // k256 0.13's from_bytes panics on a wrong-sized x coordinate.
            if a.len() != 32 { return Err(PUBLIC); }
            let key = k256::schnorr::VerifyingKey::from_bytes(a).map_err(|_| PUBLIC)?;
            // BIP340 permits zero r/s in the input range checks. k256 0.13's
            // Signature type excludes those values; use its audited point and
            // scalar operations directly for the specified verification equation.
            if c.len() != 64 { return Err(SIGNATURE); }
            const FIELD: [u8; 32] = [
                0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,
                0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,
                0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,
                0xff,0xff,0xff,0xfe,0xff,0xff,0xfc,0x2f,
            ];
            if c[..32] >= FIELD[..] { return Err(SIGNATURE); }
            let s = scalar(&c[32..]).map_err(|_| SIGNATURE)?;
            // SHA256("BIP0340/challenge"), independent of key/signature/message.
            const TAG: [u8; 32] = [0x7b, 0xb5, 0x2d, 0x7a, 0x9f, 0xef, 0x58, 0x32, 0x3e, 0xb1, 0xbf, 0x7a, 0x40, 0x7d, 0xb3, 0x82, 0xd2, 0xf3, 0xf2, 0xd8, 0x1b, 0xb1, 0x22, 0x4f, 0x49, 0xfe, 0x51, 0x8f, 0x6d, 0x48, 0xd3, 0x7c];
            let tag = TAG;
            let challenge = Sha256::new().chain_update(tag).chain_update(tag)
                .chain_update(&c[..32]).chain_update(a).chain_update(b).finalize();
            let e = <Scalar as Reduce<U256>>::reduce_bytes(&challenge);
            let r = ProjectivePoint::lincomb_vartime(&ProjectivePoint::GENERATOR, &s,
                &ProjectivePoint::from(*key.as_affine()), &-e);
            if bool::from(r.is_identity()) { return Ok(0); }
            let point = r.to_affine();
            Ok(i64::from(!bool::from(point.y_is_odd()) && point.x()[..] == c[..32]))
        }
        15 => {
            if a.len() != 32 { return Err(PUBLIC); }
            let key = k256::schnorr::VerifyingKey::from_bytes(a).map_err(|_| PUBLIC)?;
            encoded(ProjectivePoint::from(*key.as_affine()) + ProjectivePoint::GENERATOR * scalar(b)?, true, out)
        }
        16 => {
            if a.len() != 32 { return Err(SECRET); }
            // BIP341 parity normalization needs one multiplication, not a
            // Schnorr signing key (which also caches a recomputed public key).
            let key = SecretKey::from_slice(a).map_err(|_| SECRET)?;
            let tweak = scalar(b)?;
            let mut secret = key.to_nonzero_scalar();
            let odd = PublicKey::from_secret_scalar(&secret).as_affine().y_is_odd();
            let mut negated = -secret;
            secret.conditional_assign(&negated, odd);
            negated.zeroize();
            let mut tweaked = *secret.as_ref() + tweak;
            secret.zeroize();
            let result = if bool::from(tweaked.is_zero()) { Err(INFINITY) }
                else {
                    let mut encoded = tweaked.to_bytes();
                    let len = write(&encoded, out);
                    encoded.zeroize();
                    Ok(len)
                };
            tweaked.zeroize();
            result
        }
        _ => Err(SIGNATURE),
    }
}

fn output_capacity(op: usize) -> usize {
    match op { 0 | 1 | 3 | 4 | 5 | 6 | 15 => 33, 2 => 65,
        7 | 10 | 11 | 13 => 64, 9 => 72, 12 | 16 => 32, _ => 0 }
}

/// # Safety
/// Each input points to its length of readable memory; output points to fresh
/// writable bytes of capacity output_capacity(op) and does not alias inputs.
/// No GC may run here.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn secp256k1_call(
    op: usize, a: *const u8, alen: usize, b: *const u8, blen: usize,
    c: *const u8, clen: usize, output: *mut u8,
) -> i64 {
    let a = unsafe { core::slice::from_raw_parts(a, alen) };
    let b = unsafe { core::slice::from_raw_parts(b, blen) };
    let c = unsafe { core::slice::from_raw_parts(c, clen) };
    // Use initialized stack scratch, never make a Rust reference to the
    // uninitialized managed Blob. Initialize the entire output on every path.
    let mut bytes = [0u8; 72];
    let result = operation(op, a, b, c, &mut bytes).unwrap_or_else(|error| error);
    unsafe { core::ptr::copy_nonoverlapping(bytes.as_ptr(), output, output_capacity(op)) };
    if op == 16 { bytes.zeroize(); }
    result
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! { core::arch::wasm64::unreachable() }

#[cfg(test)]
mod tests {
    use super::*;
    fn hex(s: &str) -> Vec<u8> {
        s.as_bytes().chunks_exact(2).map(|pair| u8::from_str_radix(core::str::from_utf8(pair).unwrap(), 16).unwrap()).collect()
    }
    fn run(op: usize, a: &[u8], b: &[u8], c: &[u8]) -> Result<Vec<u8>> {
        let mut out = [0; 72];
        let len = operation(op, a, b, c, &mut out)?;
        Ok(out[..len as usize].to_vec())
    }
    #[test]
    fn sec2_points_and_boundaries() {
        let one = hex("0000000000000000000000000000000000000000000000000000000000000001");
        let generator = hex("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798");
        assert_eq!(run(0, &one, &[], &[]).unwrap(), generator);
        assert_eq!(run(5, &one, &[], &[]).unwrap(), generator);
        assert_eq!(run(0, &one[1..], &[], &[]), Err(SECRET));
        assert_eq!(run(0, &[0; 32], &[], &[]), Err(SECRET));
        assert_eq!(run(5, &[0; 32], &[], &[]), Err(INFINITY));
        assert_eq!(run(5, &hex("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"), &[], &[]), Err(SCALAR));
        assert_eq!(run(1, &[0], &[], &[]), Err(PUBLIC));
        let twice = run(3, &generator, &generator, &[]).unwrap();
        assert_eq!(twice, hex("02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"));
        assert_eq!(run(6, &generator, &one, &[]).unwrap(), twice);
        assert_eq!(run(4, &generator, &[0; 32], &[]), Err(INFINITY));
    }
    #[test]
    fn all_official_bip340_vectors() {
        let mut verified = 0;
        let mut signed = 0;
        for line in include_str!("../../tests/vectors/bip340.csv").lines().skip(1) {
            let fields: Vec<&str> = line.split(',').collect();
            if fields.len() < 7 { continue; }
            let index = fields[0];
            let secret = hex(fields[1]);
            let key = hex(fields[2]);
            let aux = hex(fields[3]);
            let message = hex(fields[4]);
            let signature = hex(fields[5]);
            let expected = fields[6] == "TRUE";
            let actual = operation(14, &key, &message, &signature, &mut [0; 72]);
            assert_eq!(actual == Ok(1), expected, "BIP340 verify {index}: {actual:?}");
            verified += 1;
            if !secret.is_empty() {
                assert_eq!(run(13, &secret, &message, &aux).unwrap(), signature, "BIP340 sign {index}");
                signed += 1;
            }
        }
        assert_eq!(verified, 19);
        assert_eq!(signed, 8);
    }
    #[test]
    fn bip340_vector_zero() {
        let secret = hex("0000000000000000000000000000000000000000000000000000000000000003");
        let key = hex("f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9");
        let expected = hex("e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca821525f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0");
        assert_eq!(run(13, &secret, &[0; 32], &[0; 32]).unwrap(), expected);
        assert_eq!(operation(14, &key, &[0; 32], &expected, &mut [0; 72]), Ok(1));
        assert_eq!(operation(14, &key, &[1; 32], &expected, &mut [0; 72]), Ok(0));
        assert_eq!(operation(14, &[], &[], &[], &mut [0; 72]), Err(PUBLIC));
        assert_eq!(run(13, &secret, &[], &[0; 31]), Err(AUXILIARY));
    }
    #[test]
    fn bip341_secret_tweaks() {
        let mut count = 0;
        for line in include_str!("../../tests/vectors/bip341-secret-tweaks.csv").lines().skip(1) {
            let f: Vec<Vec<u8>> = line.split(',').map(hex).collect();
            assert_eq!(run(16, &f[0], &f[1], &[]).unwrap(), f[2]);
            let public = run(0, &f[0], &[], &[]).unwrap();
            let xonly = run(12, &public, &[], &[]).unwrap();
            let tweaked_public = run(15, &xonly, &f[1], &[]).unwrap();
            assert_eq!(run(0, &f[2], &[], &[]).unwrap(), tweaked_public);
            count += 1;
        }
        assert_eq!(count, 7);
        let one = hex("0000000000000000000000000000000000000000000000000000000000000001");
        let minus_one = hex("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140");
        assert_eq!(run(16, &one, &[0; 32], &[]).unwrap(), one);
        assert_eq!(run(16, &minus_one, &[0; 32], &[]).unwrap(), one);
        assert_eq!(run(16, &one, &minus_one, &[]), Err(INFINITY));
        assert_eq!(run(16, &[0; 32], &[0; 32], &[]), Err(SECRET));
        assert_eq!(run(16, &one, &[], &[]), Err(SCALAR));
    }
    #[test]
    fn independent_rfc6979_boundary_vectors() {
        let mut count = 0;
        for line in include_str!("../../tests/vectors/ecdsa-rfc6979.csv").lines().skip(1) {
            let f: Vec<Vec<u8>> = line.split(',').map(hex).collect();
            assert_eq!(f.len(), 6);
            assert_eq!(run(0, &f[0], &[], &[]).unwrap(), f[5]);
            assert_eq!(run(7, &f[0], &f[1], &[]).unwrap(), f[2], "RFC6979 case {count}");
            assert_eq!(operation(8, &f[5], &f[1], &f[2], &mut [0; 72]), Ok(1));
            assert_eq!(operation(8, &f[5], &f[1], &f[3], &mut [0; 72]), Ok(1));
            assert_eq!(run(9, &f[2], &[], &[]).unwrap(), f[4]);
            assert_eq!(run(10, &f[4], &[], &[]).unwrap(), f[2]);
            assert_eq!(run(11, &f[3], &[], &[]).unwrap(), f[2]);
            count += 1;
        }
        assert_eq!(count, 8);
    }
    #[test]
    fn ecdsa_determinism_der_and_validation() {
        let secret = [1u8; 32];
        let key = run(0, &secret, &[], &[]).unwrap();
        let signature = run(7, &secret, &[2; 32], &[]).unwrap();
        assert_eq!(run(7, &secret, &[2; 32], &[]).unwrap(), signature);
        assert_eq!(operation(8, &key, &[2; 32], &signature, &mut [0; 72]), Ok(1));
        assert_eq!(operation(8, &key, &[3; 32], &signature, &mut [0; 72]), Ok(0));
        assert_eq!(operation(8, &key, &[2; 31], &signature, &mut [0; 72]), Err(DIGEST));
        let der = run(9, &signature, &[], &[]).unwrap();
        assert_eq!(run(10, &der, &[], &[]).unwrap(), signature);
        assert_eq!(run(11, &signature, &[], &[]).unwrap(), signature);
        assert_eq!(run(9, &[0; 64], &[], &[]), Err(SIGNATURE));
        assert_eq!(run(10, &[0x30, 6, 2, 1, 0, 2, 1, 1], &[], &[]), Err(SIGNATURE));
        let mut trailing = der.clone(); trailing.push(0);
        assert_eq!(run(10, &trailing, &[], &[]), Err(SIGNATURE));
    }
    #[test]
    fn public_variable_time_lincomb_matches_constant_time() {
        use k256::elliptic_curve::ops::LinearCombination;
        let points = [ProjectivePoint::IDENTITY, ProjectivePoint::GENERATOR,
            -ProjectivePoint::GENERATOR, ProjectivePoint::GENERATOR * Scalar::from(17u64)];
        let mut scalars = vec![Scalar::ZERO, Scalar::ONE, -Scalar::ONE];
        // Boundaries around all bits exercise GLV splitting and NAF carries.
        for bit in 0..256 {
            let mut bytes = [0u8; 32];
            bytes[31 - bit / 8] = 1 << (bit % 8);
            let value = <Scalar as Reduce<U256>>::reduce_bytes(&bytes.into());
            scalars.extend([value - Scalar::ONE, value, value + Scalar::ONE]);
        }
        for i in 0u64..512 {
            let hash = Sha256::new().chain_update(b"public-lincomb-differential")
                .chain_update(i.to_be_bytes()).finalize();
            scalars.push(<Scalar as Reduce<U256>>::reduce_bytes(&hash));
        }
        for (i, k) in scalars.iter().enumerate() {
            let l = &scalars[(i * 73 + 19) % scalars.len()];
            let x = &points[i % points.len()];
            let y = &points[(i / points.len()) % points.len()];
            assert_eq!(ProjectivePoint::lincomb_vartime(x, k, y, l),
                ProjectivePoint::lincomb(x, k, y, l), "pair {i}");
        }
    }

    #[test]
    fn output_initialization_and_no_input_mutation() {
        let mut secret = [1; 34]; secret[0] = 0xa5; secret[33] = 0x5a;
        let saved = secret;
        let mut out = [0xa5; 74];
        let result = unsafe { secp256k1_call(0, secret.as_ptr().add(1), 32, secret.as_ptr(), 0, secret.as_ptr(), 0, out.as_mut_ptr().add(1)) };
        assert_eq!(result, 33); assert_eq!(secret, saved);
        assert_eq!(out[0], 0xa5); assert_eq!(out[73], 0xa5);
        assert_eq!(&out[34..73], &[0xa5; 39]);
    }
}
