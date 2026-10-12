//! SHA-512/SHA-384 with canonical bounded streaming state. All persistent state
//! belongs to a caller-owned Motoko Blob; this runtime retains no pointers.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]
#![allow(deprecated)] // sha2 0.10 uses generic-array 0.14.

use sha2::compress512;
use sha2::digest::generic_array::{GenericArray, typenum::U128};
#[cfg(test)]
use sha2::{Digest, Sha384, Sha512};

const STATE_SIZE: usize = 216;
const LIMIT: u128 = 1u128 << 125;
const INITIAL512: [u64; 8] = [
    0x6a09e667f3bcc908,
    0xbb67ae8584caa73b,
    0x3c6ef372fe94f82b,
    0xa54ff53a5f1d36f1,
    0x510e527fade682d1,
    0x9b05688c2b3e6c1f,
    0x1f83d9abfb41bd6b,
    0x5be0cd19137e2179,
];
const INITIAL384: [u64; 8] = [
    0xcbbb9d5dc1059ed8,
    0x629a292a367cd507,
    0x9159015a3070dd17,
    0x152fecd8f70e5939,
    0x67332667ffc00b31,
    0x8eb44a8768581511,
    0xdb0c2e0d64f98fa7,
    0x47b5481dbefa4fa4,
];

// `sha2` 0.10.9's compress512 adapter relies on GenericArray<u8, U128>
// having the [u8; 128] layout. Batch full byte blocks through its public API.
fn compress_blocks(state: &mut [u64; 8], bytes: &[u8]) {
    debug_assert_eq!(bytes.len() % 128, 0);
    // Alignment is one; count complete blocks are readable within `bytes`.
    // The immutable view lives only for this call and cannot escape.
    let blocks = unsafe {
        core::slice::from_raw_parts(
            bytes.as_ptr().cast::<GenericArray<u8, U128>>(),
            bytes.len() / 128,
        )
    };
    compress512(state, blocks);
}

// Validate the unused canonical tail in machine words. Byte-wise scanning
// dominated short streaming updates even though only 128 bytes are retained.
fn all_zero(bytes: &[u8]) -> bool {
    let mut words = bytes.chunks_exact(8);
    let combined = words.by_ref().fold(0u64, |bits, word| {
        bits | u64::from_ne_bytes(word.try_into().expect("word length"))
    });
    combined == 0 && words.remainder().iter().all(|&byte| byte == 0)
}

#[derive(Clone)]
struct State {
    size: u8,
    words: [u64; 8],
    length: u128,
    tail: [u8; 128],
}
impl State {
    fn new(size: u8) -> Self {
        Self {
            size,
            words: if size == 48 { INITIAL384 } else { INITIAL512 },
            length: 0,
            tail: [0; 128],
        }
    }
    fn decode(bytes: &[u8]) -> Option<Self> {
        if bytes.len() != STATE_SIZE
            || &bytes[..4] != b"S512"
            || !matches!(bytes[4], 48 | 64)
            || bytes[5..8] != [0; 3]
        {
            return None;
        }
        let length = u128::from_be_bytes(bytes[72..88].try_into().ok()?);
        if length >= LIMIT {
            return None;
        }
        let used = (length % 128) as usize;
        if !all_zero(&bytes[88 + used..]) {
            return None;
        }
        let mut words = [0; 8];
        for (word, bytes) in words.iter_mut().zip(bytes[8..72].chunks_exact(8)) {
            *word = u64::from_be_bytes(bytes.try_into().ok()?);
        }
        if length < 128
            && words
                != if bytes[4] == 48 {
                    INITIAL384
                } else {
                    INITIAL512
                }
        {
            return None;
        }
        let mut tail = [0; 128];
        tail.copy_from_slice(&bytes[88..]);
        Some(Self {
            size: bytes[4],
            words,
            length,
            tail,
        })
    }
    // The caller provides a fresh uninitialized Blob payload. Initialize it
    // directly, without materializing/copying an intermediate 216-byte array.
    unsafe fn encode_into(&self, output: *mut u8) {
        let header = [b'S', b'5', b'1', b'2', self.size, 0, 0, 0];
        unsafe {
            output
                .cast::<u64>()
                .write_unaligned(u64::from_ne_bytes(header))
        };
        for (i, word) in self.words.iter().enumerate() {
            unsafe {
                output
                    .add(8 + i * 8)
                    .cast::<u64>()
                    .write_unaligned(word.to_be())
            };
        }
        let length = self.length.to_be_bytes();
        unsafe { core::ptr::copy_nonoverlapping(length.as_ptr(), output.add(72), 16) };
        unsafe { core::ptr::copy_nonoverlapping(self.tail.as_ptr(), output.add(88), 128) };
    }
    #[cfg(test)]
    fn encode(&self) -> [u8; STATE_SIZE] {
        let mut out = [0; STATE_SIZE];
        out[..4].copy_from_slice(b"S512");
        out[4] = self.size;
        for (word, bytes) in self.words.iter().zip(out[8..72].chunks_exact_mut(8)) {
            bytes.copy_from_slice(&word.to_be_bytes());
        }
        out[72..88].copy_from_slice(&self.length.to_be_bytes());
        out[88..].copy_from_slice(&self.tail);
        out
    }
    fn update(&mut self, mut input: &[u8]) -> Option<()> {
        let new_length = self.length.checked_add(input.len() as u128)?;
        if new_length >= LIMIT {
            return None;
        }
        let used = (self.length % 128) as usize;
        self.length = new_length;
        if used != 0 {
            let take = core::cmp::min(128 - used, input.len());
            self.tail[used..used + take].copy_from_slice(&input[..take]);
            input = &input[take..];
            if used + take < 128 {
                return Some(());
            }
            compress_blocks(&mut self.words, &self.tail);
            self.tail.fill(0);
        }
        let full_length = input.len() / 128 * 128;
        if full_length != 0 {
            compress_blocks(&mut self.words, &input[..full_length]);
        }
        let rest = &input[full_length..];
        self.tail[..rest.len()].copy_from_slice(rest);
        Some(())
    }
    fn finish(&mut self) {
        let used = (self.length % 128) as usize;
        self.tail[used] = 0x80;
        if used >= 112 {
            compress_blocks(&mut self.words, &self.tail);
            self.tail.fill(0);
        }
        self.tail[112..128].copy_from_slice(&(self.length << 3).to_be_bytes());
        compress_blocks(&mut self.words, &self.tail);
    }
    unsafe fn finalize_into(mut self, output: *mut u8) {
        self.finish();
        for (i, word) in self.words.iter().take(self.size as usize / 8).enumerate() {
            unsafe {
                output
                    .add(i * 8)
                    .cast::<u64>()
                    .write_unaligned(word.to_be())
            };
        }
    }
    #[cfg(test)]
    fn finalize(mut self) -> [u8; 64] {
        self.finish();
        let mut out = [0; 64];
        for (word, bytes) in self.words.iter().zip(out.chunks_exact_mut(8)) {
            bytes.copy_from_slice(&word.to_be_bytes());
        }
        out
    }
}

// Feed complete input blocks in one batch, sharing padding and output code
// between SHA-512 and SHA-384 while retaining RustCrypto compression.
#[inline(never)]
unsafe fn digest_general(input: *const u8, len: usize, output: *mut u8, size: u8) {
    let input = unsafe { core::slice::from_raw_parts(input, len) };
    let mut state = if size == 48 { INITIAL384 } else { INITIAL512 };
    let full_length = input.len() / 128 * 128;
    if full_length != 0 {
        compress_blocks(&mut state, &input[..full_length]);
    }
    let remaining = &input[full_length..];
    let mut tail = [0u8; 256];
    tail[..remaining.len()].copy_from_slice(remaining);
    tail[remaining.len()] = 0x80;
    let padded = if remaining.len() < 112 { 128 } else { 256 };
    tail[padded - 16..padded].copy_from_slice(&((len as u128) << 3).to_be_bytes());
    compress_blocks(&mut state, &tail[..padded]);
    for (i, word) in state.iter().take(size as usize / 8).enumerate() {
        unsafe {
            output
                .add(i * 8)
                .cast::<u64>()
                .write_unaligned(word.to_be())
        };
    }
}

/// # Safety
/// Input has `len` readable bytes; output has 64 writable bytes. They do not
/// overlap and remain valid for this synchronous, allocation-free call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha512_digest(input: *const u8, len: usize, output: *mut u8) {
    if len == 0 {
        // FIPS 180-4 empty-message known answer, stored directly as unaligned words.
        unsafe {
            output
                .add(0)
                .cast::<u64>()
                .write_unaligned(0xcf83e1357eefb8bdu64.to_be())
        };
        unsafe {
            output
                .add(8)
                .cast::<u64>()
                .write_unaligned(0xf1542850d66d8007u64.to_be())
        };
        unsafe {
            output
                .add(16)
                .cast::<u64>()
                .write_unaligned(0xd620e4050b5715dcu64.to_be())
        };
        unsafe {
            output
                .add(24)
                .cast::<u64>()
                .write_unaligned(0x83f4a921d36ce9ceu64.to_be())
        };
        unsafe {
            output
                .add(32)
                .cast::<u64>()
                .write_unaligned(0x47d0d13c5d85f2b0u64.to_be())
        };
        unsafe {
            output
                .add(40)
                .cast::<u64>()
                .write_unaligned(0xff8318d2877eec2fu64.to_be())
        };
        unsafe {
            output
                .add(48)
                .cast::<u64>()
                .write_unaligned(0x63b931bd47417a81u64.to_be())
        };
        unsafe {
            output
                .add(56)
                .cast::<u64>()
                .write_unaligned(0xa538327af927da3eu64.to_be())
        };
        return;
    }
    unsafe { digest_general(input, len, output, 64) };
}
/// # Safety
/// Same contract as `sha512_digest`, with 48 output bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha512_digest384(input: *const u8, len: usize, output: *mut u8) {
    if len == 0 {
        // FIPS 180-4 empty-message known answer, stored directly as unaligned words.
        unsafe {
            output
                .add(0)
                .cast::<u64>()
                .write_unaligned(0x38b060a751ac9638u64.to_be())
        };
        unsafe {
            output
                .add(8)
                .cast::<u64>()
                .write_unaligned(0x4cd9327eb1b1e36au64.to_be())
        };
        unsafe {
            output
                .add(16)
                .cast::<u64>()
                .write_unaligned(0x21fdb71114be0743u64.to_be())
        };
        unsafe {
            output
                .add(24)
                .cast::<u64>()
                .write_unaligned(0x4c0cc7bf63f6e1dau64.to_be())
        };
        unsafe {
            output
                .add(32)
                .cast::<u64>()
                .write_unaligned(0x274edebfe76f65fbu64.to_be())
        };
        unsafe {
            output
                .add(40)
                .cast::<u64>()
                .write_unaligned(0xd51ad2f14898b95bu64.to_be())
        };
        return;
    }
    unsafe { digest_general(input, len, output, 48) };
}
/// # Safety
/// Output has STATE_SIZE writable bytes and remains valid during this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha512_init(output: *mut u8) {
    unsafe { State::new(64).encode_into(output) };
}
/// # Safety
/// Same contract as `sha512_init`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha512_init384(output: *mut u8) {
    unsafe { State::new(48).encode_into(output) };
}
/// # Safety
/// State/input have their specified readable lengths. Output has STATE_SIZE
/// writable bytes, overlaps neither input, and all pointers remain valid.
/// Invalid state/length returns zero and initializes the entire output to zero.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha512_update(
    state: *const u8,
    state_len: usize,
    input: *const u8,
    len: usize,
    output: *mut u8,
) -> u32 {
    let bytes = unsafe { core::slice::from_raw_parts(state, state_len) };
    let input = unsafe { core::slice::from_raw_parts(input, len) };
    if let Some(mut state) = State::decode(bytes) {
        if state.update(input).is_some() {
            unsafe { state.encode_into(output) };
            return 1;
        }
    }
    unsafe { core::ptr::write_bytes(output, 0, STATE_SIZE) };
    0
}
unsafe fn sum(state: *const u8, len: usize, output: *mut u8, size: u8) -> u32 {
    let bytes = unsafe { core::slice::from_raw_parts(state, len) };
    match State::decode(bytes).filter(|state| state.size == size) {
        Some(state) => {
            unsafe { state.finalize_into(output) };
            1
        }
        None => {
            unsafe { core::ptr::write_bytes(output, 0, size as usize) };
            0
        }
    }
}
/// # Safety
/// State has len readable bytes; output has 64 writable nonoverlapping bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha512_sum(state: *const u8, len: usize, output: *mut u8) -> u32 {
    unsafe { sum(state, len, output, 64) }
}
/// # Safety
/// State has len readable bytes; output has 48 writable nonoverlapping bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha512_sum384(state: *const u8, len: usize, output: *mut u8) -> u32 {
    unsafe { sum(state, len, output, 48) }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests {
    use super::*;
    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }
    #[test]
    fn nist_vectors() {
        assert_eq!(
            hex(&Sha512::digest(b"")),
            "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
        );
        assert_eq!(
            hex(&Sha512::digest(b"abc")),
            "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
        );
        assert_eq!(
            hex(&Sha384::digest(b"abc")),
            "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"
        );
        let million = vec![b'a'; 1_000_000];
        for (size, expected) in [
            (
                64,
                "e718483d0ce769644e2e42c7bc15b4638e1f98b13b2044285632a803afa973ebde0ff244877ea60a4cb0432ce577c31beb009c5c2c49aa2e4eadb217ad8cc09b",
            ),
            (
                48,
                "9d0e1809716474cb086e834e310a4a1ced149e9c00f248527972cec5704c2a5b07b8b3dc38ecc4ebae97ddd87f3d8985",
            ),
        ] {
            let mut state = State::new(size);
            state.update(&million).unwrap();
            assert_eq!(hex(&state.finalize()[..size as usize]), expected);
        }
    }
    #[test]
    fn partitions_and_canonical_encoding() {
        for size in [48, 64] {
            for len in [
                0, 1, 63, 64, 111, 112, 113, 127, 128, 129, 239, 240, 255, 256, 257, 1024, 65537,
            ] {
                let bytes: Vec<u8> = (0..len).map(|i| (i * 131 + 17) as u8).collect();
                let expected = if size == 64 {
                    Sha512::digest(&bytes).to_vec()
                } else {
                    Sha384::digest(&bytes).to_vec()
                };
                let mut one_shot = [0xa5; 66];
                unsafe {
                    if size == 64 {
                        sha512_digest(bytes.as_ptr(), bytes.len(), one_shot.as_mut_ptr().add(1));
                    } else {
                        sha512_digest384(bytes.as_ptr(), bytes.len(), one_shot.as_mut_ptr().add(1));
                    }
                }
                assert_eq!(&one_shot[1..size as usize + 1], expected);
                assert_eq!(one_shot[0], 0xa5);
                assert_eq!(one_shot[size as usize + 1], 0xa5);
                for chunk in [1, 7, 111, 127, 128, 129, 4096] {
                    let mut state = State::new(size);
                    for input in bytes.chunks(chunk) {
                        state.update(input).unwrap();
                        let encoded = state.encode();
                        state = State::decode(&encoded).unwrap();
                        assert_eq!(state.encode(), encoded);
                    }
                    assert_eq!(&state.clone().finalize()[..size as usize], expected);
                    let before = state.encode();
                    state.update(b"").unwrap();
                    assert_eq!(before, state.encode());
                }
            }
        }
    }
    #[test]
    fn canonical_tail_word_and_byte_boundaries() {
        for length in 0..=128 {
            let mut bytes = vec![0; length];
            assert!(all_zero(&bytes));
            for offset in 0..length {
                bytes[offset] = 1;
                assert!(!all_zero(&bytes), "length {length}, offset {offset}");
                bytes[offset] = 0;
            }
        }
        for size in [48, 64] {
            for used in 0..128 {
                let mut state = State::new(size);
                state.update(&vec![0x55; used]).unwrap();
                let encoded = state.encode();
                assert!(State::decode(&encoded).is_some());
                for position in used..128 {
                    let mut malformed = encoded;
                    malformed[88 + position] = 1;
                    assert!(State::decode(&malformed).is_none());
                }
            }
        }
    }
    #[test]
    fn direct_serialization_matches_canonical_layout() {
        for size in [48, 64] {
            for length in [
                0, 1, 7, 8, 63, 64, 111, 112, 127, 128, 129, 239, 240, 255, 256, 257, 1024,
            ] {
                let input: Vec<u8> = (0..length).map(|i| (i * 131 + 17) as u8).collect();
                let mut state = State::new(size);
                state.update(&input).unwrap();
                let expected = state.encode();
                for offset in 1..=8 {
                    let mut output = vec![0xa5; STATE_SIZE + 16];
                    unsafe { state.encode_into(output.as_mut_ptr().add(offset)) };
                    assert_eq!(&output[offset..offset + STATE_SIZE], expected);
                    assert!(output[..offset].iter().all(|&b| b == 0xa5));
                    assert!(output[offset + STATE_SIZE..].iter().all(|&b| b == 0xa5));
                    let mut digest = [0xa5; 80];
                    unsafe { state.clone().finalize_into(digest.as_mut_ptr().add(offset)) };
                    assert_eq!(
                        &digest[offset..offset + size as usize],
                        &state.clone().finalize()[..size as usize]
                    );
                    assert!(digest[..offset].iter().all(|&b| b == 0xa5));
                    assert!(digest[offset + size as usize..].iter().all(|&b| b == 0xa5));
                    assert_eq!(state.encode(), expected);
                }
            }
        }
    }
    #[test]
    fn malformed_states_and_length_overflow() {
        let valid = State::new(64).encode();
        for index in [0, 3, 4, 5, 7, 8, 71, 72, 88, 215] {
            let mut bad = valid;
            bad[index] ^= 0xff;
            assert!(State::decode(&bad).is_none(), "index {index}");
        }
        assert!(State::decode(&valid[..215]).is_none());
        let mut state = State::new(48);
        state.length = LIMIT - 1;
        state.tail = [0x55; 128];
        state.tail[127] = 0;
        let before = state.encode();
        assert!(state.update(b"x").is_none());
        assert_eq!(before, state.encode());
        assert!(state.update(b"").is_some());
        let mut carry = State::new(64);
        carry.length = u64::MAX as u128 - 127;
        carry.update(&[0; 128]).unwrap();
        assert_eq!(carry.length, 1u128 << 64);
    }
    #[test]
    fn exported_abi_guards_and_input_immutability() {
        for size in [48, 64] {
            let mut state = [0xa5; STATE_SIZE + 2];
            let mut result = [0xa5; 66];
            unsafe {
                if size == 64 {
                    sha512_init(state.as_mut_ptr().add(1));
                } else {
                    sha512_init384(state.as_mut_ptr().add(1));
                }
                let initial = state;
                let mut next = [0xa5; STATE_SIZE + 2];
                assert_eq!(
                    sha512_update(
                        state.as_ptr().add(1),
                        STATE_SIZE,
                        b"abc".as_ptr(),
                        3,
                        next.as_mut_ptr().add(1)
                    ),
                    1
                );
                assert_eq!(state, initial);
                let saved = next;
                assert_eq!(
                    sum(
                        next.as_ptr().add(1),
                        STATE_SIZE,
                        result.as_mut_ptr().add(1),
                        size
                    ),
                    1
                );
                assert_eq!(next, saved);
                let digest = if size == 64 {
                    Sha512::digest(b"abc").to_vec()
                } else {
                    Sha384::digest(b"abc").to_vec()
                };
                assert_eq!(&result[1..size as usize + 1], digest);
                assert_eq!(result[0], 0xa5);
                assert_eq!(result[size as usize + 1], 0xa5);
                let borrowed = [0xa5, b'a', b'b', b'c', 0x5a];
                let saved_input = borrowed;
                result.fill(0xa5);
                if size == 64 {
                    sha512_digest(borrowed.as_ptr().add(1), 3, result.as_mut_ptr().add(1));
                } else {
                    sha512_digest384(borrowed.as_ptr().add(1), 3, result.as_mut_ptr().add(1));
                }
                assert_eq!(&result[1..size as usize + 1], digest);
                assert_eq!(result[0], 0xa5);
                assert_eq!(result[size as usize + 1], 0xa5);
                assert_eq!(borrowed, saved_input);
                assert_eq!(
                    sum(
                        next.as_ptr().add(1),
                        STATE_SIZE,
                        result.as_mut_ptr().add(1),
                        if size == 64 { 48 } else { 64 }
                    ),
                    0
                );
                assert_eq!(next[0], 0xa5);
                assert_eq!(next[STATE_SIZE + 1], 0xa5);
                assert_eq!(sum(b"".as_ptr(), 0, result.as_mut_ptr().add(1), size), 0);
                assert!(result[1..size as usize + 1].iter().all(|&b| b == 0));
                assert_eq!(
                    sha512_update(state.as_ptr(), 2, b"".as_ptr(), 0, next.as_mut_ptr().add(1)),
                    0
                );
                assert!(next[1..STATE_SIZE + 1].iter().all(|&b| b == 0));
            }
        }
    }
}
