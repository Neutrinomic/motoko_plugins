//! Portable upstream BLAKE3 with immutable, explicitly encoded Motoko state.
//! No input pointer or native object representation survives a call.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

use blake3::hazmat::{self, HasherExt, Mode};

const STATE_LEN: usize = 2816;
const MAX_OUTPUT: usize = 16 * 1024 * 1024;
const MAX_CHUNKS: u64 = (1 << 54) - 1;
// Official BLAKE3 empty-input digest. Avoid compression for this common base
// case while leaving all nonempty inputs on the upstream portable kernel.
const EMPTY_DIGEST: [u8; 32] = [
    0xaf, 0x13, 0x49, 0xb9, 0xf5, 0xf9, 0xa1, 0xa6, 0xa0, 0x40, 0x4d, 0xea, 0x36, 0xdc, 0xc9, 0x49,
    0x9b, 0xcb, 0x25, 0xc9, 0xad, 0xc1, 0x12, 0xb7, 0xcc, 0x9a, 0x93, 0xca, 0xe4, 0x1f, 0x32, 0x62,
];
const INVALID_KEY: u64 = 1;
const INVALID_STATE: u64 = 2;
const OUTPUT_TOO_LARGE: u64 = 3;
const INPUT_TOO_LONG: u64 = 4;
const INVALID_SEEK: u64 = 5;

type Result<T> = core::result::Result<T, u64>;

// Canonical padding validation uses word loads without requiring alignment.
// The final short tail is still checked byte-for-byte.
fn all_zero(bytes: &[u8]) -> bool {
    let mut words = bytes.chunks_exact(8);
    if words
        .by_ref()
        .any(|word| u64::from_ne_bytes(word.try_into().unwrap()) != 0)
    {
        return false;
    }
    words.remainder().iter().all(|&byte| byte == 0)
}

struct State {
    mode: u8,
    key: [u8; 32],
    chunks: u64,
    pending: [u8; 1024],
    pending_len: usize,
    stack: [[u8; 32]; 54],
    stack_len: usize,
}

impl State {
    fn new(mode: u8, key: [u8; 32]) -> Self {
        Self {
            mode,
            key,
            chunks: 0,
            pending: [0; 1024],
            pending_len: 0,
            stack: [[0; 32]; 54],
            stack_len: 0,
        }
    }

    fn decode(bytes: &[u8]) -> Result<Self> {
        let view = StateView::decode(bytes)?;
        let mut state = Self::new(view.mode, *view.key);
        state.chunks = view.chunks;
        state.pending_len = view.pending.len();
        state.pending[..state.pending_len].copy_from_slice(view.pending);
        state.stack_len = view.stack.len();
        state.stack[..state.stack_len].copy_from_slice(view.stack);
        Ok(state)
    }

    // `blake3_run` initializes the fresh output entirely to zero before run.
    // Write the active fields once; unused bytes retain that canonical padding.
    fn encode(&self, out: &mut [u8]) {
        out[..4].copy_from_slice(b"B3S1");
        out[4] = self.mode;
        out[8..40].copy_from_slice(&self.key);
        out[40..48].copy_from_slice(&self.chunks.to_le_bytes());
        out[48..50].copy_from_slice(&(self.pending_len as u16).to_le_bytes());
        out[50] = self.stack_len as u8;
        out[64..64 + self.pending_len].copy_from_slice(&self.pending[..self.pending_len]);
        for (i, cv) in self.stack[..self.stack_len].iter().enumerate() {
            out[1088 + i * 32..1120 + i * 32].copy_from_slice(cv);
        }
    }

    fn hasher(&self) -> blake3::Hasher {
        match self.mode {
            16 => blake3::Hasher::new_keyed(&self.key),
            64 => blake3::Hasher::new_from_context_key(&self.key),
            _ => blake3::Hasher::new(),
        }
    }

    fn mode(&self) -> Mode<'_> {
        match self.mode {
            16 => Mode::KeyedHash(&self.key),
            64 => Mode::DeriveKeyMaterial(&self.key),
            _ => Mode::Hash,
        }
    }

    fn push_chunk(&mut self) {
        let mut hasher = self.hasher();
        hasher
            .set_input_offset(self.chunks * 1024)
            .update(&self.pending);
        let mut cv = hasher.finalize_non_root();
        self.chunks += 1;
        let mut total = self.chunks;
        while total & 1 == 0 {
            self.stack_len -= 1;
            cv = hazmat::merge_subtrees_non_root(&self.stack[self.stack_len], &cv, self.mode());
            total >>= 1;
        }
        self.stack[self.stack_len] = cv;
        self.stack_len += 1;
        self.pending_len = 0;
    }

    fn update(&mut self, mut input: &[u8]) -> Result<()> {
        let total = self.chunks * 1024 + self.pending_len as u64;
        total
            .checked_add(input.len() as u64)
            .ok_or(INPUT_TOO_LONG)?;
        while !input.is_empty() {
            // Keep a complete last chunk pending: its root flag is not known
            // until another byte arrives or the user finalizes the state.
            if self.pending_len == 1024 {
                self.push_chunk();
            }
            let take = input.len().min(1024 - self.pending_len);
            self.pending[self.pending_len..self.pending_len + take].copy_from_slice(&input[..take]);
            self.pending_len += take;
            input = &input[take..];
        }
        Ok(())
    }

    #[cfg(test)]
    fn reader(&self) -> blake3::OutputReader {
        StateView {
            mode: self.mode,
            key: &self.key,
            chunks: self.chunks,
            pending: &self.pending[..self.pending_len],
            stack: &self.stack[..self.stack_len],
        }
        .reader()
    }
}

// Validation does not materialize the large writable State used for updates.
// All borrowed slices point into the caller's immutable managed blob, and live
// only for this synchronous, no-safepoint runtime call.
struct StateView<'a> {
    mode: u8,
    key: &'a [u8; 32],
    chunks: u64,
    pending: &'a [u8],
    stack: &'a [[u8; 32]],
}

impl<'a> StateView<'a> {
    fn decode(bytes: &'a [u8]) -> Result<Self> {
        if bytes.len() != STATE_LEN || &bytes[..4] != b"B3S1" {
            return Err(INVALID_STATE);
        }
        let mode = bytes[4];
        let key: &[u8; 32] = bytes[8..40].try_into().unwrap();
        let chunks = u64::from_le_bytes(bytes[40..48].try_into().unwrap());
        let pending_len = u16::from_le_bytes(bytes[48..50].try_into().unwrap()) as usize;
        let stack_len = bytes[50] as usize;
        if !matches!(mode, 0 | 16 | 64)
            || !all_zero(&bytes[5..8])
            || !all_zero(&bytes[51..64])
            || (mode == 0 && *key != [0; 32])
            || chunks > MAX_CHUNKS
            || pending_len > 1024
            || stack_len != chunks.count_ones() as usize
            || (chunks != 0 && pending_len == 0)
            || chunks
                .checked_mul(1024)
                .and_then(|n| n.checked_add(pending_len as u64))
                .is_none()
        {
            return Err(INVALID_STATE);
        }
        if !all_zero(&bytes[64 + pending_len..1088]) || !all_zero(&bytes[1088 + stack_len * 32..]) {
            return Err(INVALID_STATE);
        }
        Ok(Self {
            mode,
            key,
            chunks,
            pending: &bytes[64..64 + pending_len],
            // The validated stack length bounds this slice to 54 values.
            stack: bytes[1088..1088 + stack_len * 32].as_chunks::<32>().0,
        })
    }

    fn hasher(&self) -> blake3::Hasher {
        match self.mode {
            16 => blake3::Hasher::new_keyed(self.key),
            64 => blake3::Hasher::new_from_context_key(self.key),
            _ => blake3::Hasher::new(),
        }
    }

    fn mode(&self) -> Mode<'_> {
        match self.mode {
            16 => Mode::KeyedHash(self.key),
            64 => Mode::DeriveKeyMaterial(self.key),
            _ => Mode::Hash,
        }
    }

    fn reader(&self) -> blake3::OutputReader {
        let mut chunk = self.hasher();
        chunk
            .set_input_offset(self.chunks * 1024)
            .update(self.pending);
        if self.stack.is_empty() {
            return chunk.finalize_xof();
        }
        let mut cv = chunk.finalize_non_root();
        for left in self.stack[1..].iter().rev() {
            cv = hazmat::merge_subtrees_non_root(left, &cv, self.mode());
        }
        hazmat::merge_subtrees_root_xof(&self.stack[0], &cv, self.mode())
    }

    fn fill(&self, seek: u64, out: &mut [u8]) {
        if out.is_empty() {
            return;
        }
        let mut reader = self.reader();
        reader.set_position(seek);
        reader.fill(out);
    }
}

fn check_output(seek: u64, length: usize) -> Result<()> {
    if length > MAX_OUTPUT {
        return Err(OUTPUT_TOO_LARGE);
    }
    seek.checked_add(length as u64).ok_or(INVALID_SEEK)?;
    Ok(())
}

fn keyed(key: &[u8]) -> Result<[u8; 32]> {
    key.try_into().map_err(|_| INVALID_KEY)
}

fn context_key(context: &[u8]) -> Result<[u8; 32]> {
    let context = core::str::from_utf8(context).map_err(|_| INVALID_STATE)?;
    Ok(hazmat::hash_derive_key_context(context))
}

fn run(op: u64, a: &[u8], b: &[u8], seek: u64, out: &mut [u8]) -> Result<()> {
    match op {
        3 => {
            check_output(seek, out.len())?;
            let mut hasher = blake3::Hasher::new();
            hasher.update(a);
            let mut reader = hasher.finalize_xof();
            reader.set_position(seek);
            reader.fill(out);
        }
        4 => State::new(0, [0; 32]).encode(out),
        5 => State::new(16, keyed(a)?).encode(out),
        6 => State::new(64, context_key(a)?).encode(out),
        7 => {
            let mut state = State::decode(a)?;
            state.update(b)?;
            state.encode(out);
        }
        8 => {
            check_output(seek, out.len())?;
            // Check every canonical field before the empty-output path.
            let state = StateView::decode(a)?;
            state.fill(seek, out);
        }
        _ => return Err(INVALID_STATE),
    }
    Ok(())
}

/// Hash a borrowed input directly into the fresh 32-byte payload.
/// # Safety
/// Input is readable for `len` bytes and output is disjoint and writable for
/// 32 bytes. Neither pointer may cross a GC safepoint.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn blake3_digest(input: *const u8, len: usize, output: *mut u8) {
    let digest = if len == 0 {
        EMPTY_DIGEST
    } else {
        let input = unsafe { core::slice::from_raw_parts(input, len) };
        *blake3::hash(input).as_bytes()
    };
    // Every byte is initialized by the copy; no mutable reference to the fresh
    // uninitialized Motoko payload is formed and no preliminary clear is needed.
    unsafe { core::ptr::copy_nonoverlapping(digest.as_ptr(), output, 32) };
}

/// # Safety
/// Key/data slices are readable, output is disjoint and writable for 32 bytes,
/// and no pointer is invalidated by a GC safepoint during the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn blake3_keyed_hash(
    key: *const u8,
    key_len: usize,
    data: *const u8,
    len: usize,
    output: *mut u8,
) -> u64 {
    if key_len != 32 {
        unsafe { output.write_bytes(0, 32) };
        return INVALID_KEY;
    }
    let key = unsafe { &*key.cast::<[u8; 32]>() };
    let input = if len == 0 {
        &[]
    } else {
        unsafe { core::slice::from_raw_parts(data, len) }
    };
    let digest = blake3::keyed_hash(key, input);
    unsafe { core::ptr::copy_nonoverlapping(digest.as_bytes().as_ptr(), output, 32) };
    0
}

/// # Safety
/// Context/data slices are readable, output is disjoint and writable for 32
/// bytes, and no pointer crosses a GC safepoint during the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn blake3_derive_key(
    context: *const u8,
    context_len: usize,
    data: *const u8,
    len: usize,
    output: *mut u8,
) -> u64 {
    let context = if context_len == 0 {
        &[]
    } else {
        unsafe { core::slice::from_raw_parts(context, context_len) }
    };
    let Ok(context) = core::str::from_utf8(context) else {
        unsafe { output.write_bytes(0, 32) };
        return INVALID_STATE;
    };
    let input = if len == 0 {
        &[]
    } else {
        unsafe { core::slice::from_raw_parts(data, len) }
    };
    // The complete-message API avoids constructing an incremental Hasher.
    let digest = blake3::derive_key(context, input);
    unsafe { core::ptr::copy_nonoverlapping(digest.as_ptr(), output, 32) };
    0
}

/// # Safety
/// Inputs are readable for their lengths and output is writable for its length,
/// disjoint from inputs, and sized for the selected operation (32 bytes, 2816
/// bytes, or the requested XOF length). The compiler enforces the output cap
/// before allocation. No borrowed pointer crosses a GC safepoint.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn blake3_run(
    op: u64,
    a: *const u8,
    a_len: usize,
    b: *const u8,
    b_len: usize,
    seek: u64,
    output: *mut u8,
    output_len: usize,
) -> u64 {
    let a = if a_len == 0 {
        &[]
    } else {
        unsafe { core::slice::from_raw_parts(a, a_len) }
    };
    let b = if b_len == 0 {
        &[]
    } else {
        unsafe { core::slice::from_raw_parts(b, b_len) }
    };
    // Initialize the fresh managed payload before creating a Rust reference.
    unsafe { output.write_bytes(0, output_len) };
    let out = if output_len == 0 {
        &mut []
    } else {
        unsafe { core::slice::from_raw_parts_mut(output, output_len) }
    };
    match run(op, a, b, seek, out) {
        Ok(()) => 0,
        Err(code) => code,
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

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }
    fn pattern(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i % 251) as u8).collect()
    }
    fn call(op: u64, a: &[u8], b: &[u8], seek: u64, length: usize) -> Result<Vec<u8>> {
        let mut a_guard = vec![0xa5];
        a_guard.extend_from_slice(a);
        a_guard.push(0x5a);
        let mut b_guard = vec![0x6b];
        b_guard.extend_from_slice(b);
        b_guard.push(0xb6);
        let a_saved = a_guard.clone();
        let b_saved = b_guard.clone();
        let mut out = vec![0x7c; length + 2];
        let status = unsafe {
            match op {
                0 => {
                    blake3_digest(a_guard.as_ptr().add(1), a.len(), out.as_mut_ptr().add(1));
                    0
                }
                1 => blake3_keyed_hash(
                    a_guard.as_ptr().add(1),
                    a.len(),
                    b_guard.as_ptr().add(1),
                    b.len(),
                    out.as_mut_ptr().add(1),
                ),
                2 => blake3_derive_key(
                    a_guard.as_ptr().add(1),
                    a.len(),
                    b_guard.as_ptr().add(1),
                    b.len(),
                    out.as_mut_ptr().add(1),
                ),
                _ => blake3_run(
                    op,
                    a_guard.as_ptr().add(1),
                    a.len(),
                    b_guard.as_ptr().add(1),
                    b.len(),
                    seek,
                    out.as_mut_ptr().add(1),
                    length,
                ),
            }
        };
        assert_eq!(a_guard, a_saved);
        assert_eq!(b_guard, b_saved);
        assert_eq!(out[0], 0x7c);
        assert_eq!(out[length + 1], 0x7c);
        if status == 0 {
            Ok(out[1..length + 1].to_vec())
        } else {
            Err(status)
        }
    }

    #[test]
    fn official_vectors_all_modes_and_xof_seek() {
        // Literal answers from upstream test_vectors/test_vectors.json.
        let key = b"whats the Elvish word for friend";
        let context = b"BLAKE3 2019-12-27 16:29:52 test vectors context";
        for line in include_str!("../tests/official-vectors.txt").lines() {
            let fields: Vec<&str> = line.split_whitespace().collect();
            let input = pattern(fields[0].parse().unwrap());
            for (mode, expected) in fields[1..].iter().enumerate() {
                let initial = match mode {
                    0 => call(4, &[], &[], 0, STATE_LEN).unwrap(),
                    1 => call(5, key, &[], 0, STATE_LEN).unwrap(),
                    _ => call(6, context, &[], 0, STATE_LEN).unwrap(),
                };
                let one_shot = match mode {
                    0 => call(0, &input, &[], 0, 32),
                    1 => call(1, key, &input, 0, 32),
                    _ => call(2, context, &input, 0, 32),
                }
                .unwrap();
                assert_eq!(hex(&one_shot), &expected[..64]);
                for chunk_size in [1, 63, 64, 65, 1023, 1024, 1025, 4096] {
                    let mut state = initial.clone();
                    for chunk in input.chunks(chunk_size) {
                        state = call(7, &state, chunk, 0, STATE_LEN).unwrap();
                    }
                    assert_eq!(
                        hex(&call(8, &state, &[], 0, expected.len() / 2).unwrap()),
                        *expected
                    );
                    assert_eq!(
                        hex(&call(8, &state, &[], 63, 65).unwrap()),
                        &expected[126..256]
                    );
                    // Independent official output slices exercise the borrowed
                    // finalizer across short-output and block boundaries.
                    for (seek, length) in [
                        (0, 0),
                        (0, 1),
                        (0, 32),
                        (1, 31),
                        (31, 1),
                        (31, 2),
                        (32, 0),
                        (32, 1),
                        (63, 2),
                        (64, 32),
                    ] {
                        let start = seek as usize * 2;
                        let end = start + length * 2;
                        assert_eq!(
                            hex(&call(8, &state, &[], seek, length).unwrap()),
                            &expected[start..end]
                        );
                        if mode == 0 {
                            assert_eq!(
                                hex(&call(3, &input, &[], seek, length).unwrap()),
                                &expected[start..end]
                            );
                        }
                    }
                    assert!(call(8, &state, &[], u64::MAX, 0).unwrap().is_empty());
                }
            }
        }
    }

    #[test]
    fn malformed_state_key_limits_and_branching() {
        assert_eq!(call(1, &[0; 31], b"x", 0, 32), Err(INVALID_KEY));
        assert_eq!(call(5, &[0; 33], &[], 0, STATE_LEN), Err(INVALID_KEY));
        assert_eq!(call(8, b"garbage", &[], 0, 32), Err(INVALID_STATE));
        // Empty and short output shortcuts must preserve error precedence.
        assert_eq!(call(8, b"garbage", &[], u64::MAX, 0), Err(INVALID_STATE));
        assert_eq!(call(8, b"garbage", &[], u64::MAX, 1), Err(INVALID_SEEK));
        assert!(call(3, b"abc", &[], u64::MAX, 0).unwrap().is_empty());
        let initial = call(4, &[], &[], 0, STATE_LEN).unwrap();
        for (offset, value) in [
            (0, 0),
            (4, 32),
            (5, 1),
            (8, 1),
            (40, 1),
            (47, 0x40),
            (49, 5),
            (50, 1),
            (51, 1),
            (64, 1),
            (1088, 1),
            (2815, 1),
        ] {
            let mut bad = initial.clone();
            bad[offset] = value;
            assert_eq!(call(7, &bad, b"x", 0, STATE_LEN), Err(INVALID_STATE));
            assert_eq!(call(8, &bad, &[], 0, 32), Err(INVALID_STATE));
            assert_eq!(call(8, &bad, &[], 31, 1), Err(INVALID_STATE));
            assert_eq!(call(8, &bad, &[], u64::MAX, 0), Err(INVALID_STATE));
        }
        let mut forged = initial.clone();
        forged[40..48].copy_from_slice(&MAX_CHUNKS.to_le_bytes());
        forged[48..50].copy_from_slice(&1023u16.to_le_bytes());
        forged[50] = 54;
        assert_eq!(call(7, &forged, b"x", 0, STATE_LEN), Err(INPUT_TOO_LONG));
        assert_eq!(call(3, b"abc", &[], u64::MAX, 1), Err(INVALID_SEEK));
        assert_eq!(check_output(0, MAX_OUTPUT + 1), Err(OUTPUT_TOO_LARGE));
        let prefix = call(7, &initial, b"prefix", 0, STATE_LEN).unwrap();
        let left = call(7, &prefix, b"left", 0, STATE_LEN).unwrap();
        let right = call(7, &prefix, b"right", 0, STATE_LEN).unwrap();
        assert_eq!(call(8, &prefix, &[], 0, 32), call(0, b"prefix", &[], 0, 32));
        assert_eq!(
            call(8, &left, &[], 0, 32),
            call(0, b"prefixleft", &[], 0, 32)
        );
        assert_eq!(
            call(8, &right, &[], 0, 32),
            call(0, b"prefixright", &[], 0, 32)
        );
        assert_ne!(
            call(2, b"context A", b"same", 0, 32),
            call(2, b"context B", b"same", 0, 32)
        );
    }

    #[test]
    fn borrowed_finalizer_validates_every_padding_byte() {
        // Pending tails begin at every alignment. Exercise every rejected byte,
        // including short remainders and the complete unused CV stack.
        for pending_len in [0, 1, 7, 8, 9, 63, 64, 65, 1023, 1024] {
            let initial = call(4, &[], &[], 0, STATE_LEN).unwrap();
            let input = pattern(pending_len);
            let state = call(7, &initial, &input, 0, STATE_LEN).unwrap();
            let mut invalid = state.clone();
            for offset in (5..8)
                .chain(51..64)
                .chain(64 + pending_len..1088)
                .chain(1088..STATE_LEN)
            {
                invalid[offset] = 1;
                assert_eq!(
                    call(8, &invalid, &[], u64::MAX, 0),
                    Err(INVALID_STATE),
                    "pending_len={pending_len}, offset={offset}"
                );
                invalid[offset] = 0;
            }
        }
    }

    #[test]
    fn differential_tree_shapes_and_seeks() {
        for len in [
            0, 1, 63, 64, 65, 1023, 1024, 1025, 2048, 2049, 3072, 4095, 4096, 4097, 8191, 8192,
            8193, 65535, 65536, 65537, 1_000_000,
        ] {
            let input = pattern(len);
            let mut state = State::new(0, [0; 32]);
            for chunk in input.chunks(997) {
                state.update(chunk).unwrap();
            }
            for seek in [
                0,
                1,
                31,
                32,
                63,
                64,
                65,
                1024,
                (1u64 << 32) + 7,
                u64::MAX - 131,
            ] {
                let mut reader = blake3::Hasher::new().update(&input).finalize_xof();
                reader.set_position(seek);
                let mut expected = [0; 131];
                reader.fill(&mut expected);
                let mut actual = [0; 131];
                let mut reader = state.reader();
                reader.set_position(seek);
                reader.fill(&mut actual);
                assert_eq!(actual, expected, "len={len}, seek={seek}");
                let mut encoded = vec![0; STATE_LEN];
                state.encode(&mut encoded);
                assert_eq!(
                    call(8, &encoded, &[], seek, 131).unwrap(),
                    expected,
                    "borrowed len={len}, seek={seek}"
                );
            }
        }
    }
}
