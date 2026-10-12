//! Stateless, allocation-free HMAC-SHA2. All persistent state is serialized
//! into fresh managed Blobs by the caller. Input pointers never escape a call.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]
#![allow(deprecated)] // sha2 0.10's stable compression API uses generic-array 0.14.
use sha2::digest::generic_array::GenericArray;
use sha2::{Digest, Sha256, Sha512, compress256, compress512};

// Check unaligned serialized tails without reading past their end.
fn zero_tail(input: &[u8]) -> bool {
    let mut words = input.chunks_exact(8);
    words.all(|word| u64::from_ne_bytes(word.try_into().unwrap()) == 0)
        && words.remainder().iter().all(|byte| *byte == 0)
}

const INITIAL256: [u32; 8] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];
const STATE256: usize = 136;

#[derive(Clone)]
struct Hmac256 {
    inner: [u32; 8],
    outer: [u32; 8],
    count: u64,
    tail: [u8; 64],
}
impl Hmac256 {
    fn compress(state: &mut [u32; 8], block: &[u8]) {
        compress256(
            state,
            core::slice::from_ref(GenericArray::from_slice(block)),
        );
    }
    fn new(key: &[u8]) -> Self {
        let mut pad = [0x36u8; 64];
        if key.len() > 64 {
            for (byte, key_byte) in pad.iter_mut().zip(Sha256::digest(key)) {
                *byte ^= key_byte;
            }
        } else {
            for (byte, key_byte) in pad.iter_mut().zip(key) {
                *byte ^= key_byte;
            }
        }
        let mut inner = INITIAL256;
        Self::compress(&mut inner, &pad);
        for word in pad.chunks_exact_mut(8) {
            let value = u64::from_ne_bytes((&*word).try_into().unwrap());
            word.copy_from_slice(&(value ^ 0x6a6a6a6a6a6a6a6a).to_ne_bytes());
        }
        let mut outer = INITIAL256;
        Self::compress(&mut outer, &pad);
        Self {
            inner,
            outer,
            count: 64,
            tail: [0; 64],
        }
    }
    fn decode(input: &[u8]) -> Self {
        assert!(input.len() == STATE256, "invalid HMAC-SHA256 state length");
        let count = u64::from_be_bytes(input[64..72].try_into().unwrap());
        assert!(
            count >= 64 && count <= u64::MAX / 8,
            "invalid HMAC-SHA256 count"
        );
        let used = (count % 64) as usize;
        assert!(
            zero_tail(&input[72 + used..]),
            "noncanonical HMAC-SHA256 tail"
        );
        let mut inner = [0; 8];
        let mut outer = [0; 8];
        for i in 0..8 {
            inner[i] = u32::from_be_bytes(input[i * 4..(i + 1) * 4].try_into().unwrap());
            outer[i] = u32::from_be_bytes(input[32 + i * 4..32 + (i + 1) * 4].try_into().unwrap());
        }
        // Canonical validation above guarantees unused tail bytes are zero.
        let tail = input[72..].try_into().unwrap();
        Self {
            inner,
            outer,
            count,
            tail,
        }
    }
    #[cfg(test)]
    fn encode(&self) -> [u8; STATE256] {
        let mut output = [0; STATE256];
        for i in 0..8 {
            output[i * 4..(i + 1) * 4].copy_from_slice(&self.inner[i].to_be_bytes());
            output[32 + i * 4..32 + (i + 1) * 4].copy_from_slice(&self.outer[i].to_be_bytes());
        }
        output[64..72].copy_from_slice(&self.count.to_be_bytes());
        // new/decode/update preserve the zeroed unused-tail invariant.
        output[72..].copy_from_slice(&self.tail);
        output
    }
    // Writes every byte of a fresh Blob without referencing uninitialized memory.
    unsafe fn write_state(&self, output: *mut u8) {
        for i in 0..8 {
            unsafe {
                output
                    .add(i * 4)
                    .cast::<u32>()
                    .write_unaligned(self.inner[i].to_be());
                output
                    .add(32 + i * 4)
                    .cast::<u32>()
                    .write_unaligned(self.outer[i].to_be());
            }
        }
        unsafe {
            core::ptr::copy_nonoverlapping(self.count.to_be_bytes().as_ptr(), output.add(64), 8);
            core::ptr::copy_nonoverlapping(self.tail.as_ptr(), output.add(72), 64);
        }
    }
    fn update(&mut self, mut input: &[u8]) {
        let used = (self.count % 64) as usize;
        self.count = self
            .count
            .checked_add(input.len() as u64)
            .expect("HMAC input too long");
        assert!(self.count <= u64::MAX / 8, "HMAC input too long");
        if used > 0 {
            let take = core::cmp::min(64 - used, input.len());
            self.tail[used..used + take].copy_from_slice(&input[..take]);
            input = &input[take..];
            if used + take < 64 {
                return;
            }
            Self::compress(&mut self.inner, &self.tail);
            self.tail.fill(0);
        }
        let blocks = input.len() / 64;
        const {
            assert!(core::mem::size_of::<GenericArray<u8, sha2::digest::typenum::U64>>() == 64);
            assert!(core::mem::align_of::<GenericArray<u8, sha2::digest::typenum::U64>>() == 1);
        }
        // GenericArray<u8, U64> has alignment 1 and exactly 64 bytes,
        // the layout also relied on by RustCrypto's public compression API.
        // Borrow only complete blocks; retain no pointer beyond this call.
        if blocks > 0 {
            let blocks_slice: &[GenericArray<u8, sha2::digest::typenum::U64>] =
                unsafe { core::slice::from_raw_parts(input.as_ptr().cast(), blocks) };
            compress256(&mut self.inner, blocks_slice);
        }
        let remainder = &input[blocks * 64..];
        self.tail[..remainder.len()].copy_from_slice(remainder);
    }
    fn sum(mut self) -> [u8; 32] {
        let used = (self.count % 64) as usize;
        self.tail[used] = 0x80;
        if used >= 56 {
            Self::compress(&mut self.inner, &self.tail);
            self.tail.fill(0);
        }
        self.tail[56..].copy_from_slice(&(self.count * 8).to_be_bytes());
        Self::compress(&mut self.inner, &self.tail);
        self.tail.fill(0);
        for i in 0..8 {
            self.tail[i * 4..(i + 1) * 4].copy_from_slice(&self.inner[i].to_be_bytes());
        }
        self.tail[32] = 0x80;
        self.tail[56..].copy_from_slice(&((64 + 32) as u64 * 8).to_be_bytes());
        Self::compress(&mut self.outer, &self.tail);
        let mut output = [0; 32];
        for i in 0..8 {
            output[i * 4..(i + 1) * 4].copy_from_slice(&self.outer[i].to_be_bytes());
        }
        output
    }
}

/// # Safety
/// The input ranges are readable; output points to 32 writable nonoverlapping
/// bytes. Pointers remain valid through this synchronous call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha256(
    key: *const u8,
    key_len: usize,
    input: *const u8,
    len: usize,
    output: *mut u8,
) {
    let mut state = Hmac256::new(unsafe { core::slice::from_raw_parts(key, key_len) });
    state.update(unsafe { core::slice::from_raw_parts(input, len) });
    unsafe { core::ptr::copy_nonoverlapping(state.sum().as_ptr(), output, 32) };
}
/// # Safety
/// Key is readable for key_len bytes; output points to 136 writable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha256_init(key: *const u8, key_len: usize, output: *mut u8) {
    let state = Hmac256::new(unsafe { core::slice::from_raw_parts(key, key_len) });
    unsafe { state.write_state(output) };
}
/// # Safety
/// The input ranges are readable; output points to 136 writable bytes,
/// nonoverlapping with inputs. State contains a canonical context.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha256_update(
    state: *const u8,
    state_len: usize,
    input: *const u8,
    len: usize,
    output: *mut u8,
) {
    let mut state = Hmac256::decode(unsafe { core::slice::from_raw_parts(state, state_len) });
    state.update(unsafe { core::slice::from_raw_parts(input, len) });
    unsafe { state.write_state(output) };
}
/// # Safety
/// State is readable for state_len bytes and canonical; output has 32 writable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha256_sum(state: *const u8, state_len: usize, output: *mut u8) {
    let state = Hmac256::decode(unsafe { core::slice::from_raw_parts(state, state_len) });
    unsafe { core::ptr::copy_nonoverlapping(state.sum().as_ptr(), output, 32) };
}
/// # Safety
/// The input ranges are readable; output has 32 writable nonoverlapping bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha256_prepared(
    state: *const u8,
    state_len: usize,
    input: *const u8,
    len: usize,
    output: *mut u8,
) {
    let mut state = Hmac256::decode(unsafe { core::slice::from_raw_parts(state, state_len) });
    state.update(unsafe { core::slice::from_raw_parts(input, len) });
    unsafe { core::ptr::copy_nonoverlapping(state.sum().as_ptr(), output, 32) };
}

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
const STATE512: usize = 272;

#[derive(Clone)]
struct Hmac512 {
    inner: [u64; 8],
    outer: [u64; 8],
    count: u128,
    tail: [u8; 128],
}
impl Hmac512 {
    fn compress(state: &mut [u64; 8], block: &[u8]) {
        compress512(
            state,
            core::slice::from_ref(GenericArray::from_slice(block)),
        );
    }
    fn new(key: &[u8]) -> Self {
        let mut pad = [0x36u8; 128];
        if key.len() > 128 {
            for (byte, key_byte) in pad.iter_mut().zip(Sha512::digest(key)) {
                *byte ^= key_byte;
            }
        } else {
            for (byte, key_byte) in pad.iter_mut().zip(key) {
                *byte ^= key_byte;
            }
        }
        let mut inner = INITIAL512;
        Self::compress(&mut inner, &pad);
        for word in pad.chunks_exact_mut(8) {
            let value = u64::from_ne_bytes((&*word).try_into().unwrap());
            word.copy_from_slice(&(value ^ 0x6a6a6a6a6a6a6a6a).to_ne_bytes());
        }
        let mut outer = INITIAL512;
        Self::compress(&mut outer, &pad);
        Self {
            inner,
            outer,
            count: 128,
            tail: [0; 128],
        }
    }
    fn decode(input: &[u8]) -> Self {
        assert!(input.len() == STATE512, "invalid HMAC-SHA512 state length");
        let count = u128::from_be_bytes(input[128..144].try_into().unwrap());
        assert!(
            count >= 128 && count <= u128::MAX / 8,
            "invalid HMAC-SHA512 count"
        );
        let used = (count % 128) as usize;
        assert!(
            zero_tail(&input[144 + used..]),
            "noncanonical HMAC-SHA512 tail"
        );
        let mut inner = [0; 8];
        let mut outer = [0; 8];
        for i in 0..8 {
            inner[i] = u64::from_be_bytes(input[i * 8..(i + 1) * 8].try_into().unwrap());
            outer[i] = u64::from_be_bytes(input[64 + i * 8..64 + (i + 1) * 8].try_into().unwrap());
        }
        // Canonical validation above guarantees unused tail bytes are zero.
        let tail = input[144..].try_into().unwrap();
        Self {
            inner,
            outer,
            count,
            tail,
        }
    }
    #[cfg(test)]
    fn encode(&self) -> [u8; STATE512] {
        let mut output = [0; STATE512];
        for i in 0..8 {
            output[i * 8..(i + 1) * 8].copy_from_slice(&self.inner[i].to_be_bytes());
            output[64 + i * 8..64 + (i + 1) * 8].copy_from_slice(&self.outer[i].to_be_bytes());
        }
        output[128..144].copy_from_slice(&self.count.to_be_bytes());
        // new/decode/update preserve the zeroed unused-tail invariant.
        output[144..].copy_from_slice(&self.tail);
        output
    }
    // Writes every byte of a fresh Blob without referencing uninitialized memory.
    unsafe fn write_state(&self, output: *mut u8) {
        for i in 0..8 {
            unsafe {
                output
                    .add(i * 8)
                    .cast::<u64>()
                    .write_unaligned(self.inner[i].to_be());
                output
                    .add(64 + i * 8)
                    .cast::<u64>()
                    .write_unaligned(self.outer[i].to_be());
            }
        }
        unsafe {
            core::ptr::copy_nonoverlapping(self.count.to_be_bytes().as_ptr(), output.add(128), 16);
            core::ptr::copy_nonoverlapping(self.tail.as_ptr(), output.add(144), 128);
        }
    }
    fn update(&mut self, mut input: &[u8]) {
        let used = (self.count % 128) as usize;
        self.count = self
            .count
            .checked_add(input.len() as u128)
            .expect("HMAC input too long");
        assert!(self.count <= u128::MAX / 8, "HMAC input too long");
        if used > 0 {
            let take = core::cmp::min(128 - used, input.len());
            self.tail[used..used + take].copy_from_slice(&input[..take]);
            input = &input[take..];
            if used + take < 128 {
                return;
            }
            Self::compress(&mut self.inner, &self.tail);
            self.tail.fill(0);
        }
        let blocks = input.len() / 128;
        const {
            assert!(core::mem::size_of::<GenericArray<u8, sha2::digest::typenum::U128>>() == 128);
            assert!(core::mem::align_of::<GenericArray<u8, sha2::digest::typenum::U128>>() == 1);
        }
        // GenericArray<u8, U128> has alignment 1 and exactly 128 bytes,
        // the layout also relied on by RustCrypto's public compression API.
        // Borrow only complete blocks; retain no pointer beyond this call.
        if blocks > 0 {
            let blocks_slice: &[GenericArray<u8, sha2::digest::typenum::U128>] =
                unsafe { core::slice::from_raw_parts(input.as_ptr().cast(), blocks) };
            compress512(&mut self.inner, blocks_slice);
        }
        let remainder = &input[blocks * 128..];
        self.tail[..remainder.len()].copy_from_slice(remainder);
    }
    fn sum(mut self) -> [u8; 64] {
        let used = (self.count % 128) as usize;
        self.tail[used] = 0x80;
        if used >= 112 {
            Self::compress(&mut self.inner, &self.tail);
            self.tail.fill(0);
        }
        self.tail[112..].copy_from_slice(&(self.count * 8).to_be_bytes());
        Self::compress(&mut self.inner, &self.tail);
        self.tail.fill(0);
        for i in 0..8 {
            self.tail[i * 8..(i + 1) * 8].copy_from_slice(&self.inner[i].to_be_bytes());
        }
        self.tail[64] = 0x80;
        self.tail[112..].copy_from_slice(&((128 + 64) as u128 * 8).to_be_bytes());
        Self::compress(&mut self.outer, &self.tail);
        let mut output = [0; 64];
        for i in 0..8 {
            output[i * 8..(i + 1) * 8].copy_from_slice(&self.outer[i].to_be_bytes());
        }
        output
    }
}

/// # Safety
/// The input ranges are readable; output points to 64 writable nonoverlapping
/// bytes. Pointers remain valid through this synchronous call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha512(
    key: *const u8,
    key_len: usize,
    input: *const u8,
    len: usize,
    output: *mut u8,
) {
    let mut state = Hmac512::new(unsafe { core::slice::from_raw_parts(key, key_len) });
    state.update(unsafe { core::slice::from_raw_parts(input, len) });
    unsafe { core::ptr::copy_nonoverlapping(state.sum().as_ptr(), output, 64) };
}
/// # Safety
/// Key is readable for key_len bytes; output points to 272 writable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha512_init(key: *const u8, key_len: usize, output: *mut u8) {
    let state = Hmac512::new(unsafe { core::slice::from_raw_parts(key, key_len) });
    unsafe { state.write_state(output) };
}
/// # Safety
/// The input ranges are readable; output points to 272 writable bytes,
/// nonoverlapping with inputs. State contains a canonical context.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha512_update(
    state: *const u8,
    state_len: usize,
    input: *const u8,
    len: usize,
    output: *mut u8,
) {
    let mut state = Hmac512::decode(unsafe { core::slice::from_raw_parts(state, state_len) });
    state.update(unsafe { core::slice::from_raw_parts(input, len) });
    unsafe { state.write_state(output) };
}
/// # Safety
/// State is readable for state_len bytes and canonical; output has 64 writable bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha512_sum(state: *const u8, state_len: usize, output: *mut u8) {
    let state = Hmac512::decode(unsafe { core::slice::from_raw_parts(state, state_len) });
    unsafe { core::ptr::copy_nonoverlapping(state.sum().as_ptr(), output, 64) };
}
/// # Safety
/// The input ranges are readable; output has 64 writable nonoverlapping bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn hmac_sha512_prepared(
    state: *const u8,
    state_len: usize,
    input: *const u8,
    len: usize,
    output: *mut u8,
) {
    let mut state = Hmac512::decode(unsafe { core::slice::from_raw_parts(state, state_len) });
    state.update(unsafe { core::slice::from_raw_parts(input, len) });
    unsafe { core::ptr::copy_nonoverlapping(state.sum().as_ptr(), output, 64) };
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests {
    use super::*;
    use hmac::{Hmac, Mac};
    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }
    fn pattern(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i * 131 + 17) as u8).collect()
    }
    fn sum256(key: &[u8], input: &[u8]) -> [u8; 32] {
        let mut state = Hmac256::new(key);
        state.update(input);
        state.sum()
    }
    fn sum512(key: &[u8], input: &[u8]) -> [u8; 64] {
        let mut state = Hmac512::new(key);
        state.update(input);
        state.sum()
    }
    #[test]
    fn rfc4231() {
        let cases = [
            (vec![0x0b;20], b"Hi There".to_vec(), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"),
            (b"Jefe".to_vec(), b"what do ya want for nothing?".to_vec(), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"),
            (vec![0xaa;20], vec![0xdd;50], "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe", "fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb"),
            ((1u8..=25).collect(), vec![0xcd;50], "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b", "b0ba465637458c6990e5a8c5f61d4af7e576d97ff94b872de76f8050361ee3db a91ca5c11aa25eb4d679275cc5788063a5f19741120c4f2de2adebeb10a298dd"),
            (vec![0xaa;131], b"Test Using Larger Than Block-Size Key - Hash Key First".to_vec(), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54", "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598"),
            (vec![0xaa;131], b"This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.".to_vec(), "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2", "e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58"),
        ];
        for (key, message, expected256, expected512) in cases {
            assert_eq!(hex(&sum256(&key, &message)), expected256);
            assert_eq!(hex(&sum512(&key, &message)), expected512.replace(' ', ""));
        }
        assert_eq!(
            hex(&sum256(&[0x0c; 20], b"Test With Truncation")[..16]),
            "a3b6167473100ee06e0c796c2955552b"
        );
        assert_eq!(
            hex(&sum512(&[0x0c; 20], b"Test With Truncation")[..16]),
            "415fad6271580a531d4179bc891d87a6"
        );
    }
    #[test]
    fn streaming_prepared_boundaries_and_rustcrypto_differential() {
        let sizes = [
            0, 1, 2, 31, 32, 55, 56, 63, 64, 65, 111, 112, 127, 128, 129, 255, 256, 257, 1024, 4097,
        ];
        for key_len in [0, 1, 32, 63, 64, 65, 127, 128, 129, 131, 1024] {
            let key = pattern(key_len);
            let initial256 = Hmac256::new(&key).encode();
            let initial512 = Hmac512::new(&key).encode();
            for len in sizes {
                let input = pattern(len);
                let mut oracle256 = <Hmac<Sha256> as Mac>::new_from_slice(&key).unwrap();
                let mut oracle512 = <Hmac<Sha512> as Mac>::new_from_slice(&key).unwrap();
                oracle256.update(&input);
                oracle512.update(&input);
                let expected256 = oracle256.finalize().into_bytes();
                let expected512 = oracle512.finalize().into_bytes();
                assert_eq!(sum256(&key, &input)[..], expected256[..]);
                assert_eq!(sum512(&key, &input)[..], expected512[..]);
                for chunk in [1, 3, 31, 63, 64, 65, 127, 128, 129, 1024] {
                    let mut s256 = Hmac256::decode(&initial256);
                    let mut s512 = Hmac512::decode(&initial512);
                    for piece in input.chunks(chunk) {
                        s256.update(piece);
                        s512.update(piece);
                        s256 = Hmac256::decode(&s256.encode());
                        s512 = Hmac512::decode(&s512.encode());
                        s256.update(b"");
                        s512.update(b"");
                    }
                    assert_eq!(s256.clone().sum()[..], expected256[..]);
                    assert_eq!(s512.clone().sum()[..], expected512[..]);
                    // Finalization does not alter the retained serialized state.
                    assert_eq!(Hmac256::decode(&s256.encode()).sum()[..], expected256[..]);
                    assert_eq!(Hmac512::decode(&s512.encode()).sum()[..], expected512[..]);
                }
            }
        }
    }
    #[test]
    fn guarded_unaligned_pointer_abi_and_input_immutability() {
        for key_len in [0, 64, 129] {
            for len in [0, 1, 55, 56, 63, 64, 111, 112, 127, 128, 129, 4097] {
                let mut key = vec![0xa5];
                key.extend(pattern(key_len));
                key.push(0x5a);
                let mut input = vec![0xa5];
                input.extend(pattern(len));
                input.push(0x5a);
                let original_key = key.clone();
                let original_input = input.clone();
                macro_rules! check {
                    ($ctx:ident,$size:expr,$tag:expr,$init:ident,$update:ident,$sum:ident,$prepared:ident,$digest:ident) => {{
                        let mut initial = vec![0xa5; $size + 2];
                        let mut current = vec![0xa5; $size + 2];
                        let mut output = vec![0xa5; $tag + 2];
                        unsafe {
                            $init(key.as_ptr().add(1), key_len, initial.as_mut_ptr().add(1));
                            $update(
                                initial.as_ptr().add(1),
                                $size,
                                input.as_ptr().add(1),
                                len,
                                current.as_mut_ptr().add(1),
                            );
                            $sum(current.as_ptr().add(1), $size, output.as_mut_ptr().add(1));
                        }
                        let expected = output.clone();
                        unsafe {
                            $prepared(
                                initial.as_ptr().add(1),
                                $size,
                                input.as_ptr().add(1),
                                len,
                                output.as_mut_ptr().add(1),
                            )
                        };
                        assert_eq!(output, expected);
                        unsafe {
                            $digest(
                                key.as_ptr().add(1),
                                key_len,
                                input.as_ptr().add(1),
                                len,
                                output.as_mut_ptr().add(1),
                            )
                        };
                        assert_eq!(output, expected);
                        assert_eq!(
                            initial[1..$size + 1],
                            $ctx::new(&key[1..key_len + 1]).encode()
                        );
                        for buffer in [&initial, &current, &output] {
                            assert_eq!(buffer[0], 0xa5);
                            assert_eq!(*buffer.last().unwrap(), 0xa5);
                        }
                    }};
                }
                check!(
                    Hmac256,
                    136,
                    32,
                    hmac_sha256_init,
                    hmac_sha256_update,
                    hmac_sha256_sum,
                    hmac_sha256_prepared,
                    hmac_sha256
                );
                check!(
                    Hmac512,
                    272,
                    64,
                    hmac_sha512_init,
                    hmac_sha512_update,
                    hmac_sha512_sum,
                    hmac_sha512_prepared,
                    hmac_sha512
                );
                assert_eq!(input, original_input);
                assert_eq!(key, original_key);
            }
        }
    }
    #[test]
    fn canonical_state_suffix_validation() {
        // Exercise every partial-block length and every invalid suffix byte,
        // including short remainders and all unaligned word boundaries.
        macro_rules! check {
            ($ctx:ident, $block:expr, $offset:expr) => {
                for used in 0..$block {
                    let mut context = $ctx::new(b"key");
                    context.update(&pattern(used));
                    let canonical = context.encode();
                    assert_eq!($ctx::decode(&canonical).encode(), canonical);
                    for invalid in used..$block {
                        let mut malformed = canonical;
                        malformed[$offset + invalid] = 0x80;
                        assert!(std::panic::catch_unwind(|| $ctx::decode(&malformed)).is_err());
                    }
                }
            };
        }
        check!(Hmac256, 64, 72);
        check!(Hmac512, 128, 144);
    }
    #[test]
    fn malformed_and_overflow_states_rejected() {
        assert!(std::panic::catch_unwind(|| Hmac256::decode(&[])).is_err());
        assert!(std::panic::catch_unwind(|| Hmac512::decode(&[])).is_err());
        for marker in [0, 63, u64::MAX / 8 + 1] {
            let mut state = Hmac256::new(b"key").encode();
            state[64..72].copy_from_slice(&marker.to_be_bytes());
            assert!(std::panic::catch_unwind(|| Hmac256::decode(&state)).is_err());
        }
        for marker in [0, 127, u128::MAX / 8 + 1] {
            let mut state = Hmac512::new(b"key").encode();
            state[128..144].copy_from_slice(&marker.to_be_bytes());
            assert!(std::panic::catch_unwind(|| Hmac512::decode(&state)).is_err());
        }
        let mut state = Hmac256::new(b"key").encode();
        state[135] = 1;
        assert!(std::panic::catch_unwind(|| Hmac256::decode(&state)).is_err());
        let mut state = Hmac512::new(b"key").encode();
        state[271] = 1;
        assert!(std::panic::catch_unwind(|| Hmac512::decode(&state)).is_err());
        assert!(
            std::panic::catch_unwind(|| {
                let mut s = Hmac256::new(b"key");
                s.count = u64::MAX / 8;
                s.update(&[1]);
            })
            .is_err()
        );
        assert!(
            std::panic::catch_unwind(|| {
                let mut s = Hmac512::new(b"key");
                s.count = u128::MAX / 8;
                s.update(&[1]);
            })
            .is_err()
        );
    }
}
