//! Native ABI regressions: exact output capacities, byte alignment and borrowing.

use super::*;

const SENTINEL: u8 = 0xa5;
const SECRET: &str = "c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721";
const PUBLIC: &str = "0360fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb6";
const UNCOMPRESSED: &str = "0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299";
const HASH: &str = "af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf";
const SIGNATURE: &str = "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8";
const LOW_SIGNATURE: &str = "efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf37160834e36ad29a83bf2bc9385e491d6099c8fdf9d1ed67aa7ea5f51f93782857a9";
const DER: &str = "3046022100efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716022100f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8";

fn hex(value: &str) -> Vec<u8> {
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(core::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}

struct Buffer {
    storage: Vec<u8>,
    offset: usize,
    length: usize,
}

impl Buffer {
    fn new(bytes: &[u8], offset: usize) -> Self {
        let mut storage = vec![SENTINEL; offset + bytes.len() + 8];
        storage[offset..offset + bytes.len()].copy_from_slice(bytes);
        Self {
            storage,
            offset,
            length: bytes.len(),
        }
    }

    fn ptr(&self) -> *const u8 {
        self.storage[self.offset..].as_ptr()
    }

    fn mut_ptr(&mut self) -> *mut u8 {
        self.storage[self.offset..].as_mut_ptr()
    }

    fn bytes(&self) -> &[u8] {
        &self.storage[self.offset..self.offset + self.length]
    }

    fn check_guards(&self) {
        assert!(self.storage[..self.offset].iter().all(|b| *b == SENTINEL));
        assert!(
            self.storage[self.offset + self.length..]
                .iter()
                .all(|b| *b == SENTINEL)
        );
    }
}

fn output_call(
    capacity: usize,
    offset: usize,
    expected_status: i64,
    call: impl FnOnce(*mut u8) -> i64,
) -> Buffer {
    let mut output = Buffer::new(&vec![SENTINEL; capacity], offset);
    assert_eq!(call(output.mut_ptr()), expected_status);
    output.check_guards();
    output
}

fn error_call(
    capacity: usize,
    offset: usize,
    expected_status: i64,
    call: impl FnOnce(*mut u8) -> i64,
) {
    let output = output_call(capacity, offset, expected_status, call);
    assert!(output.bytes().iter().all(|b| *b == 0));
}

#[test]
fn every_output_export_zeroes_failed_calls_with_exact_capacity() {
    // Null is permitted only for zero-length input; output is always writable,
    // including when validation will fail. Deliberately avoid output aliases.
    for offset in 1..=8 {
        let secret = Buffer::new(&hex(SECRET), offset);
        let saved_secret = secret.storage.clone();
        for compressed in [0, 1, 2, u64::MAX] {
            let capacity = if compressed == 0 { 65 } else { 33 };
            error_call(capacity, offset, INVALID_SECRET_KEY, |out| unsafe {
                p256_public_key(core::ptr::null(), 0, compressed, out)
            });
            error_call(capacity, offset, INVALID_PUBLIC_KEY, |out| unsafe {
                p256_convert_public_key(core::ptr::null(), 0, compressed, out)
            });
        }
        error_call(64, offset, INVALID_SECRET_KEY, |out| unsafe {
            p256_sign_prehash(core::ptr::null(), 0, core::ptr::null(), 0, out)
        });
        error_call(64, offset, INVALID_DIGEST, |out| unsafe {
            p256_sign_prehash(secret.ptr(), secret.length, core::ptr::null(), 0, out)
        });
        error_call(
            prepared_table::BYTES,
            offset,
            INVALID_PUBLIC_KEY,
            |out| unsafe { p256_prepare_public_key(core::ptr::null(), 0, out) },
        );
        for export in [
            p256_signature_to_der as unsafe extern "C" fn(*const u8, usize, *mut u8) -> i64,
            p256_signature_from_der,
            p256_normalize_signature,
        ]
        .into_iter()
        .zip([72, 64, 64])
        {
            error_call(export.1, offset, INVALID_SIGNATURE, |out| unsafe {
                export.0(core::ptr::null(), 0, out)
            });
        }
        assert_eq!(secret.storage, saved_secret);
    }
}

#[test]
fn public_key_exports_respect_both_capacities_and_nonzero_boolean() {
    for offset in 1..=8 {
        let secret = Buffer::new(&hex(SECRET), offset);
        let compressed_key = Buffer::new(&hex(PUBLIC), offset);
        let uncompressed_key = Buffer::new(&hex(UNCOMPRESSED), offset);
        let saved = [
            secret.storage.clone(),
            compressed_key.storage.clone(),
            uncompressed_key.storage.clone(),
        ];
        for compressed in [0, 1, 2, u64::MAX] {
            let expected = hex(if compressed == 0 {
                UNCOMPRESSED
            } else {
                PUBLIC
            });
            let output = output_call(
                expected.len(),
                offset,
                expected.len() as i64,
                |out| unsafe { p256_public_key(secret.ptr(), secret.length, compressed, out) },
            );
            assert_eq!(output.bytes(), expected);
            for key in [&compressed_key, &uncompressed_key] {
                let output = output_call(
                    expected.len(),
                    offset,
                    expected.len() as i64,
                    |out| unsafe {
                        p256_convert_public_key(key.ptr(), key.length, compressed, out)
                    },
                );
                assert_eq!(output.bytes(), expected);
            }
        }
        assert_eq!(secret.storage, saved[0]);
        assert_eq!(compressed_key.storage, saved[1]);
        assert_eq!(uncompressed_key.storage, saved[2]);
    }
}

#[test]
fn unary_exports_preserve_inputs_and_initialize_der_tail() {
    let mut minimal = vec![0; 64];
    minimal[31] = 1;
    minimal[63] = 1;
    for offset in 1..=8 {
        // The shortest and longest DER encodings exercise both ends of the
        // fixed 72-byte scratch capacity, including its otherwise unused tail.
        for (compact, der) in [
            (minimal.clone(), hex("3006020101020101")),
            (hex(SIGNATURE), hex(DER)),
        ] {
            let compact = Buffer::new(&compact, offset);
            let der = Buffer::new(&der, offset);
            let before_compact = compact.storage.clone();
            let before_der = der.storage.clone();
            let output = output_call(72, offset, der.length as i64, |out| unsafe {
                p256_signature_to_der(compact.ptr(), compact.length, out)
            });
            assert_eq!(&output.bytes()[..der.length], der.bytes());
            assert!(output.bytes()[der.length..].iter().all(|b| *b == 0));
            let output = output_call(64, offset, 64, |out| unsafe {
                p256_signature_from_der(der.ptr(), der.length, out)
            });
            assert_eq!(output.bytes(), compact.bytes());
            assert_eq!(compact.storage, before_compact);
            assert_eq!(der.storage, before_der);
        }
        for signature in [SIGNATURE, LOW_SIGNATURE] {
            let signature = Buffer::new(&hex(signature), offset);
            let saved = signature.storage.clone();
            let output = output_call(64, offset, 64, |out| unsafe {
                p256_normalize_signature(signature.ptr(), signature.length, out)
            });
            assert_eq!(output.bytes(), hex(LOW_SIGNATURE));
            assert_eq!(signature.storage, saved);
        }
    }
}

#[test]
fn signing_and_preparation_preserve_unaligned_inputs() {
    for offset in 1..=8 {
        let secret = Buffer::new(&hex(SECRET), offset);
        let key = Buffer::new(&hex(PUBLIC), offset);
        let hash = Buffer::new(&hex(HASH), offset);
        let signature = Buffer::new(&hex(SIGNATURE), offset);
        let saved = [
            secret.storage.clone(),
            key.storage.clone(),
            hash.storage.clone(),
            signature.storage.clone(),
        ];
        let output = output_call(64, offset, 64, |out| unsafe {
            p256_sign_prehash(secret.ptr(), secret.length, hash.ptr(), hash.length, out)
        });
        assert_eq!(output.bytes(), signature.bytes());
        let prepared = output_call(
            prepared_table::BYTES,
            offset,
            prepared_table::BYTES as i64,
            |out| unsafe { p256_prepare_public_key(key.ptr(), key.length, out) },
        );
        let saved_prepared = prepared.storage.clone();
        assert_eq!(
            unsafe {
                p256_verify_prehash(
                    key.ptr(),
                    key.length,
                    hash.ptr(),
                    hash.length,
                    signature.ptr(),
                    signature.length,
                )
            },
            1
        );
        assert_eq!(
            unsafe {
                p256_verify_prehash_prepared(
                    prepared.ptr(),
                    hash.ptr(),
                    hash.length,
                    signature.ptr(),
                    signature.length,
                )
            },
            1
        );
        assert_eq!(prepared.storage, saved_prepared);
        assert_eq!(secret.storage, saved[0]);
        assert_eq!(key.storage, saved[1]);
        assert_eq!(hash.storage, saved[2]);
        assert_eq!(signature.storage, saved[3]);
    }
}

#[test]
fn verification_accepts_readonly_overlap_and_null_empty_arguments() {
    let generator = hex("036b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296");
    let mut compact = vec![0; 64];
    compact[31] = 1;
    compact[63] = 1;
    for offset in 1..=8 {
        let key = Buffer::new(&generator, offset);
        let signature = Buffer::new(&compact, offset);
        let saved_key = key.storage.clone();
        let saved_signature = signature.storage.clone();
        let prepared = output_call(
            prepared_table::BYTES,
            offset,
            prepared_table::BYTES as i64,
            |out| unsafe { p256_prepare_public_key(key.ptr(), key.length, out) },
        );
        let saved_prepared = prepared.storage.clone();
        // The digest aliases the first scalar of the compact signature. With
        // Q=G and z=r=s=1, verification computes 2G, whose x is not 1.
        unsafe {
            assert_eq!(
                p256_verify_prehash(
                    key.ptr(),
                    key.length,
                    signature.ptr(),
                    32,
                    signature.ptr(),
                    signature.length
                ),
                0
            );
            assert_eq!(
                p256_verify_prehash_prepared(
                    prepared.ptr(),
                    signature.ptr(),
                    32,
                    signature.ptr(),
                    signature.length
                ),
                0
            );
            assert_eq!(
                p256_verify_prehash(
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0
                ),
                INVALID_PUBLIC_KEY
            );
            assert_eq!(
                p256_verify_prehash(
                    key.ptr(),
                    key.length,
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0
                ),
                INVALID_DIGEST
            );
            assert_eq!(
                p256_verify_prehash(
                    key.ptr(),
                    key.length,
                    signature.ptr(),
                    32,
                    core::ptr::null(),
                    0
                ),
                INVALID_SIGNATURE
            );
            assert_eq!(
                p256_verify_prehash_prepared(
                    prepared.ptr(),
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0
                ),
                INVALID_DIGEST
            );
            assert_eq!(
                p256_verify_prehash_prepared(
                    prepared.ptr(),
                    signature.ptr(),
                    32,
                    core::ptr::null(),
                    0
                ),
                INVALID_SIGNATURE
            );
        }
        assert_eq!(key.storage, saved_key);
        assert_eq!(signature.storage, saved_signature);
        assert_eq!(prepared.storage, saved_prepared);
    }
}
