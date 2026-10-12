//! Bounded, allocation-free Bitcoin Base58 conversion. The managed caller
//! allocates the output/scratch Blob and passes no pointers across safepoints.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

const ALPHABET: &[u8; 58] = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
pub const MAX_BYTES: usize = 4096;
pub const MAX_TEXT_BYTES: usize = 5653;
const TOO_LARGE: i64 = -1;

const fn alphabet_map() -> [u8; 256] {
    let mut map = [u8::MAX; 256];
    let mut i = 0;
    while i < ALPHABET.len() {
        map[ALPHABET[i] as usize] = i as u8;
        i += 1;
    }
    map
}
const MAP: [u8; 256] = alphabet_map();

const RADIX: u64 = 656_356_768; // 58^5 fits in 30 bits.
const ENCODE_LIMBS: usize = (MAX_TEXT_BYTES + 4) / 5;
const DECODE_LIMBS: usize = MAX_BYTES / 4;

fn encode(input: &[u8], output: &mut [u8]) -> i64 {
    output.fill(0);
    if input.len() > MAX_BYTES || output.len() < input.len() * 138 / 100 + 1 {
        return TOO_LARGE;
    }
    let zeros = input.iter().take_while(|&&b| b == 0).count();
    output[..zeros].fill(b'1');
    if zeros == input.len() {
        return zeros as i64;
    }
    let input = &input[zeros..];
    let output = &mut output[zeros..];
    if input.len() <= 8 {
        // At most eight bytes fit exactly in u64. This path also handles the
        // empty and all-zero cases without reserving the large limb scratch.
        let mut carry = input.iter().fold(0u64, |n, &b| (n << 8) | b as u64);
        let mut used = 0;
        while carry != 0 {
            output[used] = ALPHABET[(carry % 58) as usize];
            carry /= 58;
            used += 1;
        }
        output[..used].reverse();
        return (zeros + used) as i64;
    }
    let length = encode_limbs(input, output);
    if length < 0 {
        length
    } else {
        zeros as i64 + length
    }
}

// Keep the bounded stack scratch out of scalar-only calls.
#[inline(never)]
fn encode_limbs(input: &[u8], output: &mut [u8]) -> i64 {
    // Each initialized limb holds five base-58 digits. The used prefix is the
    // only portion read; extending that prefix always writes before reading.
    let mut limbs = [core::mem::MaybeUninit::<u32>::uninit(); ENCODE_LIMBS];
    let mut used = 0;
    for group in input.chunks(4) {
        let shift = group.len() * 8;
        let mut carry = group.iter().fold(0u64, |n, &b| (n << 8) | b as u64);
        for limb in &mut limbs[..used] {
            // (58^5-1)*2^32 + (2^32-1) < 2^62.
            carry += (unsafe { limb.assume_init() } as u64) << shift;
            limb.write((carry % RADIX) as u32);
            carry /= RADIX;
        }
        while carry != 0 {
            if used == limbs.len() {
                return TOO_LARGE;
            }
            limbs[used].write((carry % RADIX) as u32);
            carry /= RADIX;
            used += 1;
        }
    }
    let mut end = 0;
    if used != 0 {
        let mut top = unsafe { limbs[used - 1].assume_init() };
        let mut digits = [0u8; 5];
        let mut count = 0;
        while top != 0 {
            digits[count] = ALPHABET[(top % 58) as usize];
            top /= 58;
            count += 1;
        }
        for &digit in digits[..count].iter().rev() {
            output[end] = digit;
            end += 1;
        }
        for limb in limbs[..used - 1].iter().rev() {
            let mut value = unsafe { limb.assume_init() };
            for i in (0..5).rev() {
                output[end + i] = ALPHABET[(value % 58) as usize];
                value /= 58;
            }
            end += 5;
        }
    }
    end as i64
}

fn decode(input: &[u8], output: &mut [u8]) -> i64 {
    output.fill(0);
    if input.len() > MAX_TEXT_BYTES {
        return TOO_LARGE;
    }
    for (index, &byte) in input.iter().enumerate() {
        if MAP[byte as usize] == u8::MAX {
            return -2 - index as i64;
        }
    }
    let zeros = input.iter().take_while(|&&b| b == b'1').count();
    let capacity = output.len().min(MAX_BYTES);
    if zeros > capacity {
        return TOO_LARGE;
    }
    if zeros == input.len() {
        return zeros as i64;
    }
    let input = &input[zeros..];
    let output = &mut output[zeros..capacity];
    if input.len() <= 10 {
        // 58^10 < 2^59: all ten-digit values fit exactly in u64.
        let mut carry = input
            .iter()
            .fold(0u64, |n, &b| n * 58 + MAP[b as usize] as u64);
        let used = (64 - carry.leading_zeros()).div_ceil(8) as usize;
        if used > output.len() {
            return TOO_LARGE;
        }
        for byte in output[..used].iter_mut().rev() {
            *byte = carry as u8;
            carry >>= 8;
        }
        return (zeros + used) as i64;
    }
    let length = decode_limbs(input, output);
    if length < 0 {
        length
    } else {
        zeros as i64 + length
    }
}

#[inline(never)]
fn decode_limbs(input: &[u8], output: &mut [u8]) -> i64 {
    let mut limbs = [core::mem::MaybeUninit::<u32>::uninit(); DECODE_LIMBS];
    let mut used = 0;
    for group in input.chunks(5) {
        let mut multiplier = 1u64;
        let mut carry = 0u64;
        for &byte in group {
            multiplier *= 58;
            carry = carry * 58 + MAP[byte as usize] as u64;
        }
        for limb in &mut limbs[..used] {
            // (2^32-1)*58^5 + (58^5-1) < 2^62.
            carry += (unsafe { limb.assume_init() } as u64) * multiplier;
            limb.write(carry as u32);
            carry >>= 32;
        }
        if carry != 0 {
            if used == limbs.len() {
                return TOO_LARGE;
            }
            limbs[used].write(carry as u32);
            used += 1;
        }
    }
    if used == 0 {
        return 0;
    }
    let top = unsafe { limbs[used - 1].assume_init() };
    let top_bytes = (32 - top.leading_zeros()).div_ceil(8) as usize;
    let length = (used - 1) * 4 + top_bytes;
    if length > output.len() {
        return TOO_LARGE;
    }
    let mut end = 0;
    for &byte in &top.to_be_bytes()[4 - top_bytes..] {
        output[end] = byte;
        end += 1;
    }
    for limb in limbs[..used - 1].iter().rev() {
        output[end..end + 4].copy_from_slice(&unsafe { limb.assume_init() }.to_be_bytes());
        end += 4;
    }
    end as i64
}

/// # Safety
/// `input` addresses `len` readable bytes. `output` addresses `capacity`
/// writable bytes, disjoint from input. Both pointers are non-null and remain
/// valid through this call. The output is initialized in full before return.
/// Returns output length, or -1 for a size/capacity error.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn base58_encode(
    input: *const u8,
    len: usize,
    output: *mut u8,
    capacity: usize,
) -> i64 {
    // Do not form a Rust reference to an uninitialized managed Blob payload.
    unsafe { output.write_bytes(0, capacity) };
    encode(unsafe { core::slice::from_raw_parts(input, len) }, unsafe {
        core::slice::from_raw_parts_mut(output, capacity)
    })
}

/// # Safety
/// Same pointer contract as `base58_encode`. Returns output length, -1 for
/// a size/capacity error, or -2 minus the first invalid UTF-8 byte offset.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn base58_decode(
    input: *const u8,
    len: usize,
    output: *mut u8,
    capacity: usize,
) -> i64 {
    unsafe { output.write_bytes(0, capacity) };
    decode(unsafe { core::slice::from_raw_parts(input, len) }, unsafe {
        core::slice::from_raw_parts_mut(output, capacity)
    })
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    core::arch::wasm64::unreachable()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encoded(input: &[u8]) -> Vec<u8> {
        let mut output = vec![0xa5; input.len() * 138 / 100 + 1];
        let size = encode(input, &mut output);
        assert!(size >= 0);
        assert!(output[size as usize..].iter().all(|&b| b == 0));
        output.truncate(size as usize);
        output
    }
    fn decoded(input: &[u8]) -> Result<Vec<u8>, i64> {
        let mut output = vec![0xa5; input.len().min(MAX_BYTES)];
        let size = decode(input, &mut output);
        if size < 0 {
            return Err(size);
        }
        assert!(output[size as usize..].iter().all(|&b| b == 0));
        output.truncate(size as usize);
        Ok(output)
    }
    fn hex(input: &str) -> Vec<u8> {
        input
            .as_bytes()
            .chunks_exact(2)
            .map(|b| u8::from_str_radix(core::str::from_utf8(b).unwrap(), 16).unwrap())
            .collect()
    }

    #[test]
    fn bitcoin_core_vectors() {
        // Bitcoin Core v29.0 src/test/data/base58_encode_decode.json.
        for (bytes, text) in [
            ("", ""),
            ("61", "2g"),
            ("626262", "a3gV"),
            ("636363", "aPEr"),
            (
                "73696d706c792061206c6f6e6720737472696e67",
                "2cFupjhnEsSn59qHXstmK2ffpLv2",
            ),
            (
                "00eb15231dfceb60925886b67d065299925915aeb172c06647",
                "1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L",
            ),
            ("516b6fcd0f", "ABnLTmg"),
            ("bf4f89001e670274dd", "3SEo3LWLoPntC"),
            ("572e4794", "3EFU7m"),
            ("ecac89cad93923c02321", "EJDM8drfXA6uyA"),
            ("10c8511e", "Rt5zm"),
            ("00000000000000000000", "1111111111"),
            ("271f359e", "zzzzy"),
            ("271f359f", "zzzzz"),
            ("271f35a0", "211111"),
            ("271f35a1", "211112"),
        ] {
            let bytes = hex(bytes);
            assert_eq!(encoded(&bytes), text.as_bytes(), "{text}");
            assert_eq!(decoded(text.as_bytes()), Ok(bytes));
        }
    }

    #[test]
    fn every_byte_and_group_boundaries() {
        for length in [
            0, 1, 2, 6, 7, 8, 9, 13, 14, 15, 31, 32, 33, 64, 78, 82, 255, 256, 257, 1024, 4096,
        ] {
            for zeros in [0, 1, length / 2, length] {
                if zeros > length {
                    continue;
                }
                let mut bytes: Vec<u8> = (0..length).map(|i| (i * 131 + 17) as u8).collect();
                bytes[..zeros].fill(0);
                assert_eq!(decoded(&encoded(&bytes)), Ok(bytes));
            }
        }
        for byte in 0..=255u8 {
            assert_eq!(decoded(&encoded(&[byte])), Ok(vec![byte]));
        }
    }

    #[test]
    fn alphabet_and_error_precedence() {
        for bad in [
            b"0".as_slice(),
            b"O",
            b"I",
            b"l",
            b" ",
            b"\n",
            b"\t",
            b"\0",
            "é".as_bytes(),
            "😀".as_bytes(),
        ] {
            assert_eq!(decoded(bad), Err(-2));
            let mut prefix = b"123z".to_vec();
            prefix.extend_from_slice(bad);
            assert_eq!(decoded(&prefix), Err(-6));
        }
        let mut full = vec![b'1'; MAX_BYTES + 1];
        full.push(b'0');
        assert_eq!(decoded(&full), Err(-2 - (MAX_BYTES + 1) as i64));
        assert_eq!(decoded(&vec![b'0'; MAX_TEXT_BYTES + 1]), Err(TOO_LARGE));
    }

    #[test]
    fn limits_and_small_output_buffers() {
        assert_eq!(decoded(&vec![b'1'; MAX_BYTES]), Ok(vec![0; MAX_BYTES]));
        assert_eq!(decoded(&vec![b'1'; MAX_BYTES + 1]), Err(TOO_LARGE));
        assert_eq!(decoded(&vec![b'z'; MAX_TEXT_BYTES]), Err(TOO_LARGE));
        assert_eq!(encoded(&vec![0; MAX_BYTES]), vec![b'1'; MAX_BYTES]);
        let mut output = vec![0xa5; MAX_TEXT_BYTES + 2];
        assert_eq!(encode(&vec![0; MAX_BYTES + 1], &mut output), TOO_LARGE);
        assert!(output.iter().all(|&b| b == 0));
        assert_eq!(encode(b"abc", &mut []), TOO_LARGE);
        assert_eq!(decode(b"2g", &mut []), TOO_LARGE);
        assert_eq!(decode(b"1", &mut []), TOO_LARGE);
        assert_eq!(decode(b"", &mut []), 0);
    }

    #[test]
    fn pointer_abi_initializes_output_and_preserves_guards() {
        for bytes in [b"".as_slice(), b"\0", b"\0\0abc", b"hello world"] {
            let saved = bytes.to_vec();
            let capacity = bytes.len() * 138 / 100 + 1;
            let mut output = vec![0xa5; capacity + 2];
            let size = unsafe {
                base58_encode(
                    bytes.as_ptr(),
                    bytes.len(),
                    output.as_mut_ptr().add(1),
                    capacity,
                )
            };
            assert_eq!(&output[1..1 + size as usize], encoded(bytes));
            assert_eq!(output[0], 0xa5);
            assert_eq!(output[capacity + 1], 0xa5);
            assert!(
                output[1 + size as usize..1 + capacity]
                    .iter()
                    .all(|&b| b == 0)
            );
            let mut result = vec![0xa5; bytes.len() + 2];
            let result_size = unsafe {
                base58_decode(
                    output.as_ptr().add(1),
                    size as usize,
                    result.as_mut_ptr().add(1),
                    bytes.len(),
                )
            };
            assert_eq!(result_size as usize, bytes.len());
            assert_eq!(&result[1..1 + bytes.len()], bytes);
            assert_eq!(result[0], 0xa5);
            assert_eq!(result[bytes.len() + 1], 0xa5);
            assert_eq!(bytes, saved);
        }
    }
}
