//! Allocation-free NIST P-256 operations using RustCrypto p256.
//! Inputs are borrowed synchronously and all outputs are caller-owned managed
//! Blob payloads. No pointer or mutable state is retained between calls.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

use ecdsa::hazmat::DigestPrimitive;
use p256::ecdsa::Signature;
use p256::elliptic_curve::subtle::{ConditionallySelectable, ConstantTimeEq};
use p256::elliptic_curve::{
    Curve, FieldBytesEncoding,
    bigint::U256,
    ff::PrimeField,
    group::Group,
    ops::{Invert, Reduce},
    point::AffineCoordinates,
    sec1::ToEncodedPoint,
    zeroize::{Zeroize, Zeroizing},
};
use p256::{AffinePoint, NistP256, ProjectivePoint, PublicKey, Scalar, SecretKey};

const INVALID_SECRET_KEY: i64 = -1;
const INVALID_PUBLIC_KEY: i64 = -2;
const INVALID_DIGEST: i64 = -3;
const INVALID_SIGNATURE: i64 = -4;

fn secret(input: &[u8]) -> Result<SecretKey, i64> {
    if input.len() != 32 {
        return Err(INVALID_SECRET_KEY);
    }
    SecretKey::from_slice(input).map_err(|_| INVALID_SECRET_KEY)
}

fn public(input: &[u8]) -> Result<PublicKey, i64> {
    // SEC1 identity, hybrid, raw XY and noncanonical encodings are excluded.
    if !matches!(
        (input.len(), input.first()),
        (33, Some(2 | 3)) | (65, Some(4))
    ) {
        return Err(INVALID_PUBLIC_KEY);
    }
    PublicKey::from_sec1_bytes(input).map_err(|_| INVALID_PUBLIC_KEY)
}

fn signature(input: &[u8]) -> Result<Signature, i64> {
    Signature::from_slice(input).map_err(|_| INVALID_SIGNATURE)
}

fn digest(input: &[u8]) -> Result<(), i64> {
    if input.len() == 32 {
        Ok(())
    } else {
        Err(INVALID_DIGEST)
    }
}

const GENERATOR_COMB: [[u8; 65]; 15] = [
    [
        0x04, 0x6b, 0x17, 0xd1, 0xf2, 0xe1, 0x2c, 0x42, 0x47, 0xf8, 0xbc, 0xe6, 0xe5, 0x63, 0xa4,
        0x40, 0xf2, 0x77, 0x03, 0x7d, 0x81, 0x2d, 0xeb, 0x33, 0xa0, 0xf4, 0xa1, 0x39, 0x45, 0xd8,
        0x98, 0xc2, 0x96, 0x4f, 0xe3, 0x42, 0xe2, 0xfe, 0x1a, 0x7f, 0x9b, 0x8e, 0xe7, 0xeb, 0x4a,
        0x7c, 0x0f, 0x9e, 0x16, 0x2b, 0xce, 0x33, 0x57, 0x6b, 0x31, 0x5e, 0xce, 0xcb, 0xb6, 0x40,
        0x68, 0x37, 0xbf, 0x51, 0xf5,
    ],
    [
        0x04, 0x0f, 0xa8, 0x22, 0xbc, 0x28, 0x11, 0xaa, 0xa5, 0x84, 0x92, 0x59, 0x2e, 0x32, 0x6e,
        0x25, 0xde, 0x29, 0x49, 0x3b, 0xaa, 0xad, 0x65, 0x1f, 0x7e, 0x90, 0xe7, 0x5c, 0xb4, 0x8e,
        0x14, 0xdb, 0x63, 0xbf, 0xf4, 0x4a, 0xe8, 0xf5, 0xdb, 0xa8, 0x0d, 0x6f, 0x4a, 0xd4, 0xbc,
        0xb3, 0xdf, 0x18, 0x8b, 0x34, 0xb1, 0xa6, 0x50, 0x50, 0xfe, 0x82, 0xf5, 0xe4, 0x11, 0x24,
        0x54, 0x5f, 0x46, 0x2e, 0xe7,
    ],
    [
        0x04, 0x30, 0x0a, 0x4b, 0xbc, 0x89, 0xd6, 0x72, 0x6f, 0xb2, 0x57, 0xc0, 0xde, 0x95, 0xe0,
        0x27, 0x89, 0xe9, 0x6c, 0x98, 0xfd, 0x0d, 0x35, 0xf1, 0xfa, 0x93, 0x39, 0x1c, 0xe2, 0x09,
        0x79, 0x92, 0xaf, 0x72, 0xaa, 0xc7, 0xe0, 0xd0, 0x9b, 0x46, 0x44, 0x7f, 0x1d, 0xdb, 0x25,
        0xff, 0x1e, 0x3c, 0x6f, 0x5b, 0xb1, 0xee, 0xad, 0xa9, 0xd8, 0x06, 0xa5, 0xaa, 0x54, 0xa2,
        0x91, 0xc0, 0x81, 0x27, 0xa0,
    ],
    [
        0x04, 0x44, 0x7d, 0x73, 0x9b, 0xee, 0xdb, 0x5e, 0x67, 0xfb, 0x98, 0x2f, 0xd5, 0x88, 0xc6,
        0x76, 0x6e, 0xfc, 0x35, 0xff, 0x7d, 0xc2, 0x97, 0xea, 0xc3, 0x57, 0xc8, 0x4f, 0xc9, 0xd7,
        0x89, 0xbd, 0x85, 0x2d, 0x48, 0x25, 0xab, 0x83, 0x41, 0x31, 0xee, 0xe1, 0x2e, 0x9d, 0x95,
        0x3a, 0x4a, 0xaf, 0xf7, 0x3d, 0x34, 0x9b, 0x95, 0xa7, 0xfa, 0xe5, 0x00, 0x0c, 0x7e, 0x33,
        0xc9, 0x72, 0xe2, 0x5b, 0x32,
    ],
    [
        0x04, 0xef, 0x95, 0x19, 0x32, 0x8a, 0x9c, 0x72, 0xff, 0xdd, 0xc6, 0x06, 0x8b, 0xb9, 0x1d,
        0xfc, 0x60, 0xef, 0x7f, 0xbd, 0x2b, 0x1a, 0x0a, 0x11, 0xb7, 0x13, 0x94, 0x9c, 0x93, 0x2a,
        0x1d, 0x36, 0x7f, 0x61, 0x1e, 0x9f, 0xc3, 0x7d, 0xbb, 0x2c, 0x9b, 0xc1, 0xee, 0x98, 0x07,
        0x02, 0x2c, 0x21, 0x9c, 0x23, 0x18, 0x3b, 0x08, 0x95, 0xca, 0x17, 0x40, 0x19, 0x60, 0x35,
        0xa7, 0x73, 0x76, 0xd8, 0xa8,
    ],
    [
        0x04, 0x55, 0x06, 0x63, 0x79, 0x7b, 0x51, 0xf5, 0xd8, 0x7d, 0xea, 0x64, 0x82, 0xe1, 0x12,
        0x38, 0xbf, 0x29, 0x36, 0xdf, 0x5e, 0xc6, 0xc9, 0xbc, 0x36, 0xca, 0xe2, 0xb1, 0x92, 0x0b,
        0x57, 0xf4, 0xbc, 0x15, 0x71, 0x64, 0x84, 0x8a, 0xec, 0xb8, 0x51, 0x0a, 0xfa, 0x40, 0x01,
        0x8d, 0x9d, 0x50, 0xe5, 0x9f, 0xb3, 0xd5, 0x76, 0xdb, 0xde, 0xfb, 0xe1, 0x44, 0xff, 0xe2,
        0x16, 0x34, 0x8a, 0x96, 0x4c,
    ],
    [
        0x04, 0xeb, 0x5d, 0x77, 0x45, 0xb2, 0x11, 0x41, 0xea, 0xa2, 0xe8, 0xf4, 0x83, 0xf4, 0x3e,
        0x43, 0x91, 0x7c, 0xcd, 0x84, 0xe7, 0x0d, 0x71, 0x5f, 0x26, 0xe4, 0x8e, 0xca, 0xff, 0xfc,
        0x5c, 0xde, 0x01, 0xea, 0xfd, 0x72, 0xeb, 0xdb, 0xec, 0xc1, 0x7b, 0x09, 0x90, 0xe6, 0xa1,
        0x58, 0x00, 0x6c, 0xee, 0x85, 0xf2, 0x2c, 0xfe, 0x28, 0x44, 0xb6, 0x45, 0xca, 0xc9, 0x17,
        0xe2, 0x73, 0x1a, 0x34, 0x79,
    ],
    [
        0x04, 0xa6, 0xd3, 0x96, 0x77, 0xa7, 0x84, 0x92, 0x76, 0x27, 0x36, 0xff, 0x83, 0x44, 0x31,
        0x5f, 0xc5, 0x96, 0x43, 0x95, 0x91, 0xa3, 0xc6, 0xb9, 0x4a, 0x6c, 0xf2, 0x0f, 0xfb, 0x31,
        0x37, 0x28, 0xbe, 0x67, 0x4f, 0x84, 0x74, 0x9b, 0x0b, 0x88, 0x16, 0x66, 0xb8, 0xba, 0xbd,
        0x2d, 0x27, 0xec, 0xdf, 0x82, 0x4a, 0x92, 0x0c, 0x22, 0x84, 0x05, 0x9b, 0xf2, 0xba, 0xb8,
        0x33, 0xc3, 0x57, 0xf5, 0xf4,
    ],
    [
        0x04, 0x4e, 0x76, 0x9e, 0x76, 0x72, 0xc9, 0xdd, 0xad, 0x31, 0x85, 0x5f, 0x7d, 0xb8, 0xc7,
        0xfe, 0xdb, 0x74, 0xe0, 0x2f, 0x08, 0x02, 0x03, 0xa5, 0x6b, 0x2d, 0xf4, 0x8c, 0x04, 0x67,
        0x7c, 0x8a, 0x3e, 0x42, 0xb9, 0x90, 0x82, 0xde, 0x83, 0x06, 0x63, 0x1e, 0xc0, 0x05, 0x72,
        0x06, 0x94, 0x72, 0x81, 0xfb, 0x9a, 0xe1, 0x6f, 0x3b, 0x91, 0x22, 0xa5, 0xa4, 0xc3, 0x61,
        0x65, 0xb8, 0x24, 0xbb, 0xb0,
    ],
    [
        0x04, 0x78, 0x87, 0x8e, 0xf6, 0x1c, 0x6c, 0xe0, 0x4d, 0x7f, 0xdc, 0x1c, 0xa0, 0x08, 0xa1,
        0xc4, 0x78, 0xd1, 0xf8, 0x9e, 0x79, 0x9c, 0x0c, 0xe1, 0x31, 0x6e, 0xf9, 0x51, 0x50, 0xdd,
        0xa8, 0x68, 0xb9, 0xb6, 0xcb, 0x3f, 0x5d, 0x7b, 0x72, 0xc3, 0x21, 0xde, 0x53, 0x14, 0x2c,
        0x12, 0x30, 0x9d, 0xef, 0x6a, 0xce, 0x57, 0x0e, 0xbd, 0xe0, 0x8d, 0x4f, 0x9c, 0x62, 0xb9,
        0x12, 0x1f, 0xe0, 0xd9, 0x76,
    ],
    [
        0x04, 0x0c, 0x88, 0xbc, 0x4d, 0x71, 0x6b, 0x12, 0x87, 0x59, 0x5c, 0x52, 0x20, 0x81, 0x2f,
        0xfc, 0xae, 0x5b, 0x82, 0xdd, 0x5b, 0xd5, 0x4f, 0xb4, 0x96, 0x7f, 0x99, 0x1e, 0xd2, 0xc3,
        0x1a, 0x35, 0x73, 0xdd, 0x5d, 0xde, 0xa3, 0xf3, 0x90, 0x1d, 0xc6, 0x18, 0xd1, 0xb5, 0xb3,
        0x9c, 0x04, 0xe6, 0xaa, 0x7c, 0x81, 0x81, 0xf4, 0xdf, 0x25, 0x64, 0xf3, 0x3a, 0x57, 0xbf,
        0x63, 0x5f, 0x48, 0xac, 0xa8,
    ],
    [
        0x04, 0x68, 0xf3, 0x44, 0xaf, 0x6b, 0x31, 0x74, 0x66, 0xef, 0xe0, 0xa4, 0x23, 0x08, 0x3e,
        0x49, 0xf3, 0x43, 0xa0, 0xa2, 0x8c, 0x42, 0xba, 0x79, 0x2f, 0xe9, 0x6a, 0x79, 0xfb, 0x3e,
        0x72, 0xad, 0x0c, 0x31, 0xb9, 0xc4, 0x05, 0xf8, 0x54, 0x0a, 0x20, 0x60, 0x4e, 0xd9, 0x3c,
        0x24, 0xd6, 0x7f, 0xf3, 0x66, 0x8b, 0xfc, 0x22, 0x71, 0xf5, 0xc6, 0x26, 0xcd, 0xfe, 0x17,
        0xdb, 0x3f, 0xb2, 0x4d, 0x4a,
    ],
    [
        0x04, 0x40, 0x52, 0xbf, 0x4b, 0x6f, 0x46, 0x1d, 0xb9, 0x66, 0x3c, 0x62, 0xc3, 0xed, 0xba,
        0xd7, 0xa0, 0x0d, 0x1a, 0x10, 0x14, 0x4e, 0xc3, 0x9c, 0x28, 0xd3, 0x6b, 0x47, 0x89, 0xa2,
        0x58, 0x2e, 0x7f, 0xfe, 0xcf, 0x4d, 0x51, 0x90, 0xb0, 0xfc, 0x61, 0x86, 0x2b, 0xe6, 0xbd,
        0x71, 0xd7, 0x0c, 0xc8, 0xe7, 0x24, 0xf3, 0x39, 0x99, 0xbf, 0xcc, 0x5b, 0x23, 0x5a, 0x27,
        0xc3, 0x18, 0x8d, 0x25, 0xeb,
    ],
    [
        0x04, 0x1e, 0xdd, 0xba, 0xe2, 0xc8, 0x02, 0xe4, 0x1a, 0x12, 0x32, 0x02, 0xa8, 0xf6, 0x2b,
        0xff, 0x7a, 0xaf, 0xdf, 0x5c, 0xc0, 0x85, 0x26, 0xa7, 0xa4, 0x74, 0x34, 0x6c, 0x10, 0xa1,
        0xd4, 0xcf, 0xac, 0x43, 0x10, 0x4d, 0x86, 0x56, 0x0e, 0xbc, 0xfc, 0x0c, 0x45, 0xf4, 0x52,
        0x73, 0xdb, 0x33, 0xa0, 0x36, 0xe0, 0x6b, 0x7e, 0x4c, 0x70, 0x19, 0x17, 0x8f, 0xa0, 0xaf,
        0x2d, 0xd6, 0x03, 0xf8, 0x44,
    ],
    [
        0x04, 0xb4, 0x8e, 0x26, 0xb4, 0x84, 0xf7, 0xa2, 0x1c, 0x0a, 0x4a, 0x46, 0xfb, 0x6a, 0xaf,
        0x36, 0x3a, 0x66, 0xb0, 0xde, 0x32, 0x25, 0xc4, 0x74, 0x4b, 0x96, 0x15, 0xb5, 0x11, 0x0d,
        0x1d, 0x78, 0xe5, 0xfa, 0xc0, 0x15, 0x40, 0x4d, 0x4d, 0x3d, 0xab, 0x64, 0x13, 0x1b, 0xcd,
        0xfe, 0xd6, 0xf6, 0x68, 0xc0, 0x04, 0xe4, 0x04, 0x8b, 0x7b, 0x0f, 0x98, 0x06, 0xeb, 0xb0,
        0xf6, 0x21, 0xa0, 0x1b, 0x2d,
    ],
];

// Fixed-base comb: entry bits select G, 2^64 G, 2^128 G, 2^192 G.
// All scalar-dependent selection scans the complete table in fixed time.
fn generator_comb(scalar: &Scalar) -> ProjectivePoint {
    let mut table = [AffinePoint::IDENTITY; 16];
    for i in 1..16 {
        table[i] = *PublicKey::from_sec1_bytes(&GENERATOR_COMB[i - 1])
            .unwrap()
            .as_affine();
    }
    let mut bytes = scalar.to_bytes();
    let mut result = ProjectivePoint::IDENTITY;
    for bit in (0..64).rev() {
        result = result.double();
        let mut digit = 0u8;
        for column in 0..4 {
            let pos = bit + 64 * column;
            digit |= ((bytes[31 - pos / 8] >> (pos & 7)) & 1) << column;
        }
        let mut selected = AffinePoint::IDENTITY;
        for i in 1..16 {
            selected.conditional_assign(&table[i], digit.ct_eq(&(i as u8)));
        }
        result += selected;
    }
    bytes.zeroize();
    result
}

fn public_key(input: &[u8], compressed: bool, output: &mut [u8]) -> Result<usize, i64> {
    let key = secret(input)?;
    let mut scalar = key.to_nonzero_scalar();
    let point = generator_comb(scalar.as_ref())
        .to_affine()
        .to_encoded_point(compressed);
    scalar.zeroize();
    output[..point.len()].copy_from_slice(point.as_bytes());
    Ok(point.len())
}

fn convert_public_key(input: &[u8], compressed: bool, output: &mut [u8]) -> Result<usize, i64> {
    let point = public(input)?.to_encoded_point(compressed);
    output[..point.len()].copy_from_slice(point.as_bytes());
    Ok(point.len())
}

fn sign_prehash(key: &[u8], hash: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    let key = secret(key)?;
    digest(hash)?;
    // Preserve upstream RFC6979 bits2octets and ECDSA arithmetic, but reuse
    // the constant-time fixed-base comb for k*G. Preserve S exactly; callers
    // explicitly request normalization when their protocol requires low S.
    let reduced = <Scalar as Reduce<U256>>::reduce_bytes(hash.into());
    let scalar = Zeroizing::new(key.to_nonzero_scalar());
    let secret_bytes = Zeroizing::new(scalar.to_repr());
    let nonce_bytes = Zeroizing::new(rfc6979::generate_k::<
        <NistP256 as DigestPrimitive>::Digest,
        _,
    >(
        &secret_bytes,
        &NistP256::ORDER.encode_field_bytes(),
        &reduced.to_bytes(),
        &[],
    ));
    // generate_k guarantees 0 < k < n. Inversion must stay constant-time:
    // invert_vartime is used exclusively by public signature verification.
    let nonce = Zeroizing::new(Scalar::from_repr(*nonce_bytes).unwrap());
    let inverse = Zeroizing::new(nonce.invert().unwrap());
    let point = generator_comb(&nonce).to_affine();
    let r = <Scalar as Reduce<U256>>::reduce_bytes(&point.x());
    let product = Zeroizing::new(r * scalar.as_ref());
    let numerator = Zeroizing::new(reduced + *product);
    let s = *inverse * *numerator;
    // Upstream validation rejects the vanishingly rare zero r or s case.
    let sig = Signature::from_scalars(r, s).map_err(|_| INVALID_SIGNATURE)?;
    output[..64].copy_from_slice(&sig.to_bytes());
    Ok(64)
}

// Verification scalars are derived exclusively from the public key, digest and
// signature. Direct table indexing and zero-digit branches below therefore do
// not depend on secret data. Signing and public-key derivation use the separate
// constant-time fixed-base comb.
fn verification_lincomb(u1: &Scalar, q: &ProjectivePoint, u2: &Scalar) -> ProjectivePoint {
    fn table(point: &ProjectivePoint) -> [ProjectivePoint; 8] {
        let mut points = [ProjectivePoint::IDENTITY; 8];
        points[0] = *point;
        let twice = point.double();
        for i in 1..8 {
            points[i] = points[i - 1] + twice;
        }
        points
    }
    // Width-5 nonadjacent digits: each odd digit is in [-15,15] and is
    // followed by at least four zero digits. The extra bit holds a final carry.
    // Everything here depends exclusively on public verification scalars.
    fn nonadjacent(scalar: &Scalar) -> [i8; 257] {
        let bytes = scalar.to_bytes();
        let mut digits = [0i8; 257];
        let mut position = 0;
        let mut carry = 0u8;
        while position < 257 {
            let mut window = carry;
            for offset in 0..5 {
                let bit = position + offset;
                if bit < 256 {
                    window += ((bytes[31 - bit / 8] >> (bit % 8)) & 1) << offset;
                }
            }
            if window & 1 == 0 {
                position += 1;
                continue;
            }
            if window < 16 {
                digits[position] = window as i8;
                carry = 0;
            } else {
                digits[position] = window as i8 - 32;
                carry = 1;
            }
            position += 5;
        }
        digits
    }
    let generator = table(&ProjectivePoint::GENERATOR);
    let public_key = table(q);
    let left = nonadjacent(u1);
    let right = nonadjacent(u2);
    let mut result = ProjectivePoint::IDENTITY;
    for bit in (0..257).rev() {
        result = result.double();
        let a = left[bit];
        let b = right[bit];
        if a > 0 {
            result += generator[a as usize / 2];
        } else if a < 0 {
            result -= generator[(-a) as usize / 2];
        }
        if b > 0 {
            result += public_key[b as usize / 2];
        } else if b < 0 {
            result -= public_key[(-b) as usize / 2];
        }
    }
    result
}

fn verify_prehash(key: &[u8], hash: &[u8], sig: &[u8]) -> Result<bool, i64> {
    let key = public(key)?;
    digest(hash)?;
    let sig = signature(sig)?;
    // Same ECDSA equation and canonical input checks as upstream verify_prehash;
    // simultaneous multiplication shares the two scalars' point doublings.
    let z = <Scalar as Reduce<U256>>::reduce_bytes(hash.into());
    let (r, s) = sig.split_scalars();
    let s_inv = *s.invert_vartime();
    let u1 = z * s_inv;
    let u2 = *r * s_inv;
    let point =
        verification_lincomb(&u1, &ProjectivePoint::from(*key.as_affine()), &u2).to_affine();
    if bool::from(point.is_identity()) {
        return Ok(false);
    }
    Ok(*r == <Scalar as Reduce<U256>>::reduce_bytes(&point.x()))
}

fn signature_to_der(input: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    let der = signature(input)?.to_der();
    output[..der.len()].copy_from_slice(der.as_bytes());
    Ok(der.len())
}

fn signature_from_der(input: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    // RustCrypto's DER parser enforces minimal positive ASN.1 INTEGERs and
    // exact sequence length; from_der also rejects zero or out-of-range r/s.
    let sig = Signature::from_der(input).map_err(|_| INVALID_SIGNATURE)?;
    output[..64].copy_from_slice(&sig.to_bytes());
    Ok(64)
}

fn normalize_signature(input: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    let sig = signature(input)?;
    let sig = sig.normalize_s().unwrap_or(sig);
    output[..64].copy_from_slice(&sig.to_bytes());
    Ok(64)
}

unsafe fn input<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    // Empty inputs need not have a non-null pointer, and are validated normally.
    if len == 0 {
        &[]
    } else {
        unsafe { core::slice::from_raw_parts(ptr, len) }
    }
}
unsafe fn output<'a>(ptr: *mut u8, len: usize) -> &'a mut [u8] {
    // Initialize before forming a Rust reference, including error paths.
    unsafe { core::ptr::write_bytes(ptr, 0, len) };
    unsafe { core::slice::from_raw_parts_mut(ptr, len) }
}
fn status(result: Result<usize, i64>) -> i64 {
    match result {
        Ok(length) => length as i64,
        Err(error) => error,
    }
}

/// # Safety
/// Inputs point to readable buffers; out points to 33 bytes when compressed is
/// nonzero and 65 bytes otherwise. Output does not alias any input. All buffers
/// remain live throughout this synchronous call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn p256_public_key(
    ptr: *const u8,
    len: usize,
    compressed: u64,
    out: *mut u8,
) -> i64 {
    let compressed = compressed != 0;
    status(public_key(unsafe { input(ptr, len) }, compressed, unsafe {
        output(out, if compressed { 33 } else { 65 })
    }))
}

/// # Safety
/// Same buffer contract as p256_public_key.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn p256_convert_public_key(
    ptr: *const u8,
    len: usize,
    compressed: u64,
    out: *mut u8,
) -> i64 {
    let compressed = compressed != 0;
    status(convert_public_key(
        unsafe { input(ptr, len) },
        compressed,
        unsafe { output(out, if compressed { 33 } else { 65 }) },
    ))
}

/// # Safety
/// Inputs point to readable disjoint buffers and out to 64 writable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn p256_sign_prehash(
    key: *const u8,
    key_len: usize,
    hash: *const u8,
    hash_len: usize,
    out: *mut u8,
) -> i64 {
    status(sign_prehash(
        unsafe { input(key, key_len) },
        unsafe { input(hash, hash_len) },
        unsafe { output(out, 64) },
    ))
}

/// # Safety
/// Inputs point to readable buffers that remain valid for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn p256_verify_prehash(
    key: *const u8,
    key_len: usize,
    hash: *const u8,
    hash_len: usize,
    sig: *const u8,
    sig_len: usize,
) -> i64 {
    match verify_prehash(
        unsafe { input(key, key_len) },
        unsafe { input(hash, hash_len) },
        unsafe { input(sig, sig_len) },
    ) {
        Ok(valid) => i64::from(valid),
        Err(error) => error,
    }
}

macro_rules! unary_export {
    ($name:ident, $implementation:ident, $capacity:expr) => {
        /// # Safety
        /// Input points to len readable bytes; out points to the documented
        /// output capacity, disjoint from input. Buffers remain live for call.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(ptr: *const u8, len: usize, out: *mut u8) -> i64 {
            status($implementation(unsafe { input(ptr, len) }, unsafe {
                output(out, $capacity)
            }))
        }
    };
}
unary_export!(p256_signature_to_der, signature_to_der, 72);
unary_export!(p256_signature_from_der, signature_from_der, 64);
unary_export!(p256_normalize_signature, normalize_signature, 64);

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn hex(value: &str) -> Vec<u8> {
        (0..value.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&value[i..i + 2], 16).unwrap())
            .collect()
    }
    const SECRET: &str = "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721";
    const PUBLIC: &str = "0360fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6";
    const HASH: &str = "af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf";
    const SIGNATURE: &str = "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8";

    #[test]
    fn rfc6979_a_2_5_sha256_sample() {
        let mut out = [0; 72];
        assert_eq!(public_key(&hex(SECRET), true, &mut out), Ok(33));
        assert_eq!(&out[..33], hex(PUBLIC));
        assert_eq!(sign_prehash(&hex(SECRET), &hex(HASH), &mut out), Ok(64));
        assert_eq!(&out[..64], hex(SIGNATURE));
        assert_eq!(
            verify_prehash(&hex(PUBLIC), &hex(HASH), &hex(SIGNATURE)),
            Ok(true)
        );
        let mut wrong = hex(HASH);
        wrong[0] ^= 1;
        assert_eq!(
            verify_prehash(&hex(PUBLIC), &wrong, &hex(SIGNATURE)),
            Ok(false)
        );
        assert_eq!(normalize_signature(&hex(SIGNATURE), &mut out), Ok(64));
        assert_eq!(
            verify_prehash(&hex(PUBLIC), &hex(HASH), &out[..64]),
            Ok(true)
        );
        assert_ne!(&out[..64], hex(SIGNATURE));
    }

    #[test]
    fn strict_scalars_keys_and_der() {
        let mut out = [0; 72];
        for key in [
            vec![],
            vec![1; 31],
            vec![1; 33],
            vec![0; 32],
            vec![255; 32],
            hex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551"),
        ] {
            assert_eq!(public_key(&key, true, &mut out), Err(INVALID_SECRET_KEY));
        }
        for key in [
            vec![],
            vec![0],
            vec![4; 65],
            vec![2; 32],
            vec![6; 65],
            vec![255; 33],
        ] {
            assert_eq!(
                convert_public_key(&key, true, &mut out),
                Err(INVALID_PUBLIC_KEY)
            );
        }
        for sig in [vec![], vec![0; 64], vec![255; 64], vec![1; 63], vec![1; 65]] {
            assert_eq!(signature_to_der(&sig, &mut out), Err(INVALID_SIGNATURE));
        }
        for der in [
            hex("3006020101020100"),
            hex("300702020001020101"),
            hex("3006020180020101"),
            hex("300602010102010100"),
            hex("308106020101020101"),
        ] {
            assert_eq!(signature_from_der(&der, &mut out), Err(INVALID_SIGNATURE));
        }
        let n = signature_to_der(&hex(SIGNATURE), &mut out).unwrap();
        let der = out[..n].to_vec();
        assert_eq!(signature_from_der(&der, &mut out), Ok(64));
        assert_eq!(&out[..64], hex(SIGNATURE));
        assert_eq!(
            verify_prehash(&hex(PUBLIC), &[0; 31], &hex(SIGNATURE)),
            Err(INVALID_DIGEST)
        );
    }

    #[test]
    fn pointer_abi_and_initialized_error_output() {
        let mut key = vec![0xa5];
        key.extend_from_slice(&hex(SECRET));
        key.push(0x5a);
        let saved = key.clone();
        let mut out = [0xa5; 67];
        assert_eq!(
            unsafe { p256_public_key(key.as_ptr().add(1), 32, 0, out.as_mut_ptr().add(1)) },
            65
        );
        assert_eq!(out[0], 0xa5);
        assert_eq!(out[66], 0xa5);
        assert_eq!(key, saved);
        let pub_uncompressed = out[1..66].to_vec();
        assert_eq!(
            unsafe {
                p256_convert_public_key(pub_uncompressed.as_ptr(), 65, 1, out.as_mut_ptr().add(1))
            },
            33
        );
        assert_eq!(&out[1..34], hex(PUBLIC));
        assert_eq!(
            unsafe {
                p256_sign_prehash(
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0,
                    out.as_mut_ptr().add(1),
                )
            },
            INVALID_SECRET_KEY
        );
        assert_eq!(&out[1..65], &[0; 64]);
        assert_eq!(out[0], 0xa5);
        assert_eq!(out[66], 0xa5);
    }

    #[test]
    fn full_wycheproof_corpus() {
        use sha2::{Digest, Sha256};
        let corpus: serde_json::Value = serde_json::from_str(include_str!(
            "../../tests/vectors/wycheproof-ecdsa-secp256r1-sha256.json"
        ))
        .unwrap();
        let mut count = 0;
        for group in corpus["testGroups"].as_array().unwrap() {
            let key = hex(group["publicKey"]["uncompressed"].as_str().unwrap());
            for vector in group["tests"].as_array().unwrap() {
                let message = hex(vector["msg"].as_str().unwrap());
                let hash = Sha256::digest(&message);
                let der = hex(vector["sig"].as_str().unwrap());
                let mut compact = [0; 64];
                let valid = signature_from_der(&der, &mut compact).is_ok()
                    && verify_prehash(&key, &hash, &compact) == Ok(true);
                assert_eq!(
                    valid,
                    vector["result"] == "valid",
                    "tcId {}: {}",
                    vector["tcId"],
                    vector["comment"]
                );
                count += 1;
            }
        }
        assert_eq!(count, 484);
    }

    #[test]
    fn rfc6979_bits2octets_boundaries() {
        // Independent RFC6979/HMAC implementation with OpenSSL point derivation.
        // Complete provenance and generator live in tests/vectors/.
        let vectors = [
            (
                "0000000000000000000000000000000000000000000000000000000000000000",
                "68897a78df51058b490c6012251c95921abba96e2e488c8cc998942e440db9b780587fb387363a1df2c9e83c00f8ca990fc0a55b5e470946499b82ca3b552a87",
            ),
            (
                "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550",
                "c675c43e829a5e838be6014515bcc7d82fb8d3053c770d32d322a9e9e35530e749996eb95b9f4471484b96cd60fef80a14f6504ed7279e133404a61e1ab8aee5",
            ),
            (
                "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
                "68897a78df51058b490c6012251c95921abba96e2e488c8cc998942e440db9b780587fb387363a1df2c9e83c00f8ca990fc0a55b5e470946499b82ca3b552a87",
            ),
            (
                "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                "1f2adbc54b88764c279f689fc9505959fc9e73e80dc20889a4e0be91865de75b9d109b65e2fbfc0ae42ba0b2e5f03670cd458cff4882df6783f3d93d607d1755",
            ),
        ];
        for (hash, expected) in vectors {
            let mut out = [0; 64];
            assert_eq!(sign_prehash(&hex(SECRET), &hex(hash), &mut out), Ok(64));
            assert_eq!(&out[..], hex(expected));
            assert_eq!(verify_prehash(&hex(PUBLIC), &hex(hash), &out), Ok(true));
        }
    }

    #[test]
    fn comb_signing_matches_upstream() {
        use ecdsa::hazmat::SignPrimitive;
        use sha2::{Digest, Sha256};
        let order = NistP256::ORDER.encode_field_bytes();
        let before_order = (-Scalar::ONE).to_bytes();
        let mut keys = vec![Scalar::ONE, Scalar::from(2u64), -Scalar::ONE];
        let hashes = [
            [0u8; 32],
            Scalar::ONE.to_bytes().into(),
            before_order.into(),
            order.into(),
            [0xffu8; 32],
            hex(HASH).try_into().unwrap(),
        ];
        for bit in 0..256 {
            let mut bytes = [0u8; 32];
            bytes[31 - bit / 8] = 1 << (bit & 7);
            keys.push(Scalar::from_repr(bytes.into()).unwrap());
        }
        for i in 0u32..256 {
            keys.push(<Scalar as Reduce<U256>>::reduce_bytes(&Sha256::digest(
                i.to_be_bytes(),
            )));
        }
        for (i, scalar) in keys.iter().enumerate() {
            let hash: [u8; 32] = if i < 3 {
                // Boundary secrets exercise every digest boundary below.
                hashes[i]
            } else {
                Sha256::digest((i as u32).to_le_bytes()).into()
            };
            let selected = if i < 3 {
                hashes.as_slice()
            } else {
                core::slice::from_ref(&hash)
            };
            for hash in selected {
                let reduced = <Scalar as Reduce<U256>>::reduce_bytes(hash.into()).to_bytes();
                let expected: Signature = scalar
                    .try_sign_prehashed_rfc6979::<Sha256>(&reduced, &[])
                    .unwrap()
                    .0;
                let mut output = [0u8; 64];
                assert_eq!(sign_prehash(&scalar.to_bytes(), hash, &mut output), Ok(64));
                assert_eq!(output.as_slice(), &expected.to_bytes()[..]);
                let key = (ProjectivePoint::GENERATOR * scalar)
                    .to_affine()
                    .to_encoded_point(true);
                assert_eq!(verify_prehash(key.as_bytes(), hash, &output), Ok(true));
            }
        }
    }

    #[test]
    fn verification_lincomb_matches_upstream() {
        let values = [
            "0000000000000000000000000000000000000000000000000000000000000000",
            "0000000000000000000000000000000000000000000000000000000000000001",
            "0000000000000000000000000000000000000000000000000000000000000002",
            "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550",
            "8000000000000000000000000000000000000000000000000000000000000000",
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
        ];
        let keys = [
            ProjectivePoint::GENERATOR,
            -ProjectivePoint::GENERATOR,
            ProjectivePoint::from(*public(&hex(PUBLIC)).unwrap().as_affine()),
        ];
        for key in keys {
            for a in values {
                for b in values {
                    let a = <Scalar as Reduce<U256>>::reduce_bytes(hex(a).as_slice().into());
                    let b = <Scalar as Reduce<U256>>::reduce_bytes(hex(b).as_slice().into());
                    assert_eq!(
                        verification_lincomb(&a, &key, &b),
                        ProjectivePoint::GENERATOR * a + key * b
                    );
                }
            }
        }
    }
    #[test]
    fn comb_matches_upstream() {
        use sha2::{Digest, Sha256};
        let mut before_order =
            hex("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
        before_order[31] -= 1;
        let mut cases = vec![vec![0; 32], vec![1; 32], vec![255; 32], before_order];
        for bit in 0..256 {
            let mut bytes = vec![0; 32];
            bytes[31 - bit / 8] = 1 << (bit & 7);
            cases.push(bytes);
        }
        for i in 0u32..1024 {
            cases.push(Sha256::digest(i.to_be_bytes()).to_vec());
        }
        for bytes in cases {
            let scalar = <Scalar as Reduce<U256>>::reduce_bytes(bytes.as_slice().into());
            let expected = (ProjectivePoint::GENERATOR * scalar).to_affine();
            assert_eq!(generator_comb(&scalar).to_affine(), expected);
            for compressed in [false, true] {
                let mut actual = [0u8; 65];
                let result = public_key(&scalar.to_bytes(), compressed, &mut actual);
                if scalar == Scalar::ZERO {
                    assert_eq!(result, Err(INVALID_SECRET_KEY));
                } else {
                    let encoded = expected.to_encoded_point(compressed);
                    assert_eq!(result, Ok(encoded.len()));
                    assert_eq!(&actual[..encoded.len()], encoded.as_bytes());
                }
            }
        }
    }
}
