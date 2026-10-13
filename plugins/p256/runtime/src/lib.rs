//! Allocation-free NIST P-256 operations using RustCrypto p256.
//! Inputs are borrowed synchronously and all outputs are caller-owned managed
//! Blob payloads. No pointer or mutable state is retained between calls.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

use ecdsa::hazmat::DigestPrimitive;
use p256::ecdsa::Signature;
use p256::elliptic_curve::subtle::{ConditionallySelectable, ConstantTimeEq};
use p256::elliptic_curve::{
    BatchNormalize, Curve, FieldBytesEncoding,
    bigint::{CheckedAdd, U256},
    ff::PrimeField,
    group::Group,
    ops::{Invert, Reduce},
    point::AffineCoordinates,
    sec1::ToEncodedPoint,
    zeroize::{Zeroize, Zeroizing},
};
use p256::{AffinePoint, FieldElement, NistP256, ProjectivePoint, PublicKey, Scalar, SecretKey};

mod prepared_table;
mod secret_table;

#[cfg(test)]
mod projective_tests;

#[cfg(test)]
mod ffi_tests;

#[cfg(test)]
mod encoding_tests;

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

// Split fixed-base comb. Every round scans all 15 nonidentity entries of
// every table, even for a zero digit. All loop bounds and addresses depend
// only on public constants; complete mixed addition handles identity digits.
// The generated Montgomery points are validated offline against independent
// Python arithmetic and OpenSSL; they need no per-call SEC1 parsing.
fn generator_comb(scalar: &Scalar) -> ProjectivePoint {
    let mut tables = [[AffinePoint::IDENTITY; 16]; secret_table::TABLES];
    for (table, words) in tables.iter_mut().zip(secret_table::POINTS.iter()) {
        for (point, words) in table[1..].iter_mut().zip(words.iter()) {
            *point = point_from_words(words);
        }
    }
    let mut bytes = scalar.to_bytes();
    let mut result = ProjectivePoint::IDENTITY;
    for bit in (0..secret_table::ROWS).rev() {
        result = result.double();
        for (chunk, table) in tables.iter().enumerate() {
            let mut digit = 0u8;
            for column in 0..4 {
                let position = bit + secret_table::ROWS * chunk + 64 * column;
                digit |= ((bytes[31 - position / 8] >> (position & 7)) & 1) << column;
            }
            let mut selected = AffinePoint::IDENTITY;
            for i in 1..16 {
                selected.conditional_assign(&table[i], digit.ct_eq(&(i as u8)));
            }
            result += selected;
        }
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
    let public_key = table(q);
    let left = nonadjacent(u1);
    let right = nonadjacent(u2);
    let mut result = ProjectivePoint::IDENTITY;
    for bit in (0..257).rev() {
        result = result.double();
        let a = left[bit];
        let b = right[bit];
        if a > 0 {
            result += point_from_words(&prepared_table::ODD_GENERATOR[a as usize / 2]);
        } else if a < 0 {
            result -= point_from_words(&prepared_table::ODD_GENERATOR[(-a) as usize / 2]);
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
    let point = verification_lincomb(&u1, &ProjectivePoint::from(*key.as_affine()), &u2);
    Ok(projective_x_matches_scalar(&point, &r))
}

// primeorder uses homogeneous coordinates: affine x = X/Z, not X/Z².
// Since n < p < 2n, x mod n == r iff x == r or x == r+n < p.
// Compare after multiplying by Z, avoiding a field inverse. All branches
// depend only on public verification inputs. Signature parsing establishes r>0.
fn projective_x_matches_scalar(point: &ProjectivePoint, r: &p256::NonZeroScalar) -> bool {
    let (x, _, z) = point.to_field_coordinates();
    if bool::from(z.is_zero()) {
        return false;
    }
    let bytes = r.to_repr();
    // A validated scalar is below n, hence below the base-field modulus p.
    let first = FieldElement::from_bytes(&bytes).unwrap();
    if x == first * z {
        return true;
    }
    // Both checks are essential: wrapping at 2^256 or reducing modulo p
    // would admit false signatures. Canonical field decoding enforces r+n<p.
    let Some(sum) = Option::<U256>::from(U256::from_be_slice(&bytes).checked_add(&NistP256::ORDER)) else {
        return false;
    };
    let Some(second) = Option::<FieldElement>::from(FieldElement::from_bytes(&sum.encode_field_bytes())) else {
        return false;
    };
    x == second * z
}

// The point encoding is private to the nominal PreparedPublicKey type: eight
// initialized little-endian u64 limbs, x then y, in canonical Montgomery form.
// It contains no Rust layout, padding, pointers, identity marker or global state.
fn point_words(point: &AffinePoint) -> [u64; 8] {
    let (x, y) = point.to_field_coordinates();
    let mut words = [0u64; 8];
    words[..4].copy_from_slice(&x.to_montgomery_words());
    words[4..].copy_from_slice(&y.to_montgomery_words());
    words
}

fn point_from_words(words: &[u64; 8]) -> AffinePoint {
    let x = FieldElement::from_montgomery_words_unchecked(words[..4].try_into().unwrap());
    let y = FieldElement::from_montgomery_words_unchecked(words[4..].try_into().unwrap());
    AffinePoint::from_field_coordinates_unchecked(x, y)
}

fn prepared_point(bytes: &[u8], index: usize) -> AffinePoint {
    let mut words = [0u64; 8];
    let encoded = &bytes[index * 64..(index + 1) * 64];
    for (word, chunk) in words.iter_mut().zip(encoded.chunks_exact(8)) {
        *word = u64::from_le_bytes(chunk.try_into().unwrap());
    }
    point_from_words(&words)
}

fn prepare_public_key(key: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    let key = public(key)?;
    let mut basis = [ProjectivePoint::IDENTITY; prepared_table::WIDTH];
    basis[0] = ProjectivePoint::from(*key.as_affine());
    for column in 1..prepared_table::WIDTH {
        let mut point = basis[column - 1];
        for _ in 0..prepared_table::ROWS {
            point = point.double();
        }
        basis[column] = point;
    }
    let mut table = [ProjectivePoint::IDENTITY; prepared_table::POINTS];
    for digit in 1usize..=prepared_table::POINTS {
        let column = digit.trailing_zeros() as usize;
        let remainder = digit & (digit - 1);
        table[digit - 1] = if remainder == 0 {
            basis[column]
        } else {
            table[remainder - 1] + basis[column]
        };
    }
    // A nonzero Q of prime order multiplied by these nonzero coefficients
    // (all below n) cannot be the identity. Normalize together with one inverse.
    let affine = ProjectivePoint::batch_normalize(&table);
    for (encoded, point) in output.chunks_exact_mut(64).zip(affine.iter()) {
        for (chunk, word) in encoded.chunks_exact_mut(8).zip(point_words(point)) {
            chunk.copy_from_slice(&word.to_le_bytes());
        }
    }
    Ok(prepared_table::BYTES)
}

// Only public verification scalars determine table indices and zero branches.
fn verification_prepared(u1: &Scalar, key: &[u8], u2: &Scalar) -> ProjectivePoint {
    let left = u1.to_bytes();
    let right = u2.to_bytes();
    let mut result = ProjectivePoint::IDENTITY;
    for bit in (0..prepared_table::ROWS).rev() {
        result = result.double();
        let mut a = 0usize;
        let mut b = 0usize;
        for column in 0..prepared_table::WIDTH {
            let position = bit + prepared_table::ROWS * column;
            if position < 256 {
                a |= (((left[31 - position / 8] >> (position & 7)) & 1) as usize) << column;
                b |= (((right[31 - position / 8] >> (position & 7)) & 1) as usize) << column;
            }
        }
        if a != 0 {
            result += point_from_words(&prepared_table::GENERATOR[a - 1]);
        }
        if b != 0 {
            result += prepared_point(key, b - 1);
        }
    }
    result
}

fn verify_prehash_prepared(key: &[u8], hash: &[u8], sig: &[u8]) -> Result<bool, i64> {
    // The SDK type and matching preparation function establish key validity.
    // Neither arbitrary Blob bytes nor another plugin's prepared type can enter.
    digest(hash)?;
    let sig = signature(sig)?;
    let z = <Scalar as Reduce<U256>>::reduce_bytes(hash.into());
    let (r, s) = sig.split_scalars();
    let inverse = *s.invert_vartime();
    let point = verification_prepared(&(z * inverse), key, &(*r * inverse));
    Ok(projective_x_matches_scalar(&point, &r))
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

/// # Safety
/// key points to key_len readable bytes. out points to prepared_table::BYTES
/// writable bytes disjoint from key; all buffers remain live for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn p256_prepare_public_key(
    key: *const u8,
    key_len: usize,
    out: *mut u8,
) -> i64 {
    status(prepare_public_key(unsafe { input(key, key_len) }, unsafe {
        output(out, prepared_table::BYTES)
    }))
}

/// # Safety
/// key must point to the immutable prepared_table::BYTES-byte output of this
/// exact build's successful preparation, protected by the SDK nominal type.
/// Other inputs point to readable buffers; all remain live for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn p256_verify_prehash_prepared(
    key: *const u8,
    hash: *const u8,
    hash_len: usize,
    sig: *const u8,
    sig_len: usize,
) -> i64 {
    match verify_prehash_prepared(
        unsafe { input(key, prepared_table::BYTES) },
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
            let mut prepared = [0u8; prepared_table::BYTES];
            let prepared_valid = prepare_public_key(&key, &mut prepared).is_ok();
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
                let valid_prepared = prepared_valid
                    && signature_from_der(&der, &mut compact).is_ok()
                    && verify_prehash_prepared(&prepared, &hash, &compact) == Ok(true);
                assert_eq!(valid_prepared, valid, "prepared tcId {}", vector["tcId"]);
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
    fn scalar_inversion_matches_binary_exponent() {
        use sha2::{Digest, Sha256};
        // The unchanged binary exponentiation is independent of the optimized
        // fixed addition chain. Include zero's CtOption behavior explicitly.
        let exponent = [
            0xf3b9_cac2_fc63_254f,
            0xbce6_faad_a717_9e84,
            0xffff_ffff_ffff_ffff,
            0xffff_ffff_0000_0000,
        ];
        let mut values = vec![Scalar::ZERO, Scalar::ONE, Scalar::from(2u64), -Scalar::ONE];
        for bit in 0..256 {
            let mut bytes = [0u8; 32];
            bytes[31 - bit / 8] = 1 << (bit & 7);
            values.push(Scalar::from_repr(bytes.into()).unwrap());
        }
        for i in 0u32..512 {
            values.push(<Scalar as Reduce<U256>>::reduce_bytes(&Sha256::digest(
                i.to_be_bytes(),
            )));
        }
        for scalar in values {
            assert_eq!(scalar.square(), scalar.multiply(&scalar));
            let inverse = scalar.invert();
            assert_eq!(bool::from(inverse.is_some()), scalar != Scalar::ZERO);
            assert_eq!(inverse.unwrap_or(Scalar::ZERO), scalar.pow_vartime(&exponent));
            if scalar != Scalar::ZERO {
                assert_eq!(scalar * inverse.unwrap(), Scalar::ONE);
            }
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
    fn prepared_table_codec_and_lincomb_match_upstream() {
        let keys = [
            ProjectivePoint::GENERATOR,
            -ProjectivePoint::GENERATOR,
            ProjectivePoint::from(*public(&hex(PUBLIC)).unwrap().as_affine()),
        ];
        let scalars = [
            Scalar::ZERO,
            Scalar::ONE,
            Scalar::from(2u64),
            -Scalar::ONE,
            Scalar::from_repr({
                let mut bytes = [0u8; 32];
                bytes[0] = 0x80;
                bytes.into()
            })
            .unwrap(),
            <Scalar as Reduce<U256>>::reduce_bytes(
                hex("fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210")
                    .as_slice()
                    .into(),
            ),
        ];
        for (index, words) in prepared_table::ODD_GENERATOR.iter().enumerate() {
            assert_eq!(
                point_from_words(words),
                (ProjectivePoint::GENERATOR * Scalar::from((2 * index + 1) as u64)).to_affine()
            );
        }
        for key in keys {
            let mut prepared = [0u8; prepared_table::BYTES];
            let encoded = key.to_affine().to_encoded_point(true);
            assert_eq!(
                prepare_public_key(encoded.as_bytes(), &mut prepared),
                Ok(prepared.len())
            );
            for digit in 1..=prepared_table::POINTS {
                let mut bytes = [0u8; 32];
                for column in 0..prepared_table::WIDTH {
                    if digit >> column & 1 != 0 {
                        let bit = prepared_table::ROWS * column;
                        bytes[31 - bit / 8] |= 1 << (bit & 7);
                    }
                }
                let coefficient = Scalar::from_repr(bytes.into()).unwrap();
                assert_eq!(
                    prepared_point(&prepared, digit - 1),
                    (key * coefficient).to_affine()
                );
                assert_eq!(
                    point_from_words(&prepared_table::GENERATOR[digit - 1]),
                    (ProjectivePoint::GENERATOR * coefficient).to_affine()
                );
            }
            for a in scalars {
                for b in scalars {
                    assert_eq!(
                        verification_prepared(&a, &prepared, &b),
                        ProjectivePoint::GENERATOR * a + key * b
                    );
                }
            }
        }
    }

    #[test]
    fn prepared_pointer_contract_errors_and_immutability() {
        let key = hex(PUBLIC);
        let hash = hex(HASH);
        let sig = hex(SIGNATURE);
        let mut output = vec![0xa5; prepared_table::BYTES + 2];
        assert_eq!(
            unsafe { p256_prepare_public_key(key.as_ptr(), key.len(), output.as_mut_ptr().add(1)) },
            prepared_table::BYTES as i64
        );
        assert_eq!(output[0], 0xa5);
        assert_eq!(output[prepared_table::BYTES + 1], 0xa5);
        let saved = output.clone();
        for _ in 0..8 {
            assert_eq!(
                unsafe {
                    p256_verify_prehash_prepared(
                        output.as_ptr().add(1),
                        hash.as_ptr(),
                        hash.len(),
                        sig.as_ptr(),
                        sig.len(),
                    )
                },
                1
            );
        }
        assert_eq!(
            unsafe {
                p256_verify_prehash_prepared(
                    output.as_ptr().add(1),
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0,
                )
            },
            INVALID_DIGEST
        );
        assert_eq!(
            unsafe {
                p256_verify_prehash_prepared(
                    output.as_ptr().add(1),
                    hash.as_ptr(),
                    hash.len(),
                    core::ptr::null(),
                    0,
                )
            },
            INVALID_SIGNATURE
        );
        assert_eq!(output, saved);
        for key in [vec![], vec![0], vec![4; 65], vec![255; 33], vec![6; 65]] {
            output.fill(0xa5);
            assert_eq!(
                unsafe {
                    p256_prepare_public_key(key.as_ptr(), key.len(), output.as_mut_ptr().add(1))
                },
                INVALID_PUBLIC_KEY
            );
            assert!(output[1..=prepared_table::BYTES].iter().all(|b| *b == 0));
            assert_eq!(output[0], 0xa5);
            assert_eq!(output[prepared_table::BYTES + 1], 0xa5);
        }
    }

    #[test]
    fn comb_matches_upstream() {
        use sha2::{Digest, Sha256};
        for (chunk, table) in secret_table::POINTS.iter().enumerate() {
            for (index, words) in table.iter().enumerate() {
                let digit = index + 1;
                let mut bytes = [0u8; 32];
                for column in 0..4 {
                    if digit >> column & 1 != 0 {
                        let bit = secret_table::ROWS * chunk + 64 * column;
                        bytes[31 - bit / 8] |= 1 << (bit & 7);
                    }
                }
                let coefficient = Scalar::from_repr(bytes.into()).unwrap();
                assert_eq!(
                    point_from_words(words),
                    (ProjectivePoint::GENERATOR * coefficient).to_affine()
                );
            }
        }
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
