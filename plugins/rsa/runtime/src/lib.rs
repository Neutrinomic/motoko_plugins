//! Fixed RSA-3072/e65537 PSS-SHA256 adapter to the pinned BearSSL i31 kernel.
//! All outputs are managed caller storage; scratch is bounded stack storage.
#![cfg_attr(not(test), no_std)]
unsafe extern "C" {
    fn rsa_impl_public_key(key: *const u8, len: usize, out: *mut u8) -> i64;
    fn rsa_impl_validate_private_key(key: *const u8, len: usize) -> i64;
    fn rsa_impl_validate_public_key(key: *const u8, len: usize) -> i64;
    fn rsa_impl_sign(key: *const u8, key_len: usize, message: *const u8, message_len: usize,
        salt: *const u8, salt_len: usize, out: *mut u8, prehash: u32) -> i64;
    fn rsa_impl_verify(key: *const u8, key_len: usize, message: *const u8, message_len: usize,
        signature: *const u8, signature_len: usize, prehash: u32) -> i64;
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rsa_public_key(key: *const u8, len: usize, out: *mut u8) -> i64 {
    unsafe { rsa_impl_public_key(key, len, out) }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rsa_validate_private_key(key: *const u8, len: usize) -> i64 {
    unsafe { rsa_impl_validate_private_key(key, len) }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rsa_validate_public_key(key: *const u8, len: usize) -> i64 {
    unsafe { rsa_impl_validate_public_key(key, len) }
}
macro_rules! signing {
    ($name:ident, $prehash:expr) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(key: *const u8, kl: usize, msg: *const u8, ml: usize,
            salt: *const u8, sl: usize, out: *mut u8) -> i64 {
            unsafe { rsa_impl_sign(key, kl, msg, ml, salt, sl, out, $prehash) }
        }
    };
}
macro_rules! verifying {
    ($name:ident, $prehash:expr) => {
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn $name(key: *const u8, kl: usize, msg: *const u8, ml: usize,
            sig: *const u8, sl: usize) -> i64 {
            unsafe { rsa_impl_verify(key, kl, msg, ml, sig, sl, $prehash) }
        }
    };
}
signing!(rsa_sign, 0);
signing!(rsa_sign_prehash, 1);
verifying!(rsa_verify, 0);
verifying!(rsa_verify_prehash, 1);
#[cfg(not(test))]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    unsafe extern "C" { fn compute_plugin_trap(ptr: *const u8, len: usize) -> !; }
    let message = b"RSA plugin invariant failure";
    unsafe { compute_plugin_trap(message.as_ptr(), message.len()) }
}
#[cfg(test)]
mod tests;
