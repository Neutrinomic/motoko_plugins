//! Pure Ed25519: caller-owned seed, deterministic signing and strict verification.
//! Stack-only dalek arithmetic; no allocator, RNG, retained state or input writes.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

use curve25519_dalek::{
    edwards::{CompressedEdwardsY, EdwardsPoint, PreparedVartimeEdwardsTable},
    scalar::Scalar,
};
use ed25519_dalek::{
    Signer, SigningKey, VerifyingKey, hazmat::ExpandedSecretKey,
};
use sha2::{Digest, Sha512};
use zeroize::Zeroizing;

const INVALID_SECRET_KEY: i64 = -1;
const INVALID_PUBLIC_KEY: i64 = -2;
const INVALID_SIGNATURE: i64 = -3;

fn secret(input: &[u8]) -> Result<SigningKey, i64> {
    let seed: &[u8; 32] = input.try_into().map_err(|_| INVALID_SECRET_KEY)?;
    // SigningKey and its expanded secret zeroize on drop (feature enabled).
    Ok(SigningKey::from_bytes(seed))
}

// Dalek decoding accepts reduced field encodings (ZIP-215). This API requires
// the RFC8032 canonical y < 2^255-19 encoding. All x=0 points have small order,
// so the small-order rejection below also excludes the invalid x=0 sign bit.
fn canonical_y(bytes: &[u8; 32]) -> bool {
    let mut modulus = [0xff; 32];
    modulus[0] = 0xed;
    modulus[31] = 0x7f;
    for i in (0..32).rev() {
        let byte = if i == 31 { bytes[i] & 0x7f } else { bytes[i] };
        if byte != modulus[i] {
            return byte < modulus[i];
        }
    }
    false
}

fn public(input: &[u8]) -> Result<VerifyingKey, i64> {
    let bytes: &[u8; 32] = input.try_into().map_err(|_| INVALID_PUBLIC_KEY)?;
    if !canonical_y(bytes) {
        return Err(INVALID_PUBLIC_KEY);
    }
    let key = VerifyingKey::from_bytes(bytes).map_err(|_| INVALID_PUBLIC_KEY)?;
    if key.is_weak() {
        return Err(INVALID_PUBLIC_KEY);
    }
    Ok(key)
}

struct CheckedSignature {
    r_bytes: [u8; 32],
    r_point: EdwardsPoint,
    s: Scalar,
}

fn signature(input: &[u8]) -> Result<CheckedSignature, i64> {
    let bytes: &[u8; 64] = input.try_into().map_err(|_| INVALID_SIGNATURE)?;
    let mut r = [0; 32];
    r.copy_from_slice(&bytes[..32]);
    if !canonical_y(&r) {
        return Err(INVALID_SIGNATURE);
    }
    let point = CompressedEdwardsY(r)
        .decompress()
        .ok_or(INVALID_SIGNATURE)?;
    if point.is_small_order() {
        return Err(INVALID_SIGNATURE);
    }
    let mut s = [0; 32];
    s.copy_from_slice(&bytes[32..]);
    let s = Option::<Scalar>::from(Scalar::from_canonical_bytes(s))
        .ok_or(INVALID_SIGNATURE)?;
    Ok(CheckedSignature { r_bytes: r, r_point: point, s })
}

fn challenge(r: &[u8; 32], key: &[u8], message: &[u8]) -> Scalar {
    let mut hash = Sha512::new();
    hash.update(r);
    hash.update(key);
    hash.update(message);
    Scalar::from_bytes_mod_order_wide(&hash.finalize().into())
}

fn public_key(seed: &[u8], output: &mut [u8; 32]) -> Result<(), i64> {
    *output = secret(seed)?.verifying_key().to_bytes();
    Ok(())
}

fn sign(seed: &[u8], message: &[u8], output: &mut [u8; 64]) -> Result<(), i64> {
    *output = secret(seed)?.sign(message).to_bytes();
    Ok(())
}

fn verify(key: &[u8], message: &[u8], sig: &[u8]) -> Result<bool, i64> {
    let key = public(key)?;
    let sig = signature(sig)?;
    let k = challenge(&sig.r_bytes, key.as_bytes(), message);
    let expected_r = EdwardsPoint::vartime_double_scalar_mul_basepoint(
        &k, &(-key.to_edwards()), &sig.s,
    );
    // Canonical R has one encoding. Compare its already validated point using
    // upstream projective equality, avoiding a final field inversion. This is
    // the same uncofactored equation, including for mixed-order A and R.
    Ok(expected_r == sig.r_point)
}

// Prepared payloads are immutable SDK-protected managed Blobs. Their explicit
// encodings contain no pointers, padding, or platform-dependent Rust layouts.
const PREPARED_PUBLIC_BYTES: usize = 1056;
const PREPARED_SECRET_BYTES: usize = 96;

fn prepare_public_key(key: &[u8], output: &mut [u8; PREPARED_PUBLIC_BYTES]) -> Result<(), i64> {
    let key = public(key)?;
    let table = PreparedVartimeEdwardsTable::from_point(&(-key.to_edwards()));
    output[..32].copy_from_slice(key.as_bytes());
    output[32..].copy_from_slice(&table.to_bytes());
    Ok(())
}

fn prepare_secret_key(seed: &[u8], output: &mut [u8; PREPARED_SECRET_BYTES]) -> Result<(), i64> {
    let seed: &[u8; 32] = seed.try_into().map_err(|_| INVALID_SECRET_KEY)?;
    let digest = Zeroizing::new(<[u8; 64]>::from(Sha512::digest(seed)));
    let expanded = ExpandedSecretKey::from_bytes(&digest);
    let key = VerifyingKey::from(&expanded);
    output[..32].copy_from_slice(expanded.scalar.as_bytes());
    output[32..64].copy_from_slice(&expanded.hash_prefix);
    output[64..].copy_from_slice(key.as_bytes());
    Ok(())
}

fn sign_prepared(key: &[u8; PREPARED_SECRET_BYTES], message: &[u8], output: &mut [u8; 64]) {
    // The nominal type proves factory origin, immutable bytes, and exact size.
    // Stored scalar bytes are already reduced; never clamp them again.
    let mut scalar = Zeroizing::new([0; 32]);
    scalar.copy_from_slice(&key[..32]);
    let mut expanded = ExpandedSecretKey {
        scalar: Scalar::from_bytes_mod_order(*scalar),
        hash_prefix: [0; 32],
    };
    expanded.hash_prefix.copy_from_slice(&key[32..64]);
    let public_bytes: &[u8; 32] = key[64..].try_into().unwrap();
    *output = expanded
        .sign_prepared::<Sha512>(message, public_bytes)
        .to_bytes();
}

fn verify_prepared(
    key: &[u8; PREPARED_PUBLIC_BYTES],
    message: &[u8],
    sig: &[u8],
) -> Result<bool, i64> {
    let sig = signature(sig)?;
    let k = challenge(&sig.r_bytes, &key[..32], message);
    let table = PreparedVartimeEdwardsTable::from_trusted_bytes(key[32..].try_into().unwrap());
    // Cache -A, not a negated scalar modulo L: those differ for mixed-order A.
    let expected_r = table.vartime_double_scalar_mul_basepoint(&k, &sig.s);
    Ok(expected_r == sig.r_point)
}

unsafe fn input<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if len == 0 {
        &[]
    } else {
        unsafe { core::slice::from_raw_parts(ptr, len) }
    }
}

/// # Safety
/// Input is readable for len bytes; out is a disjoint writable 32-byte buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ed25519_public_key(ptr: *const u8, len: usize, out: *mut u8) -> i64 {
    match public_key(unsafe { input(ptr, len) }, unsafe {
        &mut *out.cast::<[u8; 32]>()
    }) {
        Ok(()) => 0,
        Err(error) => error,
    }
}

/// # Safety
/// Input is readable for len bytes and remains live for this synchronous call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ed25519_validate_public_key(ptr: *const u8, len: usize) -> i64 {
    match public(unsafe { input(ptr, len) }) {
        Ok(_) => 1,
        Err(error) => error,
    }
}

/// # Safety
/// Inputs are readable for their lengths; out is a disjoint writable 64-byte buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ed25519_sign(
    seed: *const u8,
    seed_len: usize,
    message: *const u8,
    message_len: usize,
    out: *mut u8,
) -> i64 {
    match sign(
        unsafe { input(seed, seed_len) },
        unsafe { input(message, message_len) },
        unsafe { &mut *out.cast::<[u8; 64]>() },
    ) {
        Ok(()) => 0,
        Err(error) => error,
    }
}

/// # Safety
/// All inputs are readable for their lengths and remain live for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ed25519_verify(
    key: *const u8,
    key_len: usize,
    message: *const u8,
    message_len: usize,
    sig: *const u8,
    sig_len: usize,
) -> i64 {
    match verify(
        unsafe { input(key, key_len) },
        unsafe { input(message, message_len) },
        unsafe { input(sig, sig_len) },
    ) {
        Ok(valid) => i64::from(valid),
        Err(error) => error,
    }
}

/// # Safety
/// Input is readable for len bytes; out is disjoint and writable for 1056 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ed25519_prepare_public_key(
    ptr: *const u8,
    len: usize,
    out: *mut u8,
) -> i64 {
    match prepare_public_key(unsafe { input(ptr, len) }, unsafe {
        &mut *out.cast::<[u8; PREPARED_PUBLIC_BYTES]>()
    }) {
        Ok(()) => 0,
        Err(error) => error,
    }
}

/// # Safety
/// Input is readable for len bytes; out is disjoint and writable for 96 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ed25519_prepare_secret_key(
    ptr: *const u8,
    len: usize,
    out: *mut u8,
) -> i64 {
    match prepare_secret_key(unsafe { input(ptr, len) }, unsafe {
        &mut *out.cast::<[u8; PREPARED_SECRET_BYTES]>()
    }) {
        Ok(()) => 0,
        Err(error) => error,
    }
}

/// # Safety
/// key points to an intact 96-byte result of ed25519_prepare_secret_key.
/// Message is readable for message_len bytes; out is a disjoint 64-byte buffer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ed25519_sign_prepared(
    key: *const u8,
    message: *const u8,
    message_len: usize,
    out: *mut u8,
) {
    sign_prepared(
        unsafe { &*key.cast::<[u8; PREPARED_SECRET_BYTES]>() },
        unsafe { input(message, message_len) },
        unsafe { &mut *out.cast::<[u8; 64]>() },
    )
}

/// # Safety
/// key points to an intact 1056-byte result of ed25519_prepare_public_key.
/// Other inputs are readable for their lengths and remain live for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ed25519_verify_prepared(
    key: *const u8,
    message: *const u8,
    message_len: usize,
    sig: *const u8,
    sig_len: usize,
) -> i64 {
    match verify_prepared(
        unsafe { &*key.cast::<[u8; PREPARED_PUBLIC_BYTES]>() },
        unsafe { input(message, message_len) },
        unsafe { input(sig, sig_len) },
    ) {
        Ok(valid) => i64::from(valid),
        Err(error) => error,
    }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests;
