//! Allocation-free SHA-256 kernel. Input is borrowed from a Motoko Blob and
//! the caller provides the payload of a freshly allocated 32-byte Blob.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

const INITIAL: [u32; 8] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

#[inline(always)]
fn sigma0(x: u32) -> u32 {
    x.rotate_right(7) ^ x.rotate_right(18) ^ (x >> 3)
}

#[inline(always)]
fn sigma1(x: u32) -> u32 {
    x.rotate_right(17) ^ x.rotate_right(19) ^ (x >> 10)
}

// Keep the hash state and rolling schedule in Wasm locals across blocks.
#[inline(always)]
fn compress(state: &mut [u32; 8], block: &[u8; 64]) {
    let mut w = [0u32; 16];
    for (word, bytes) in w.iter_mut().zip(block.chunks_exact(4)) {
        *word = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
    }
    let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = *state;

    // Constant indices and rotated variable names let LLVM keep the rolling
    // schedule in Wasm locals and remove loop/index overhead from every round.
    macro_rules! round {
        ($i:expr, $a:ident, $b:ident, $c:ident, $d:ident,
            $e:ident, $f:ident, $g:ident, $h:ident, $k:expr) => {{
            if $i >= 16 {
                w[$i & 15] = sigma1(w[($i + 14) & 15])
                    .wrapping_add(w[($i + 9) & 15])
                    .wrapping_add(sigma0(w[($i + 1) & 15]))
                    .wrapping_add(w[$i & 15]);
            }
            let s1 = $e.rotate_right(6) ^ $e.rotate_right(11) ^ $e.rotate_right(25);
            let choose = $g ^ ($e & ($f ^ $g));
            let t1 = $h
                .wrapping_add(s1)
                .wrapping_add(choose)
                .wrapping_add($k)
                .wrapping_add(w[$i & 15]);
            let s0 = $a.rotate_right(2) ^ $a.rotate_right(13) ^ $a.rotate_right(22);
            // The previous round's a ^ b becomes this round's b ^ c, so
            // LLVM can reuse that XOR instead of recomputing it.
            let majority = (($a ^ $b) & ($b ^ $c)) ^ $b;
            $d = $d.wrapping_add(t1);
            $h = t1.wrapping_add(s0).wrapping_add(majority);
        }};
    }

    round!(0, a, b, c, d, e, f, g, h, 0x428a2f98);
    round!(1, h, a, b, c, d, e, f, g, 0x71374491);
    round!(2, g, h, a, b, c, d, e, f, 0xb5c0fbcf);
    round!(3, f, g, h, a, b, c, d, e, 0xe9b5dba5);
    round!(4, e, f, g, h, a, b, c, d, 0x3956c25b);
    round!(5, d, e, f, g, h, a, b, c, 0x59f111f1);
    round!(6, c, d, e, f, g, h, a, b, 0x923f82a4);
    round!(7, b, c, d, e, f, g, h, a, 0xab1c5ed5);
    round!(8, a, b, c, d, e, f, g, h, 0xd807aa98);
    round!(9, h, a, b, c, d, e, f, g, 0x12835b01);
    round!(10, g, h, a, b, c, d, e, f, 0x243185be);
    round!(11, f, g, h, a, b, c, d, e, 0x550c7dc3);
    round!(12, e, f, g, h, a, b, c, d, 0x72be5d74);
    round!(13, d, e, f, g, h, a, b, c, 0x80deb1fe);
    round!(14, c, d, e, f, g, h, a, b, 0x9bdc06a7);
    round!(15, b, c, d, e, f, g, h, a, 0xc19bf174);
    round!(16, a, b, c, d, e, f, g, h, 0xe49b69c1);
    round!(17, h, a, b, c, d, e, f, g, 0xefbe4786);
    round!(18, g, h, a, b, c, d, e, f, 0x0fc19dc6);
    round!(19, f, g, h, a, b, c, d, e, 0x240ca1cc);
    round!(20, e, f, g, h, a, b, c, d, 0x2de92c6f);
    round!(21, d, e, f, g, h, a, b, c, 0x4a7484aa);
    round!(22, c, d, e, f, g, h, a, b, 0x5cb0a9dc);
    round!(23, b, c, d, e, f, g, h, a, 0x76f988da);
    round!(24, a, b, c, d, e, f, g, h, 0x983e5152);
    round!(25, h, a, b, c, d, e, f, g, 0xa831c66d);
    round!(26, g, h, a, b, c, d, e, f, 0xb00327c8);
    round!(27, f, g, h, a, b, c, d, e, 0xbf597fc7);
    round!(28, e, f, g, h, a, b, c, d, 0xc6e00bf3);
    round!(29, d, e, f, g, h, a, b, c, 0xd5a79147);
    round!(30, c, d, e, f, g, h, a, b, 0x06ca6351);
    round!(31, b, c, d, e, f, g, h, a, 0x14292967);
    round!(32, a, b, c, d, e, f, g, h, 0x27b70a85);
    round!(33, h, a, b, c, d, e, f, g, 0x2e1b2138);
    round!(34, g, h, a, b, c, d, e, f, 0x4d2c6dfc);
    round!(35, f, g, h, a, b, c, d, e, 0x53380d13);
    round!(36, e, f, g, h, a, b, c, d, 0x650a7354);
    round!(37, d, e, f, g, h, a, b, c, 0x766a0abb);
    round!(38, c, d, e, f, g, h, a, b, 0x81c2c92e);
    round!(39, b, c, d, e, f, g, h, a, 0x92722c85);
    round!(40, a, b, c, d, e, f, g, h, 0xa2bfe8a1);
    round!(41, h, a, b, c, d, e, f, g, 0xa81a664b);
    round!(42, g, h, a, b, c, d, e, f, 0xc24b8b70);
    round!(43, f, g, h, a, b, c, d, e, 0xc76c51a3);
    round!(44, e, f, g, h, a, b, c, d, 0xd192e819);
    round!(45, d, e, f, g, h, a, b, c, 0xd6990624);
    round!(46, c, d, e, f, g, h, a, b, 0xf40e3585);
    round!(47, b, c, d, e, f, g, h, a, 0x106aa070);
    round!(48, a, b, c, d, e, f, g, h, 0x19a4c116);
    round!(49, h, a, b, c, d, e, f, g, 0x1e376c08);
    round!(50, g, h, a, b, c, d, e, f, 0x2748774c);
    round!(51, f, g, h, a, b, c, d, e, 0x34b0bcb5);
    round!(52, e, f, g, h, a, b, c, d, 0x391c0cb3);
    round!(53, d, e, f, g, h, a, b, c, 0x4ed8aa4a);
    round!(54, c, d, e, f, g, h, a, b, 0x5b9cca4f);
    round!(55, b, c, d, e, f, g, h, a, 0x682e6ff3);
    round!(56, a, b, c, d, e, f, g, h, 0x748f82ee);
    round!(57, h, a, b, c, d, e, f, g, 0x78a5636f);
    round!(58, g, h, a, b, c, d, e, f, 0x84c87814);
    round!(59, f, g, h, a, b, c, d, e, 0x8cc70208);
    round!(60, e, f, g, h, a, b, c, d, 0x90befffa);
    round!(61, d, e, f, g, h, a, b, c, 0xa4506ceb);
    round!(62, c, d, e, f, g, h, a, b, 0xbef9a3f7);
    round!(63, b, c, d, e, f, g, h, a, 0xc67178f2);

    for (current, next) in state.iter_mut().zip([a, b, c, d, e, f, g, h]) {
        *current = current.wrapping_add(next);
    }
}

// This leaf kernel keeps the padding buffer off the fixed-size and empty paths.
#[inline(never)]
unsafe fn sha256_general(input: *const u8, len: usize, output: *mut u8) {
    let input = unsafe { core::slice::from_raw_parts(input, len) };
    let mut state = INITIAL;
    let mut blocks = input.chunks_exact(64);
    let remaining = blocks.remainder();
    let mut tail = [0u8; 128];
    tail[..remaining.len()].copy_from_slice(remaining);
    tail[remaining.len()] = 0x80;
    let padded = if remaining.len() < 56 { 64 } else { 128 };
    tail[padded - 8..padded].copy_from_slice(&(input.len() as u64 * 8).to_be_bytes());
    // One compression loop avoids both state spills between calls and
    // duplicating the unrolled rounds for the one- and two-block tails.
    // ChunksExact is fused, so no Chain exhaustion state is needed.
    let mut padding = tail[..padded].chunks_exact(64);
    while let Some(block) = blocks.next().or_else(|| padding.next()) {
        compress(&mut state, block.try_into().expect("block length"));
    }
    unsafe { write_digest(&state, output) };
}

#[inline(always)]
unsafe fn write_digest(state: &[u32; 8], output: *mut u8) {
    // Write all bytes without first referencing the uninitialized Blob payload.
    // Blob payloads need not be aligned to u32.
    for (i, word) in state.iter().enumerate() {
        unsafe { output.add(i * 4).cast::<u32>().write_unaligned(word.to_be()) };
    }
}

// A 64-byte Merkle-parent input has an entirely constant second message
// schedule. Keep it separate from the general loop so it avoids the loop's
// padding setup and state spills.
#[inline(never)]
unsafe fn sha256_merkle_parent(input: *const u8, output: *mut u8) {
    let input = unsafe { &*input.cast::<[u8; 64]>() };
    let mut state = INITIAL;
    compress(&mut state, input);
    let mut tail = [0u8; 64];
    tail[0] = 0x80;
    tail[62] = 2;
    compress(&mut state, &tail);
    unsafe { write_digest(&state, output) };
}

// Hashes and compressed SEC1 public keys share eight complete input words.
// The ninth word and encoded bit length differ; all other padding words are
// constant, so one specialization serves both lengths without duplicated rounds.
#[inline(never)]
unsafe fn sha256_digest_or_public_key(input: *const u8, len: usize, output: *mut u8) {
    let mut state = INITIAL;
    let mut tail = [0u8; 64];
    unsafe { core::ptr::copy_nonoverlapping(input, tail.as_mut_ptr(), 32) };
    if len == 33 {
        tail[32] = unsafe { input.add(32).read() };
        tail[33] = 0x80;
        tail[63] = 8;
    } else {
        tail[32] = 0x80;
    }
    tail[62] = 1;
    compress(&mut state, &tail);
    unsafe { write_digest(&state, output) };
}

/// # Safety
/// Input points to `len` readable bytes and output to 32 writable bytes.
/// Neither pointer may be invalidated by a GC increment during this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha256_digest(input: *const u8, len: usize, output: *mut u8) {
    if len == 0 {
        // The empty message has a fixed digest. Write it directly so LLVM
        // does not spill the nonempty path's state to merge array results.
        const EMPTY: [u8; 32] = [
            0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14, 0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f,
            0xb9, 0x24, 0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c, 0xa4, 0x95, 0x99, 0x1b,
            0x78, 0x52, 0xb8, 0x55,
        ];
        // Explicit word stores become immediate Wasm constants, avoiding
        // loads from a static data segment. Unaligned Blob payloads are valid.
        for (i, bytes) in EMPTY.chunks_exact(8).enumerate() {
            let word = u64::from_ne_bytes(bytes.try_into().expect("word length"));
            unsafe { output.add(i * 8).cast::<u64>().write_unaligned(word) };
        }
        return;
    }
    if len == 32 || len == 33 {
        unsafe { sha256_digest_or_public_key(input, len, output) };
    } else if len == 64 {
        unsafe { sha256_merkle_parent(input, output) };
    } else {
        unsafe { sha256_general(input, len, output) };
    }
}

/// One compiler-created descriptor borrows an immutable Blob payload.
/// Descriptor storage and payloads may be unaligned.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Part {
    input: *const u8,
    len: usize,
}

/// # Safety
/// `parts` points to `count` readable descriptors, each describing readable
/// immutable bytes. `output` points to 32 writable bytes. The compiler resolves
/// forwarding before borrowing and introduces no GC safepoint until return.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sha256_digest_parts(parts: *const Part, count: usize, output: *mut u8) {
    let mut length = 0u64;
    for index in 0..count {
        let part = unsafe { parts.add(index).read_unaligned() };
        length = length.wrapping_add(part.len as u64);
    }
    let mut state = INITIAL;
    let mut tail = [0u8; 64];
    let mut index = 0;
    let mut input = core::ptr::null();
    let mut remaining = 0;
    let mut final_length_block = false;
    loop {
        let mut finished = false;
        let block = if final_length_block {
            tail.fill(0);
            tail[56..].copy_from_slice(&length.wrapping_mul(8).to_be_bytes());
            finished = true;
            tail.as_ptr()
        } else {
            let mut used = 0;
            loop {
                while remaining == 0 && index < count {
                    let part = unsafe { parts.add(index).read_unaligned() };
                    input = part.input;
                    remaining = part.len;
                    index += 1;
                }
                if remaining == 0 {
                    tail[used] = 0x80;
                    tail[used + 1..].fill(0);
                    if used < 56 {
                        tail[56..].copy_from_slice(&length.wrapping_mul(8).to_be_bytes());
                        finished = true;
                    } else {
                        final_length_block = true;
                    }
                    break tail.as_ptr();
                }
                // Complete blocks within a part are compressed in place.
                if used == 0 && remaining >= 64 {
                    let block = input;
                    input = unsafe { input.add(64) };
                    remaining -= 64;
                    break block;
                }
                // Only blocks crossing part boundaries use the stack buffer.
                let take = core::cmp::min(64 - used, remaining);
                unsafe { core::ptr::copy_nonoverlapping(input, tail.as_mut_ptr().add(used), take) };
                input = unsafe { input.add(take) };
                remaining -= take;
                used += take;
                if used == 64 {
                    break tail.as_ptr();
                }
            }
        };
        // Keep one copy of the unrolled compression rounds for all input and
        // padding blocks, including blocks borrowed directly from a part.
        compress(&mut state, unsafe { &*block.cast::<[u8; 64]>() });
        if finished {
            break;
        }
    }
    unsafe { write_digest(&state, output) };
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn digest(input: &[u8]) -> [u8; 32] {
        let mut output = [0; 32];
        unsafe { sha256_general(input.as_ptr(), input.len(), output.as_mut_ptr()) };
        output
    }

    fn check(input: &[u8], expected: &str) {
        let actual: String = digest(input).iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(actual, expected);
        // Exercise the exported pointer ABI at unaligned addresses, including
        // empty input, and verify that exactly the output's 32 bytes change.
        let mut borrowed = vec![0xa5];
        borrowed.extend_from_slice(input);
        borrowed.push(0x5a);
        let saved = borrowed.clone();
        let mut output = [0xa5; 34];
        unsafe {
            sha256_digest(
                borrowed.as_ptr().add(1),
                input.len(),
                output.as_mut_ptr().add(1),
            )
        };
        assert_eq!(&output[1..33], digest(input));
        assert_eq!(output[0], 0xa5);
        assert_eq!(output[33], 0xa5);
        assert_eq!(borrowed, saved);
    }

    fn check_parts(input: &[u8], cuts: &[usize]) {
        let mut parts = Vec::new();
        let mut start = 0;
        for &end in cuts {
            assert!(end >= start && end <= input.len());
            parts.push(Part { input: input[start..].as_ptr(), len: end - start });
            start = end;
        }
        parts.push(Part { input: input[start..].as_ptr(), len: input.len() - start });
        let mut descriptors = vec![0xa5u8; 2 + parts.len() * core::mem::size_of::<Part>()];
        for (index, part) in parts.iter().enumerate() {
            unsafe {
                descriptors.as_mut_ptr().add(1 + index * core::mem::size_of::<Part>())
                    .cast::<Part>().write_unaligned(*part);
            }
        }
        let saved = descriptors.clone();
        let mut output = [0xa5; 34];
        unsafe {
            sha256_digest_parts(descriptors.as_ptr().add(1).cast::<Part>(), parts.len(), output.as_mut_ptr().add(1));
        }
        assert_eq!(&output[1..33], digest(input));
        assert_eq!(output[0], 0xa5);
        assert_eq!(output[33], 0xa5);
        assert_eq!(descriptors, saved);
    }

    #[test]
    fn segmented_boundaries_and_randomized_splits() {
        let mut output = [0; 32];
        unsafe { sha256_digest_parts(core::ptr::null(), 0, output.as_mut_ptr()) };
        assert_eq!(output, digest(b""));
        for length in [0, 1, 2, 31, 32, 33, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 1024, 65537] {
            let input: Vec<u8> = (0..length).map(|i| (i * 131 + 17) as u8).collect();
            for split in 0..=core::cmp::min(length, 140) {
                check_parts(&input, &[0, split, split, length]);
            }
            check_parts(&input, &(0..=length).collect::<Vec<_>>());
        }
        let mut random = 0x85ec_33a9u32;
        for _ in 0..256 {
            random = random.wrapping_mul(1664525).wrapping_add(1013904223);
            let length = random as usize % 8193;
            let input: Vec<u8> = (0..length).map(|_| {
                random = random.wrapping_mul(1664525).wrapping_add(1013904223);
                (random >> 24) as u8
            }).collect();
            let mut cuts = Vec::new();
            let mut end = 0;
            while end < length {
                random = random.wrapping_mul(1664525).wrapping_add(1013904223);
                end = core::cmp::min(length, end + random as usize % 130);
                cuts.push(end);
            }
            check_parts(&input, &cuts);
        }
    }

    #[test]
    fn standard_vectors() {
        check(
            b"",
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        );
        check(
            b"abc",
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        );
        check(
            b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
        );
        check(
            b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn\
            hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
            "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
        );
        check(
            &vec![b'a'; 1_000_000],
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
        );
    }

    #[test]
    fn fixed_size_extremes() {
        // Independent hashlib/OpenSSL answers exercise constant padding and
        // message-schedule carries in the shared digest/public-key and parent paths.
        for (length, byte, expected) in [
            (
                32,
                0x00,
                "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925",
            ),
            (
                32,
                0xff,
                "af9613760f72635fbdb44a5a0a63c39f12af30f950a6ee5c971be188e89c4051",
            ),
            (
                33,
                0x00,
                "7f9c9e31ac8256ca2f258583df262dbc7d6f68f2a03043d5c99a4ae5a7396ce9",
            ),
            (
                33,
                0xff,
                "ffb8b6e27a06ffb98ecf60d261a6818cdc573f8256f06429000a2b125b070c37",
            ),
            (
                64,
                0x00,
                "f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b",
            ),
            (
                64,
                0xff,
                "8667e718294e9e0df1d30600ba3eeb201f764aad2dad72748643e4a285e1d1f7",
            ),
        ] {
            check(&vec![byte; length], expected);
        }
    }

    #[test]
    fn binary_padding_boundaries() {
        // Independently generated with Python's hashlib/OpenSSL SHA-256.
        for (length, expected) in [
            (
                1,
                "4a64a107f0cb32536e5bce6c98c393db21cca7f4ea187ba8c4dca8b51d4ea80a",
            ),
            (
                32,
                "43599ef388fde687ef9376c222e271b733efb0b6982a7810af4a0cbd5a0050e3",
            ),
            (
                33,
                "494429bb371f5d9fbd3d20a65986a827a6f0059deeb28b157d5a42b82d2f00b4",
            ),
            (
                55,
                "59aaae80b8e7958f5757b4ac9274f1fd57ec0dc7aa8349319102316781b92006",
            ),
            (
                56,
                "dca902d31487ffab357ce36cc5abc6947fbb69127ec04c468ba5687268c4bf7c",
            ),
            (
                63,
                "b8e655e9e7ad413b96f0a371eb1d6db71dcca27f4eee35892517cbe4bfaa6f9a",
            ),
            (
                64,
                "e5146be62accc56709594cb45c651b361df94f622cbb09b91ea3ca7a2060bd53",
            ),
            (
                65,
                "4b6c6774f0cbcd776a90e187b9494e04ca880c0afe3ea1c5cad51c8bbcb41f74",
            ),
            (
                119,
                "3244509f8746f6fb511ca8a72a292a4d7d12e456cce283c03f169dbbcb0d512e",
            ),
            (
                120,
                "c5236e50172da3b69c903dcd3b3bb8ce855182f79364d1b59ed36367aa25e468",
            ),
            (
                127,
                "b4f5398bf618d741f2ab0f6e2fcde06f4949c20d476b5f6e1d4bf8618bc8973a",
            ),
            (
                128,
                "ed045c7c319e0c9286e1dea21c80bfd4a08eca43e02e13ee8a7a2c8b4b2baec9",
            ),
            (
                129,
                "d6f2fca0407b3f98c9ce29ae92a6cdf489506450fdbb29172f6b18987bc685db",
            ),
            (
                1024,
                "575383deff0775797e1ff4c82da069141937c843a81cbe50959a96bcfa88140e",
            ),
            (
                65537,
                "65d80b2b0f0120bda1628b3749982090e058d2d9f4a5fad1bc70250b49bc4e96",
            ),
        ] {
            let input: Vec<u8> = (0..length).map(|i| (i * 131 + 17) as u8).collect();
            check(&input, expected);
        }
    }
}
