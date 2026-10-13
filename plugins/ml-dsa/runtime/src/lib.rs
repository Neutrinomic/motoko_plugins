//! FIPS 204 ML-DSA-44 using the pinned, allocation-free fips204 implementation.
//! A secret key is its 32-byte seed: expanded secret-key encodings cannot enter
//! the API. All scratch is bounded stack storage, and no input pointer escapes.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

use fips204::ml_dsa_44::{KG, PK_LEN, SIG_LEN, PublicKey};
use fips204::traits::{KeyGen, SerDes, Verifier};
use fips204::motoko_prepared::{self as prepared, PUBLIC_LEN, SECRET_LEN};

const INVALID_SECRET_KEY: i64 = -1;
const INVALID_PUBLIC_KEY: i64 = -2;
const INVALID_SIGNATURE: i64 = -3;
const INVALID_CONTEXT: i64 = -4;
const INVALID_RANDOMNESS: i64 = -5;

fn seed(bytes: &[u8]) -> Result<&[u8; 32], i64> {
    bytes.try_into().map_err(|_| INVALID_SECRET_KEY)
}

fn context(bytes: &[u8]) -> Result<(), i64> {
    if bytes.len() <= 255 { Ok(()) } else { Err(INVALID_CONTEXT) }
}

fn public_key(secret: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    let (public, _secret) = KG::keygen_from_seed(seed(secret)?);
    output[..PK_LEN].copy_from_slice(&public.into_bytes());
    Ok(PK_LEN)
}

fn sign(secret: &[u8], message: &[u8], ctx: &[u8], randomness: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    let seed = seed(secret)?;
    context(ctx)?;
    let randomness = randomness.try_into().map_err(|_| INVALID_RANDOMNESS)?;
    // Keep key generation's matrix only for this call, avoiding a second
    // expansion. No managed cache or hidden RNG is involved.
    let signature = prepared::sign_from_seed(seed, message, ctx, randomness);
    output[..SIG_LEN].copy_from_slice(&signature);
    Ok(SIG_LEN)
}

fn verify(public: &[u8], message: &[u8], signature: &[u8], ctx: &[u8]) -> Result<bool, i64> {
    let public: &[u8; PK_LEN] = public.try_into().map_err(|_| INVALID_PUBLIC_KEY)?;
    let signature: &[u8; SIG_LEN] = signature.try_into().map_err(|_| INVALID_SIGNATURE)?;
    context(ctx)?;
    // Every length-correct public key is a canonical rho || packed-t1 value.
    let public = PublicKey::try_from_bytes(*public).map_err(|_| INVALID_PUBLIC_KEY)?;
    Ok(public.verify(message, signature, ctx))
}

fn prepare_public_key(public: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    let public = public.try_into().map_err(|_| INVALID_PUBLIC_KEY)?;
    prepared::prepare_public(public, output.try_into().expect("fixed prepared public output"))
        .map_err(|_| INVALID_PUBLIC_KEY)?;
    Ok(PUBLIC_LEN)
}

fn prepare_secret_key(secret: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    prepared::prepare_secret(seed(secret)?, output.try_into().expect("fixed prepared secret output"));
    Ok(SECRET_LEN)
}

fn sign_prepared(secret: &[u8; SECRET_LEN], message: &[u8], ctx: &[u8], randomness: &[u8], output: &mut [u8]) -> Result<usize, i64> {
    context(ctx)?;
    let randomness = randomness.try_into().map_err(|_| INVALID_RANDOMNESS)?;
    output[..SIG_LEN].copy_from_slice(&prepared::sign(secret, message, ctx, randomness));
    Ok(SIG_LEN)
}

fn verify_prepared(public: &[u8; PUBLIC_LEN], message: &[u8], signature: &[u8], ctx: &[u8]) -> Result<bool, i64> {
    let signature = signature.try_into().map_err(|_| INVALID_SIGNATURE)?;
    context(ctx)?;
    Ok(prepared::verify(public, message, signature, ctx))
}

unsafe fn input<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if len == 0 { &[] } else { unsafe { core::slice::from_raw_parts(ptr, len) } }
}
unsafe fn output<'a>(ptr: *mut u8, len: usize) -> &'a mut [u8] {
    // Managed Blob allocation is uninitialized. Initialize it even on errors.
    unsafe { core::ptr::write_bytes(ptr, 0, len) };
    unsafe { core::slice::from_raw_parts_mut(ptr, len) }
}
fn status(result: Result<usize, i64>) -> i64 {
    match result { Ok(length) => length as i64, Err(error) => error }
}

/// # Safety
/// Inputs are live readable buffers; out is a writable 1312-byte managed Blob
/// payload disjoint from all inputs. No GC safepoint occurs during the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_public_key(ptr: *const u8, len: usize, out: *mut u8) -> i64 {
    status(public_key(unsafe { input(ptr, len) }, unsafe { output(out, PK_LEN) }))
}

/// # Safety
/// Inputs are live readable buffers; out is a writable 2420-byte managed Blob
/// payload disjoint from all inputs. No GC safepoint occurs during the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_sign(
    secret: *const u8, secret_len: usize,
    message: *const u8, message_len: usize,
    ctx: *const u8, ctx_len: usize, out: *mut u8,
) -> i64 {
    status(sign(unsafe { input(secret, secret_len) }, unsafe { input(message, message_len) },
        unsafe { input(ctx, ctx_len) }, &[0; 32], unsafe { output(out, SIG_LEN) }))
}

/// # Safety
/// Inputs are live readable buffers; out is a writable 2420-byte managed Blob
/// payload disjoint from all inputs. No GC safepoint occurs during the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_sign_randomized(
    secret: *const u8, secret_len: usize,
    message: *const u8, message_len: usize,
    ctx: *const u8, ctx_len: usize,
    randomness: *const u8, randomness_len: usize, out: *mut u8,
) -> i64 {
    status(sign(unsafe { input(secret, secret_len) }, unsafe { input(message, message_len) },
        unsafe { input(ctx, ctx_len) }, unsafe { input(randomness, randomness_len) },
        unsafe { output(out, SIG_LEN) }))
}

/// # Safety
/// Inputs are live readable buffers for the stated lengths. No GC safepoint
/// occurs during the call. Returns 0/1 for a valid call or a negative error.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_verify(
    public: *const u8, public_len: usize,
    message: *const u8, message_len: usize,
    signature: *const u8, signature_len: usize,
    ctx: *const u8, ctx_len: usize,
) -> i64 {
    match verify(unsafe { input(public, public_len) }, unsafe { input(message, message_len) },
        unsafe { input(signature, signature_len) }, unsafe { input(ctx, ctx_len) }) {
        Ok(value) => i64::from(value), Err(error) => error,
    }
}

/// # Safety
/// Input is readable; out is a disjoint writable PUBLIC_LEN-byte Blob payload.
/// The compiler publishes it as a protected public handle only on success.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_prepare_public_key(public: *const u8, public_len: usize, out: *mut u8) -> i64 {
    status(prepare_public_key(unsafe { input(public, public_len) }, unsafe { output(out, PUBLIC_LEN) }))
}

/// # Safety
/// Input is readable; out is a disjoint writable SECRET_LEN-byte Blob payload.
/// The compiler publishes it as a protected secret handle only on success.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_prepare_secret_key(secret: *const u8, secret_len: usize, out: *mut u8) -> i64 {
    status(prepare_secret_key(unsafe { input(secret, secret_len) }, unsafe { output(out, SECRET_LEN) }))
}

/// # Safety
/// secret is the immutable SECRET_LEN-byte payload of this plugin's protected
/// secret handle; other inputs are readable and out is disjoint writable SIG_LEN
/// bytes. No GC or callback occurs while any pointer is borrowed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_sign_prepared(
    secret: *const u8, message: *const u8, message_len: usize,
    ctx: *const u8, ctx_len: usize, out: *mut u8,
) -> i64 {
    let secret = unsafe { &*secret.cast::<[u8; SECRET_LEN]>() };
    status(sign_prepared(secret, unsafe { input(message, message_len) },
        unsafe { input(ctx, ctx_len) }, &[0; 32], unsafe { output(out, SIG_LEN) }))
}

/// # Safety
/// Same protected secret and disjoint output requirements as mldsa_sign_prepared;
/// randomness is readable for its stated length. No GC safepoint occurs.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_sign_randomized_prepared(
    secret: *const u8, message: *const u8, message_len: usize,
    ctx: *const u8, ctx_len: usize,
    randomness: *const u8, randomness_len: usize, out: *mut u8,
) -> i64 {
    let secret = unsafe { &*secret.cast::<[u8; SECRET_LEN]>() };
    status(sign_prepared(secret, unsafe { input(message, message_len) },
        unsafe { input(ctx, ctx_len) }, unsafe { input(randomness, randomness_len) },
        unsafe { output(out, SIG_LEN) }))
}

/// # Safety
/// public is the immutable PUBLIC_LEN-byte payload of this plugin's protected
/// public handle. All other inputs are readable; no GC safepoint occurs.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mldsa_verify_prepared(
    public: *const u8, message: *const u8, message_len: usize,
    signature: *const u8, signature_len: usize, ctx: *const u8, ctx_len: usize,
) -> i64 {
    let public = unsafe { &*public.cast::<[u8; PUBLIC_LEN]>() };
    match verify_prepared(public, unsafe { input(message, message_len) },
        unsafe { input(signature, signature_len) }, unsafe { input(ctx, ctx_len) }) {
        Ok(value) => i64::from(value), Err(error) => error,
    }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests;
