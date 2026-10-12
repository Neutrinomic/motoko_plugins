//! Allocation-free RIPEMD-160 using RustCrypto's portable compression kernel.
//! All retained state is a canonical, immutable 104-byte Motoko Blob. No raw
//! pointers, heap allocations or runtime globals survive a call.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

use ripemd::{
    Digest, Ripemd160,
    block_api::Ripemd160Core,
    digest::{
        block_api::{Buffer, CoreProxy},
        common::hazmat::{SerializableState, SerializedState},
    },
};

const STATE_SIZE: usize = 104;
const MAX_BYTES: u64 = u64::MAX / 8;
const IV: [u8; 20] = [
    0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10,
    0xf0, 0xe1, 0xd2, 0xc3,
];

// Plugin encoding (independent of Rust's in-memory layout): R160, reserved4,
// total_bytes LE64, chaining_words LE32[5], reserved4, zero-padded tail64.
// The pinned RustCrypto 0.2.0 core serialization is chaining_words20 followed
// by block_count8. Buffer contents use its public constructor/accessor, so no
// second canonical-tail scan or whole-hasher serialization is necessary.
// Translate explicitly; never transmute objects or expose padding bytes.
fn validate(state: &[u8]) -> Option<(u64, usize)> {
    if state.len() != STATE_SIZE
        || &state[..4] != b"R160"
        || state[4..8] != [0; 4]
        || state[36..40] != [0; 4]
    {
        return None;
    }
    let total = u64::from_le_bytes(state[8..16].try_into().ok()?);
    let used = (total % 64) as usize;
    if total > MAX_BYTES
        || state[40 + used..].iter().any(|b| *b != 0)
        || (total < 64 && state[16..36] != IV)
    {
        return None;
    }
    Some((total, used))
}

fn decode_validated(state: &[u8], total: u64, used: usize) -> Option<Ripemd160> {
    let mut serialized = SerializedState::<Ripemd160Core>::default();
    serialized[..20].copy_from_slice(&state[16..36]);
    serialized[20..28].copy_from_slice(&(total / 64).to_le_bytes());
    let core = Ripemd160Core::deserialize(&serialized).ok()?;
    let buffer = Buffer::<Ripemd160Core>::new(&state[40..40 + used]);
    Some(Ripemd160::compose(core, buffer))
}

fn decode(state: &[u8]) -> Option<(Ripemd160, u64)> {
    let (total, used) = validate(state)?;
    Some((decode_validated(state, total, used)?, total))
}

fn encode_owned(hash: Ripemd160, total: u64) -> [u8; STATE_SIZE] {
    let (core, buffer) = hash.decompose();
    let serialized = core.serialize();
    let used = (total % 64) as usize;
    let mut state = [0; STATE_SIZE];
    state[..4].copy_from_slice(b"R160");
    state[8..16].copy_from_slice(&total.to_le_bytes());
    state[16..36].copy_from_slice(&serialized[..20]);
    state[40..40 + used].copy_from_slice(buffer.get_data());
    state
}

#[cfg(test)]
fn encode(hash: &Ripemd160, total: u64) -> [u8; STATE_SIZE] {
    encode_owned(hash.clone(), total)
}

fn update(state: &[u8], input: &[u8]) -> Option<[u8; STATE_SIZE]> {
    let (old_total, used) = validate(state)?;
    let total = old_total.checked_add(u64::try_from(input.len()).ok()?)?;
    if total > MAX_BYTES {
        return None;
    }
    if input.len() < 64 - used {
        let mut next: [u8; STATE_SIZE] = state.try_into().ok()?;
        next[8..16].copy_from_slice(&total.to_le_bytes());
        next[40 + used..40 + used + input.len()].copy_from_slice(input);
        return Some(next);
    }
    let mut hash = decode_validated(state, old_total, used)?;
    hash.update(input);
    Some(encode_owned(hash, total))
}

fn finalize(state: &[u8]) -> Option<[u8; 20]> {
    let (hash, _) = decode(state)?;
    Some(hash.finalize().into())
}

// HASH160 feeds a 32-byte SHA-256 digest. Exposing this fixed length to LLVM
// removes the generic block-buffer length checks and padding decisions while
// retaining the audited RustCrypto compression function.
#[inline(never)]
unsafe fn digest32(input: *const u8, output: *mut u8) {
    let input = unsafe { core::slice::from_raw_parts(input, 32) };
    let digest = Ripemd160::digest(input);
    unsafe { core::ptr::copy_nonoverlapping(digest.as_ptr(), output, 20) };
}

#[inline(never)]
unsafe fn digest_general(input: *const u8, len: usize, output: *mut u8) {
    let input = unsafe { core::slice::from_raw_parts(input, len) };
    let digest = Ripemd160::digest(input);
    unsafe { core::ptr::copy_nonoverlapping(digest.as_ptr(), output, 20) };
}

/// # Safety
/// `input` addresses `len` initialized bytes and `output` addresses 20 writable
/// bytes, disjoint from input. The caller must prevent GC during this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ripemd160_digest(input: *const u8, len: usize, output: *mut u8) {
    if len == 0 {
        // Immediate word stores avoid both hashing and a static memory load.
        unsafe {
            output
                .cast::<u64>()
                .write_unaligned(0x54fce9c5a585119cu64.to_le());
            output
                .add(8)
                .cast::<u64>()
                .write_unaligned(0x48f5e87e97082861u64.to_le());
            output
                .add(16)
                .cast::<u32>()
                .write_unaligned(0x318d25b2u32.to_le());
        }
    } else if len == 32 {
        unsafe { digest32(input, output) };
    } else {
        unsafe { digest_general(input, len, output) };
    }
}

/// # Safety
/// `output` addresses STATE_SIZE writable bytes and no GC runs during this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ripemd160_init(output: *mut u8) {
    // Immediate unaligned stores retain the baseline's compact initialization
    // without serializing a hasher or loading constants from linear memory.
    unsafe {
        output.cast::<u64>().write_unaligned(0x30363152u64.to_le());
        output.add(8).cast::<u64>().write_unaligned(0);
        output
            .add(16)
            .cast::<u64>()
            .write_unaligned(0xefcdab8967452301u64.to_le());
        output
            .add(24)
            .cast::<u64>()
            .write_unaligned(0x1032547698badcfeu64.to_le());
        output
            .add(32)
            .cast::<u32>()
            .write_unaligned(0xc3d2e1f0u32.to_le());
        core::ptr::write_bytes(output.add(36), 0, STATE_SIZE - 36);
    }
}

/// # Safety
/// Input ranges are initialized readable memory; output is a fresh, disjoint
/// STATE_SIZE-byte buffer. No pointers are retained and no GC may run here.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ripemd160_update(
    state: *const u8,
    state_len: usize,
    input: *const u8,
    len: usize,
    output: *mut u8,
) -> usize {
    let state = unsafe { core::slice::from_raw_parts(state, state_len) };
    let input = unsafe { core::slice::from_raw_parts(input, len) };
    match update(state, input) {
        Some(next) => {
            unsafe { core::ptr::copy_nonoverlapping(next.as_ptr(), output, STATE_SIZE) };
            1
        }
        None => {
            unsafe { core::ptr::write_bytes(output, 0, STATE_SIZE) };
            0
        }
    }
}

/// # Safety
/// `state` addresses state_len initialized bytes; output is a fresh, disjoint
/// 20-byte buffer. The caller must prevent GC during this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ripemd160_finalize(
    state: *const u8,
    state_len: usize,
    output: *mut u8,
) -> usize {
    let state = unsafe { core::slice::from_raw_parts(state, state_len) };
    match finalize(state) {
        Some(digest) => {
            unsafe { core::ptr::copy_nonoverlapping(digest.as_ptr(), output, 20) };
            1
        }
        None => {
            unsafe { core::ptr::write_bytes(output, 0, 20) };
            0
        }
    }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn check(input: &[u8], expected: &str) {
        // Exercise the exported ABI with deliberately unaligned addresses,
        // guard bytes and a saved input copy.
        let mut borrowed = vec![0xa5];
        borrowed.extend_from_slice(input);
        borrowed.push(0x5a);
        let saved = borrowed.clone();
        let mut output = [0xa5; 22];
        unsafe {
            ripemd160_digest(
                borrowed.as_ptr().add(1),
                input.len(),
                output.as_mut_ptr().add(1),
            )
        };
        let actual: String = output[1..21].iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(actual, expected);
        assert_eq!(output[0], 0xa5);
        assert_eq!(output[21], 0xa5);
        assert_eq!(borrowed, saved);

        let initial = encode(&Ripemd160::new(), 0);
        for chunk_size in [1, 7, 55, 56, 63, 64, 65, 257] {
            let mut state = initial;
            for chunk in input.chunks(chunk_size) {
                state = update(&state, chunk).unwrap();
                assert_eq!(update(&state, b"").unwrap(), state);
            }
            assert_eq!(finalize(&state).unwrap().as_slice(), &output[1..21]);
            assert_eq!(finalize(&state), finalize(&state));
        }
    }

    #[test]
    fn official_vectors() {
        // Original RIPEMD-160 authors' published known answers:
        // https://homes.esat.kuleuven.be/~bosselae/ripemd160.html
        for (input, expected) in [
            ("", "9c1185a5c5e9fc54612808977ee8f548b2258d31"),
            ("a", "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe"),
            ("abc", "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc"),
            ("message digest", "5d0689ef49d2fae572b881b123a85ffa21595f36"),
            (
                "abcdefghijklmnopqrstuvwxyz",
                "f71c27109c692c1b56bbdceb5b9d2865b3708dbc",
            ),
            (
                "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
                "12a053384a9c0c88e405a06c27dcf49ada62eb2b",
            ),
            (
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
                "b0e20b6e3116640286ed3a87a5713079b21f5189",
            ),
            (
                "12345678901234567890123456789012345678901234567890123456789012345678901234567890",
                "9b752e45573d4b39f4dbd3323cab82bf63326bfb",
            ),
        ] {
            check(input.as_bytes(), expected);
        }
    }

    #[test]
    fn million_a() {
        // Avoid a million single-byte snapshot serializations in this vector;
        // byte-wise partitioning is exercised on the smaller boundary cases.
        let input = vec![b'a'; 1_000_000];
        let expected = "52783243c1697bdbe16d37f97f68f08325dc1528";
        let output = Ripemd160::digest(&input);
        assert_eq!(
            output
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect::<String>(),
            expected
        );
        let mut state = encode(&Ripemd160::new(), 0);
        for chunk in input.chunks(4093) {
            state = update(&state, chunk).unwrap();
        }
        assert_eq!(finalize(&state).unwrap().as_slice(), output.as_slice());
    }

    #[test]
    fn malformed_state_and_length_limit() {
        let initial = encode(&Ripemd160::new(), 0);
        for size in [0, 1, 20, 64, 103, 105, 4096] {
            let invalid = vec![0; size];
            assert!(update(&invalid, b"abc").is_none());
            assert!(finalize(&invalid).is_none());
        }
        // Every byte in the initial state is canonical, including its IV and
        // unused tail. Length bytes are tested separately (some values valid).
        for offset in (0..8).chain(16..STATE_SIZE) {
            let mut invalid = initial;
            invalid[offset] ^= 1;
            assert!(update(&invalid, b"").is_none(), "offset {offset}");
            assert!(finalize(&invalid).is_none(), "offset {offset}");
        }
        let mut overlimit = initial;
        overlimit[8..16].copy_from_slice(&(MAX_BYTES + 1).to_le_bytes());
        assert!(update(&overlimit, b"").is_none());
        assert!(finalize(&overlimit).is_none());

        // Synthetic structurally valid states exercise arithmetic without
        // allocating a huge input. Chaining words are not authenticated.
        let mut limit = initial;
        limit[8..16].copy_from_slice(&MAX_BYTES.to_le_bytes());
        assert!(finalize(&limit).is_some());
        assert_eq!(update(&limit, b"").unwrap(), limit);
        assert!(update(&limit, b"a").is_none());
        let mut near_limit = initial;
        near_limit[8..16].copy_from_slice(&(MAX_BYTES - 1).to_le_bytes());
        assert!(update(&near_limit, b"a").is_some());
        assert!(update(&near_limit, b"ab").is_none());
    }

    #[test]
    fn state_pointer_abi_and_branching() {
        let mut storage = [0xa5; STATE_SIZE + 2];
        unsafe { ripemd160_init(storage.as_mut_ptr().add(1)) };
        assert_eq!(storage[0], 0xa5);
        assert_eq!(storage[STATE_SIZE + 1], 0xa5);
        let original = storage;
        let mut next = [0xa5; STATE_SIZE + 2];
        let mut digest = [0xa5; 22];
        unsafe {
            assert_eq!(
                ripemd160_update(
                    storage.as_ptr().add(1),
                    STATE_SIZE,
                    b"abc".as_ptr(),
                    3,
                    next.as_mut_ptr().add(1)
                ),
                1
            );
            assert_eq!(
                ripemd160_finalize(next.as_ptr().add(1), STATE_SIZE, digest.as_mut_ptr().add(1)),
                1
            );
        }
        assert_eq!(&digest[1..21], Ripemd160::digest(b"abc").as_slice());
        assert_eq!(storage, original);
        assert_eq!(next[0], 0xa5);
        assert_eq!(next[STATE_SIZE + 1], 0xa5);
        assert_eq!(digest[0], 0xa5);
        assert_eq!(digest[21], 0xa5);
        let branch = update(&next[1..STATE_SIZE + 1], b"def").unwrap();
        assert_eq!(
            finalize(&branch).unwrap().as_slice(),
            Ripemd160::digest(b"abcdef").as_slice()
        );
        assert_eq!(
            finalize(&next[1..STATE_SIZE + 1]).unwrap().as_slice(),
            &digest[1..21]
        );

        // Rejected calls initialize all output bytes and preserve guards.
        unsafe {
            assert_eq!(
                ripemd160_update(
                    b"bad".as_ptr(),
                    3,
                    b"".as_ptr(),
                    0,
                    next.as_mut_ptr().add(1)
                ),
                0
            );
            assert_eq!(
                ripemd160_finalize(b"bad".as_ptr(), 3, digest.as_mut_ptr().add(1)),
                0
            );
        }
        assert_eq!(&next[1..STATE_SIZE + 1], &[0; STATE_SIZE]);
        assert_eq!(&digest[1..21], &[0; 20]);
        assert_eq!((next[0], next[STATE_SIZE + 1]), (0xa5, 0xa5));
        assert_eq!((digest[0], digest[21]), (0xa5, 0xa5));
    }
    #[test]
    fn binary_padding_and_block_boundaries() {
        // Independent Python hashlib/OpenSSL known answers.
        for (length, expected) in [
            (0, "9c1185a5c5e9fc54612808977ee8f548b2258d31"),
            (1, "dd6098c316993685cf244f6f932704e863fddffc"),
            (2, "ac292023e7c678d01bbed001ed48332d310b3019"),
            (31, "3e4c65e1e14f63351516fc0eb7895c59547b65f7"),
            (32, "6e155df0e6ad32f647dc1789d6e1bf4c9cebe273"),
            (33, "32b4de732e151d4fdecfb14bbcaf5813109799eb"),
            (54, "b990ab6fe3bc16ce6901600acaa84ecbf15bea65"),
            (55, "bc83805ce4ab83ba49dd28a2a11ae3b31cefa581"),
            (56, "194a11d6cc36daadd30c1f4296b9b298dba48a28"),
            (57, "865a584c3b0a1f4180f4b4a8e2b35701c3018c2d"),
            (63, "90f8a7c9f4c0afc80c41589f26d15cc53e129a47"),
            (64, "6a334adae09ccc0029fb1a95de03ad8b3b61ef0e"),
            (65, "dd543682402372fb64e90d0a0b766e8d4e0e4f8e"),
            (119, "c56bc4f0a79b0a9fa8323c7cf0d877cd392d82a0"),
            (120, "d80a7c354ae09536ace75d697dac6a36a9e09819"),
            (127, "828f60e3bee56738190dfe7a8a86b66f87bc4a61"),
            (128, "5d50e41e7a8566518be20d9e528b791f9cfa84ba"),
            (129, "269dc1843a99afb6f683b414e1f4d1c78a9ed3ac"),
            (255, "55b19c7fd04bb43d43bdc5ad8e7b3a5a34cdfffa"),
            (256, "df1deaa70c17a90b5eec6dd0b8ffe4de9c2e08cb"),
            (257, "acfba49b2dc78db842fd636ecb8fb488e2826f42"),
            (1023, "dbe8437e5e5c065005c31870b480476cdb563044"),
            (1024, "35a60c3f565bc6d7f808b58b39efec28e603f5e4"),
            (1025, "269b75ed5ff0e9980ea18059f424f93ef06f80a9"),
            (4096, "d03599ed12c05e643ca552f24ae8e375015a2b60"),
            (65537, "56606eb77b22ee49a16b2a8304c76d39a1a3cfdf"),
        ] {
            let input: Vec<u8> = (0..length).map(|i| (i * 131 + 17) as u8).collect();
            check(&input, expected);
        }
    }
}
