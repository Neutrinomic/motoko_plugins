//! Stateless, allocation-free secp256k1 operations using RustCrypto k256.
//! Inputs are borrowed Motoko Blobs; caller owns an operation-sized output.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

mod prepared_sign;

const PUBLIC_CACHE_SIZE: usize = 512;

use k256::{ProjectivePoint, PublicKey, Scalar, SecretKey};
use k256::ecdsa::{Signature, hazmat::SignPrimitive};
use k256::elliptic_curve::{PrimeField, group::Group, sec1::ToEncodedPoint, bigint::U256, ops::{Reduce, Invert, MulByGenerator}};
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
fn write(bytes: &[u8], output: &mut [u8]) -> i64 {
    output[..bytes.len()].copy_from_slice(bytes);
    bytes.len() as i64
}
fn encoded(point: ProjectivePoint, compressed: bool, output: &mut [u8]) -> Result<i64> {
    if bool::from(point.is_identity()) { return Err(INFINITY); }
    Ok(write(point.to_affine().to_encoded_point(compressed).as_bytes(), output))
}

// Successful blob operations return their byte length; successful predicates
// return 0 or 1. Negative results are stable typed input/identity errors.
fn operation(op: usize, a: &[u8], b: &[u8], c: &[u8], out: &mut [u8]) -> Result<i64> {
    match op {
        0 => {
            let key = SecretKey::from_slice(a).map_err(|_| SECRET)?;
            // SecretKey::from_slice accepts short inputs. Public API requires 32 bytes.
            if a.len() != 32 { return Err(SECRET); }
            let mut secret = key.to_nonzero_scalar();
            let point = ProjectivePoint::mul_by_generator(&secret);
            secret.zeroize();
            Ok(write(point.to_affine().to_encoded_point(true).as_bytes(), out))
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
        5 => encoded(ProjectivePoint::mul_by_generator(&scalar(a)?), true, out),
        6 => encoded(public(a)?.to_projective() + ProjectivePoint::mul_by_generator(&scalar(b)?), true, out),
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
        8 | 18 => {
            let key = if op == 8 { Some(public(a)?) } else {
                if a.len() != PUBLIC_CACHE_SIZE { return Err(PUBLIC); }
                None
            };
            let digest: [u8; 32] = b.try_into().map_err(|_| DIGEST)?;
            let sig = signature(c)?;
            // Same upstream verification equation and high-S acceptance; all
            // inputs to the variable-time multiplication are public here.
            let z = <Scalar as Reduce<U256>>::reduce_bytes(&digest.into());
            let (r, s) = sig.split_scalars();
            let inverse = *s.invert_vartime();
            let point = match key {
                Some(key) => ProjectivePoint::lincomb_generator_vartime(
                    &(z * inverse), &key.to_projective(), &(*r * inverse)),
                None => ProjectivePoint::lincomb_generator_prepared_vartime(
                    &(z * inverse), a, &(*r * inverse)),
            };
            Ok(i64::from(point.x_matches_scalar_vartime(&r)))
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
        14 | 20 => {
            // Prepared keys are factory-validated even-Y points; only the
            // direct API decodes the external x coordinate on each call.
            let key = if op == 14 {
                if a.len() != 32 { return Err(PUBLIC); }
                Some(k256::schnorr::VerifyingKey::from_bytes(a).map_err(|_| PUBLIC)?)
            } else {
                if a.len() != PUBLIC_CACHE_SIZE { return Err(PUBLIC); }
                None
            };
            let public_x = &a[..32];
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
                .chain_update(&c[..32]).chain_update(public_x).chain_update(b).finalize();
            let e = <Scalar as Reduce<U256>>::reduce_bytes(&challenge);
            let r = match key {
                Some(key) => ProjectivePoint::lincomb_generator_vartime(
                    &s, &ProjectivePoint::from(*key.as_affine()), &-e),
                None => ProjectivePoint::lincomb_generator_prepared_vartime(&s, a, &-e),
            };
            if bool::from(r.is_identity()) { return Ok(0); }
            let point = r.to_affine();
            Ok(i64::from(!bool::from(point.y_is_odd()) && point.x()[..] == c[..32]))
        }
        15 => {
            if a.len() != 32 { return Err(PUBLIC); }
            let key = k256::schnorr::VerifyingKey::from_bytes(a).map_err(|_| PUBLIC)?;
            encoded(ProjectivePoint::from(*key.as_affine()) + ProjectivePoint::mul_by_generator(&scalar(b)?), true, out)
        }
        16 => {
            if a.len() != 32 { return Err(SECRET); }
            // BIP341 parity normalization needs one multiplication, not a
            // Schnorr signing key (which also caches a recomputed public key).
            let key = SecretKey::from_slice(a).map_err(|_| SECRET)?;
            let tweak = scalar(b)?;
            let mut secret = key.to_nonzero_scalar();
            let odd = ProjectivePoint::mul_by_generator(&secret).to_affine().y_is_odd();
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
        17 | 19 => {
            let affine = if op == 17 { *public(a)?.as_affine() } else {
                if a.len() != 32 { return Err(PUBLIC); }
                *k256::schnorr::VerifyingKey::from_bytes(a).map_err(|_| PUBLIC)?.as_affine()
            };
            ProjectivePoint::prepare_verification_key(&affine, &mut out[..PUBLIC_CACHE_SIZE]);
            Ok(PUBLIC_CACHE_SIZE as i64)
        }
        21 => prepared_sign::prepare(a, out),
        22 => prepared_sign::sign(a, b, c, out),
        _ => Err(SIGNATURE),
    }
}

fn output_capacity(op: usize) -> usize {
    match op { 0 | 1 | 3 | 4 | 5 | 6 | 15 => 33, 2 => 65,
        7 | 10 | 11 | 13 | 21 | 22 => 64, 9 => 72, 12 | 16 => 32,
        17 | 19 => PUBLIC_CACHE_SIZE, _ => 0 }
}

/// # Safety
/// Each input points to its length of readable memory; output points to fresh
/// writable bytes of capacity output_capacity(op) and does not alias inputs.
/// If that capacity is zero (predicates), output is ignored and may be null.
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
    if op == 17 || op == 19 {
        let mut bytes = [0u8; PUBLIC_CACHE_SIZE];
        let result = operation(op, a, b, c, &mut bytes).unwrap_or_else(|error| error);
        unsafe { core::ptr::copy_nonoverlapping(bytes.as_ptr(), output, PUBLIC_CACHE_SIZE) };
        return result;
    }
    let mut bytes = [0u8; 72];
    let result = operation(op, a, b, c, &mut bytes).unwrap_or_else(|error| error);
    let capacity = output_capacity(op);
    if capacity != 0 {
        unsafe { core::ptr::copy_nonoverlapping(bytes.as_ptr(), output, capacity) };
    }
    if op == 16 || op == 21 { bytes.zeroize(); }
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
    fn fixed_generator_and_prepared_lincomb_match_constant_time_at_scalar_boundaries() {
        use k256::elliptic_curve::ops::LinearCombination;
        let points = [ProjectivePoint::GENERATOR,
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
            let y = &points[i % points.len()];
            let expected = ProjectivePoint::lincomb(&ProjectivePoint::GENERATOR, k, y, l);
            assert_eq!(ProjectivePoint::lincomb_generator_vartime(k, y, l), expected, "direct pair {i}");
            let mut table = [0; 512];
            ProjectivePoint::prepare_verification_key(&y.to_affine(), &mut table);
            assert_eq!(ProjectivePoint::lincomb_generator_prepared_vartime(k, &table, l), expected, "table pair {i}");
        }
    }

    #[test]
    fn immutable_fixed_generator_matches_generic_at_scalar_boundaries() {
        let mut scalars = vec![Scalar::ZERO, Scalar::ONE, -Scalar::ONE];
        for bit in 0..256 {
            let mut bytes = [0u8; 32];
            bytes[31 - bit / 8] = 1 << (bit % 8);
            let value = <Scalar as Reduce<U256>>::reduce_bytes(&bytes.into());
            scalars.extend([value - Scalar::ONE, value, value + Scalar::ONE]);
        }
        for i in 0u64..512 {
            let hash = Sha256::new().chain_update(b"immutable-fixed-generator-differential")
                .chain_update(i.to_be_bytes()).finalize();
            scalars.push(<Scalar as Reduce<U256>>::reduce_bytes(&hash));
        }
        for (i, scalar) in scalars.iter().enumerate() {
            assert_eq!(ProjectivePoint::mul_by_generator(scalar),
                ProjectivePoint::GENERATOR * scalar, "fixed generator scalar {i}");
        }
    }

    #[test]
    fn inversionless_ecdsa_coordinate_checks_reduction_and_field_wrap() {
        use k256::elliptic_curve::bigint::Encoding;
        let order = U256::from_be_hex("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141");
        let difference = U256::from_be_hex("000000000000000000000000000000014551231950b75fc4402da1722fc9baee");
        assert!(!ProjectivePoint::IDENTITY.x_matches_scalar_vartime(&Scalar::ZERO));
        assert!(!ProjectivePoint::IDENTITY.x_matches_scalar_vartime(&Scalar::ONE));
        for i in 1u64..128 {
            let point = ProjectivePoint::GENERATOR * Scalar::from(i);
            let r = <Scalar as Reduce<U256>>::reduce_bytes(&point.to_affine().x());
            assert!(point.x_matches_scalar_vartime(&r));
            assert!(!point.x_matches_scalar_vartime(&(r + Scalar::ONE)));
        }
        // Construct a real curve point with x >= n; random tests cannot reach
        // this branch with useful probability because p-n is only 129 bits.
        let mut found = false;
        for i in 1u64..64 {
            let x = order.wrapping_add(&U256::from(i));
            let mut bytes = [0u8; 33]; bytes[0] = 2;
            bytes[1..].copy_from_slice(&x.to_be_bytes());
            if let Ok(key) = public(&bytes) {
                let r = Scalar::from(i);
                assert!(key.to_projective().x_matches_scalar_vartime(&r));
                let q = key.to_projective() * r.invert().unwrap();
                let mut sig = [0u8; 64]; sig[..32].copy_from_slice(&r.to_bytes()); sig[63] = 1;
                assert_eq!(operation(8, q.to_affine().to_encoded_point(true).as_bytes(), &[0;32], &sig, &mut []), Ok(1));
                found = true; break;
            }
        }
        assert!(found);
        // Without the r < p-n guard, field reduction of r+n would make this
        // wrong scalar compare equal to G.x and admit a forged equation.
        let x = U256::from_be_slice(&ProjectivePoint::GENERATOR.to_affine().x());
        let wrong = scalar(&x.wrapping_add(&difference).to_be_bytes()).unwrap();
        assert!(!ProjectivePoint::GENERATOR.x_matches_scalar_vartime(&wrong));
        let q = ProjectivePoint::GENERATOR * wrong.invert().unwrap();
        let mut sig = [0u8;64]; sig[..32].copy_from_slice(&wrong.to_bytes()); sig[63] = 1;
        assert_eq!(operation(8, q.to_affine().to_encoded_point(true).as_bytes(), &[0;32], &sig, &mut []), Ok(0));
    }

    #[test]
    fn wide_scalar_square_matches_general_multiplication() {
        let mut scalars = vec![Scalar::ZERO, Scalar::ONE, -Scalar::ONE];
        for bit in 0..256 {
            let mut bytes = [0u8; 32];
            bytes[31 - bit / 8] = 1 << (bit % 8);
            let value = <Scalar as Reduce<U256>>::reduce_bytes(&bytes.into());
            scalars.extend([value - Scalar::ONE, value, value + Scalar::ONE]);
        }
        for i in 0u64..512 {
            let hash = Sha256::new().chain_update(b"wide-scalar-square-differential")
                .chain_update(i.to_be_bytes()).finalize();
            scalars.push(<Scalar as Reduce<U256>>::reduce_bytes(&hash));
        }
        for (i, scalar) in scalars.iter().enumerate() {
            assert_eq!(scalar.square(), scalar * scalar, "wide square scalar {i}");
        }
    }

    #[test]
    fn predicates_accept_null_output_without_accessing_it() {
        let secret = [1u8; 32];
        let key = run(0, &secret, &[], &[]).unwrap();
        let digest = [2u8; 32];
        let signature = run(7, &secret, &digest, &[]).unwrap();
        let schnorr = run(13, &secret, &digest, &[0; 32]).unwrap();
        let xonly = run(12, &key, &[], &[]).unwrap();
        let call = |op, a: &[u8], b: &[u8], c: &[u8]| unsafe {
            secp256k1_call(op, a.as_ptr(), a.len(), b.as_ptr(), b.len(),
                c.as_ptr(), c.len(), core::ptr::null_mut())
        };
        assert_eq!(call(8, &key, &digest, &signature), 1);
        assert_eq!(call(8, &key, &[3; 32], &signature), 0);
        assert_eq!(call(8, &[], &digest, &signature), PUBLIC);
        assert_eq!(call(8, &key, &[], &signature), DIGEST);
        assert_eq!(call(8, &key, &digest, &[]), SIGNATURE);
        assert_eq!(call(14, &xonly, &digest, &schnorr), 1);
        assert_eq!(call(14, &xonly, &[3; 32], &schnorr), 0);
        assert_eq!(call(14, &[], &digest, &schnorr), PUBLIC);
        assert_eq!(call(14, &xonly, &digest, &[]), SIGNATURE);
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
    #[test]
    fn prepared_public_tables_and_fixed_generator_match_vetted_multiplication() {
        use k256::elliptic_curve::ops::LinearCombination;
        let mut scalars = vec![Scalar::ZERO, Scalar::ONE, -Scalar::ONE];
        for i in 0u64..64 {
            let hash = Sha256::new().chain_update(b"prepared-public-crosscheck")
                .chain_update(i.to_be_bytes()).finalize();
            scalars.push(<Scalar as Reduce<U256>>::reduce_bytes(&hash));
        }
        for (i, k) in scalars.iter().enumerate() {
            let l = scalars[(i * 19 + 1) % scalars.len()];
            let q = ProjectivePoint::GENERATOR * Scalar::from(i as u64 + 1);
            let mut table = [0xa5; 512];
            ProjectivePoint::prepare_verification_key(&q.to_affine(), &mut table);
            for j in 0..8 {
                let point = q * Scalar::from(2 * j as u64 + 1);
                let encoded = point.to_affine().to_encoded_point(false);
                assert_eq!(&table[j * 64..(j + 1) * 64], &encoded.as_bytes()[1..]);
            }
            let expected = ProjectivePoint::lincomb(&ProjectivePoint::GENERATOR, k, &q, &l);
            assert_eq!(ProjectivePoint::lincomb_generator_vartime(k, &q, &l), expected, "direct {i}");
            assert_eq!(ProjectivePoint::lincomb_generator_prepared_vartime(k, &table, &l), expected, "table {i}");
        }
    }

    #[test]
    fn prepared_sign_and_verify_preserve_vectors_and_errors() {
        for row in include_str!("../../tests/vectors/bip340.csv").lines().skip(1) {
            let fields: Vec<_> = row.split(',').collect();
            let public = hex(fields[2]);
            let message = hex(fields[4]);
            let sig = hex(fields[5]);
            let mut key = [0u8; PUBLIC_CACHE_SIZE];
            let prepared = operation(19, &public, &[], &[], &mut key);
            let direct = operation(14, &public, &message, &sig, &mut []);
            if prepared.is_ok() {
                assert_eq!(operation(20, &key, &message, &sig, &mut []), direct, "vector {}", fields[0]);
            } else { assert_eq!(prepared, Err(PUBLIC)); assert_eq!(direct, Err(PUBLIC)); }
        }
        let secret = [1; 32];
        let digest = [2; 32];
        let public = run(0, &secret, &[], &[]).unwrap();
        let sig = run(7, &secret, &digest, &[]).unwrap();
        let mut key = [0u8; PUBLIC_CACHE_SIZE];
        assert_eq!(operation(17, &public, &[], &[], &mut key), Ok(PUBLIC_CACHE_SIZE as i64));
        assert_eq!(operation(18, &key, &digest, &sig, &mut []), Ok(1));
        assert_eq!(operation(18, &key, &[3; 32], &sig, &mut []), Ok(0));
        assert_eq!(operation(18, &key, &[], &[], &mut []), Err(DIGEST));
        assert_eq!(operation(18, &key, &digest, &[], &mut []), Err(SIGNATURE));
        let secret_cache = run(21, &secret, &[], &[]).unwrap();
        assert_eq!(run(22, &secret_cache, &digest, &[0; 32]), run(13, &secret, &digest, &[0; 32]));
        assert_eq!(run(22, &secret_cache, &digest, &[]), Err(AUXILIARY));
    }

    #[test]
    fn prepared_ffi_initializes_exact_capacity_and_never_mutates_inputs() {
        let secret = [1; 32];
        let public = run(0, &secret, &[], &[]).unwrap();
        for op in [17, 19, 21] {
            let input = match op { 17 => public.clone(), 19 => public[1..].to_vec(), _ => secret.to_vec() };
            let saved = input.clone();
            let capacity = output_capacity(op);
            for valid in [true, false] {
                let mut output = vec![0xa5; capacity + 2];
                let len = if valid { input.len() } else { 0 };
                let result = unsafe { secp256k1_call(op, input.as_ptr(), len, input.as_ptr(), 0,
                    input.as_ptr(), 0, output.as_mut_ptr().add(1)) };
                assert_eq!(result, if valid { capacity as i64 } else if op == 21 { SECRET } else { PUBLIC });
                assert_eq!((output[0], output[capacity + 1]), (0xa5, 0xa5));
                if !valid { assert!(output[1..=capacity].iter().all(|&b| b == 0)); }
                assert_eq!(input, saved);
            }
        }
    }

}
