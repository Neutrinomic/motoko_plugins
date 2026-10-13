//! Pure Ed25519: caller-owned seed, deterministic signing and strict verification.
//! Stack-only dalek arithmetic; no allocator, RNG, retained state or input writes.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

use curve25519_dalek::{edwards::CompressedEdwardsY, scalar::Scalar};
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};

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

fn signature(input: &[u8]) -> Result<Signature, i64> {
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
    if !bool::from(Scalar::from_canonical_bytes(s).is_some()) {
        return Err(INVALID_SIGNATURE);
    }
    Ok(Signature::from_bytes(bytes))
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
    // The checks above implement verify_strict's small-order and scalar rules
    // plus canonical A/R encodings. Calling verify here avoids decompressing R
    // twice while retaining the same uncofactored equation, not ZIP-215 rules.
    Ok(key.verify(message, &sig).is_ok())
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

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests;
