//! Stateless, allocation-free BIP173/BIP350 codec kernels.
//! Only the caller allocates Motoko-managed output; no pointers survive a call.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(simd_wasm64))]

const ALPHABET: &[u8; 32] = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";
const LIMIT: usize = 16 * 1024 * 1024;

// The decoder validates printable ASCII before indexing. Map both cases so
// each symbol needs one lookup, without a 32-character search or lowercasing.
const REVERSE: [u8; 128] = {
    let mut table = [255; 128];
    let mut i = 0;
    while i < ALPHABET.len() {
        let byte = ALPHABET[i];
        table[byte as usize] = i as u8;
        if byte >= b'a' && byte <= b'z' {
            table[(byte - b'a' + b'A') as usize] = i as u8;
        }
        i += 1;
    }
    table
};

// Polymod feedback is linear in the five high bits. Precompute all 32
// combinations to replace five conditional generator contributions per symbol.
const FEEDBACK: [u32; 32] = {
    let generators = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    let mut table = [0; 32];
    let mut high = 0;
    while high < 32 {
        let mut bit = 0;
        while bit < 5 {
            if high & (1 << bit) != 0 {
                table[high] ^= generators[bit];
            }
            bit += 1;
        }
        high += 1;
    }
    table
};
#[inline(always)]
fn step(check: u32, value: u8) -> u32 {
    ((check & 0x1ffffff) << 5) ^ value as u32 ^ FEEDBACK[((check >> 25) & 31) as usize]
}

fn hrp_check(hrp: &[u8]) -> u32 {
    let mut check = 1;
    for byte in hrp {
        check = step(check, byte >> 5);
    }
    check = step(check, 0);
    for byte in hrp {
        check = step(check, byte & 31);
    }
    check
}
fn encode(hrp: &[u8], data: &[u8], modified: bool, output: &mut [u8; 90]) -> Result<usize, i64> {
    if hrp.len() > 83 {
        return Err(1);
    }
    if hrp.is_empty() {
        return Err(2);
    }
    let mut cases = 0u8;
    let mut check = 1;
    // Preserve validation precedence while combining printable validation,
    // normalization, case tracking and the high HRP checksum into one pass.
    for (slot, byte) in output.iter_mut().zip(hrp) {
        if !(33..=126).contains(byte) {
            return Err(2);
        }
        cases |= if byte.is_ascii_alphabetic() {
            1 << ((byte >> 5) & 1)
        } else {
            0
        };
        let lower = byte.to_ascii_lowercase();
        *slot = lower;
        check = step(check, lower >> 5);
    }
    if data.len() > 83 - hrp.len() {
        return Err(1);
    }
    if cases == 3 {
        return Err(3);
    }
    check = step(check, 0);
    for byte in &output[..hrp.len()] {
        check = step(check, byte & 31);
    }
    output[hrp.len()] = b'1';
    for (index, value) in data.iter().enumerate() {
        if *value > 31 {
            return Err(6);
        }
        output[hrp.len() + 1 + index] = ALPHABET[*value as usize];
        check = step(check, *value);
    }
    for _ in 0..6 {
        check = step(check, 0);
    }
    check ^= if modified { 0x2bc830a3 } else { 1 };
    for index in 0..6 {
        output[hrp.len() + 1 + data.len() + index] =
            ALPHABET[((check >> (5 * (5 - index))) & 31) as usize];
    }
    Ok(hrp.len() + data.len() + 7)
}
fn decode(input: &[u8], output: &mut [u8; 90]) -> Result<u64, i64> {
    if !(8..=90).contains(&input.len()) {
        return Err(1);
    }
    let mut cases = 0u8;
    let mut separator = 0;
    // The last separator wins. Printable-character errors still precede mixed
    // case errors, which precede separator/length/alphabet/checksum errors.
    for (index, byte) in input.iter().enumerate() {
        if !(33..=126).contains(byte) {
            return Err(4);
        }
        cases |= if byte.is_ascii_alphabetic() {
            1 << ((byte >> 5) & 1)
        } else {
            0
        };
        if *byte == b'1' {
            separator = index;
        }
    }
    if cases == 3 {
        return Err(3);
    }
    if separator == 0 {
        return Err(2);
    }
    if input.len() - separator - 1 < 6 {
        return Err(1);
    }
    for (slot, byte) in output.iter_mut().zip(&input[..separator]) {
        *slot = byte.to_ascii_lowercase();
    }
    let mut check = hrp_check(&output[..separator]);
    for (index, byte) in input[separator + 1..].iter().enumerate() {
        let value = REVERSE[*byte as usize];
        if value == 255 {
            return Err(4);
        }
        check = step(check, value);
        output[separator + index] = value;
    }
    let modified = match check {
        1 => 0,
        0x2bc830a3 => 1,
        _ => return Err(5),
    };
    let data_len = input.len() - separator - 7;
    Ok((modified << 16) | ((separator as u64) << 8) | data_len as u64)
}

fn converted_len(input: &[u8], from: u64, to: u64, pad: bool) -> Result<usize, i64> {
    if !(1..=8).contains(&from) || !(1..=8).contains(&to) {
        return Err(8);
    }
    // Width checks still run for empty input. Its output is canonically empty
    // for either padding mode, and all byte/size/padding checks are vacuous.
    if input.is_empty() {
        return Ok(0);
    }
    if input.len() > LIMIT {
        return Err(1);
    }
    let bits = input.len() * from as usize;
    let result = (bits + if pad { to as usize - 1 } else { 0 }) / to as usize;
    if result > LIMIT {
        return Err(1);
    }
    if from != 8 && input.iter().any(|b| (*b as u16) >= (1u16 << from)) {
        return Err(6);
    }
    if !pad {
        let remaining = bits % to as usize;
        if remaining >= from as usize {
            return Err(7);
        }
        // remaining < from <= 8, so all residual bits are in the final input byte.
        if remaining != 0
            && input
                .last()
                .is_some_and(|b| b & ((1 << remaining) - 1) != 0)
        {
            return Err(7);
        }
    }
    Ok(result)
}
unsafe fn convert_valid(mut input: &[u8], from: u64, to: u64, pad: bool, mut output: *mut u8) {
    if input.is_empty() {
        return;
    }
    if from == to {
        // Width and element ranges were already checked by converted_len.
        unsafe { core::ptr::copy_nonoverlapping(input.as_ptr(), output, input.len()) };
        return;
    }
    let widths = (from << 4) | to;
    if widths == 0x85 {
        // Each five-byte group forms exactly eight symbols, with no residual bits.
        let mut groups = input.chunks_exact(5);
        for group in &mut groups {
            let packed = [
                group[0] >> 3,
                ((group[0] & 7) << 2) | (group[1] >> 6),
                (group[1] >> 1) & 31,
                ((group[1] & 1) << 4) | (group[2] >> 4),
                ((group[2] & 15) << 1) | (group[3] >> 7),
                (group[3] >> 2) & 31,
                ((group[3] & 3) << 3) | (group[4] >> 5),
                group[4] & 31,
            ];
            unsafe {
                core::ptr::copy_nonoverlapping(packed.as_ptr(), output, packed.len());
                output = output.add(8);
            }
        }
        input = groups.remainder();
    } else if widths == 0x58 {
        // Each eight-symbol group forms exactly five bytes, with no residual bits.
        let mut groups = input.chunks_exact(8);
        for group in &mut groups {
            let packed = [
                (group[0] << 3) | (group[1] >> 2),
                (group[1] << 6) | (group[2] << 1) | (group[3] >> 4),
                (group[3] << 4) | (group[4] >> 1),
                (group[4] << 7) | (group[5] << 2) | (group[6] >> 3),
                (group[6] << 5) | group[7],
            ];
            unsafe {
                core::ptr::copy_nonoverlapping(packed.as_ptr(), output, packed.len());
                output = output.add(5);
            }
        }
        input = groups.remainder();
    }
    // At most 15 live bits occur: from/to were validated in 1..8. Matching
    // the accumulator's width avoids repeated Wasm i64-to-i32 shift bridges.
    let from = from as u32;
    let to = to as u32;
    let mut accumulator = 0u32;
    let mut bits = 0u32;
    let mut index = 0usize;
    let mask = (1u32 << to) - 1;
    for value in input {
        accumulator = (accumulator << from) | *value as u32;
        bits += from;
        while bits >= to {
            bits -= to;
            unsafe {
                output
                    .add(index)
                    .write(((accumulator >> bits) & mask) as u8);
            }
            index += 1;
        }
    }
    if pad && bits != 0 {
        unsafe {
            output
                .add(index)
                .write(((accumulator << (to - bits)) & mask) as u8);
        }
    }
}
/// Input ranges must be readable; output must be writable for 90 bytes and not overlap inputs.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bech32_encode(
    hrp: *const u8,
    hrp_len: usize,
    data: *const u8,
    data_len: usize,
    modified: u64,
    output: *mut u8,
) -> i64 {
    unsafe {
        output.write_bytes(0, 90);
    }
    let out = unsafe { &mut *output.cast::<[u8; 90]>() };
    encode(
        unsafe { core::slice::from_raw_parts(hrp, hrp_len) },
        unsafe { core::slice::from_raw_parts(data, data_len) },
        modified != 0,
        out,
    )
    .map(|n| n as i64)
    .unwrap_or_else(|e| -e)
}
/// Input is borrowed; output is a disjoint writable 90-byte scratch range.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bech32_decode(input: *const u8, len: usize, output: *mut u8) -> i64 {
    unsafe {
        output.write_bytes(0, 90);
    }
    decode(unsafe { core::slice::from_raw_parts(input, len) }, unsafe {
        &mut *output.cast::<[u8; 90]>()
    })
    .map(|n| n as i64)
    .unwrap_or_else(|e| -e)
}
/// Return exact output size or a negative error. Does not write output.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bech32_convert_size(
    input: *const u8,
    len: usize,
    from: u64,
    to: u64,
    pad: u64,
) -> i64 {
    converted_len(
        unsafe { core::slice::from_raw_parts(input, len) },
        from,
        to,
        pad != 0,
    )
    .map(|n| n as i64)
    .unwrap_or_else(|e| -e)
}
/// Same validated arguments as convert_size; output has that exact size and is disjoint.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bech32_convert(
    input: *const u8,
    len: usize,
    from: u64,
    to: u64,
    pad: u64,
    output: *mut u8,
) {
    unsafe {
        convert_valid(
            core::slice::from_raw_parts(input, len),
            from,
            to,
            pad != 0,
            output,
        )
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
    #[test]
    fn published_generic_vectors() {
        for (value, modified) in [
            ("A12UEL5L", false),
            ("a12uel5l", false),
            (
                "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
                false,
            ),
            ("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw", false),
            (
                "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
                false,
            ),
            (
                "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
                false,
            ),
            ("?1ezyfcl", false),
            ("A1LQFN3A", true),
            ("a1lqfn3a", true),
            (
                "an83characterlonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11sg7hg6",
                true,
            ),
            ("abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx", true),
            (
                "11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8",
                true,
            ),
            (
                "split1checkupstagehandshakeupstreamerranterredcaperredlc445v",
                true,
            ),
            ("?1v759aa", true),
        ] {
            let mut output = [0; 90];
            let meta = decode(value.as_bytes(), &mut output).unwrap();
            assert_eq!(meta >> 16 != 0, modified);
            let hrp_len = (meta >> 8 & 255) as usize;
            let data_len = (meta & 255) as usize;
            let mut encoded = [0; 90];
            let len = encode(
                &output[..hrp_len],
                &output[hrp_len..hrp_len + data_len],
                modified,
                &mut encoded,
            )
            .unwrap();
            assert_eq!(&encoded[..len], value.to_ascii_lowercase().as_bytes());
        }
    }
    #[test]
    fn invalid_generic_vectors() {
        for value in [
            " 1nwldj5",
            "\u{7f}1axkwrx",
            "an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx",
            "pzry9x0s0muk",
            "1pzry9x0s0muk",
            "x1b4n0q5v",
            "li1dgmt3",
            "A1G7SGD8",
            "10a06t8",
            "1qzzfhee",
            "a12UEL5L",
            " 1xj0phk",
            "\u{7f}1g6xzxy",
            "an84characterslonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11d6pts4",
            "qyrz8wqd2c9m",
            "1qyrz8wqd2c9m",
            "y1b0jsk6g",
            "lt1igcx5c0",
            "in1muywd",
            "mm1crxm3i",
            "au1s5cgom",
            "M1VUXWEZ",
            "16plkw9",
            "1p2gdwpf",
        ] {
            assert!(decode(value.as_bytes(), &mut [0; 90]).is_err(), "{value}");
        }
    }
    #[test]
    fn conversion_and_padding() {
        for from in 1..=8 {
            for to in 1..=8 {
                for length in 0..65 {
                    let input: Vec<u8> = (0..length)
                        .map(|i| ((i * 13 + 7) & ((1 << from) - 1)) as u8)
                        .collect();
                    let len = converted_len(&input, from, to, true).unwrap();
                    let mut guarded = vec![0xa5; len + 2];
                    unsafe {
                        convert_valid(&input, from, to, true, guarded.as_mut_ptr().add(1));
                    }
                    assert_eq!(guarded[0], 0xa5);
                    assert_eq!(guarded[len + 1], 0xa5);
                    let round = converted_len(&guarded[1..len + 1], to, from, false);
                    // Conversion to smaller groups round-trips canonically; converting to larger
                    // groups may add a complete source group, rejected as excessive padding.
                    if from >= to {
                        let size = round.unwrap();
                        let mut out = vec![0; size];
                        unsafe {
                            convert_valid(&guarded[1..len + 1], to, from, false, out.as_mut_ptr());
                        }
                        assert_eq!(out, input);
                    }
                }
            }
        }
        assert_eq!(converted_len(&[32], 5, 8, false), Err(6));
        assert_eq!(converted_len(&[0], 5, 8, false), Err(7));
        assert_eq!(converted_len(&[0, 1], 5, 8, false), Err(7));
        assert_eq!(converted_len(&[], 0, 8, false), Err(8));
        let mut out = [0; 8];
        unsafe {
            convert_valid(&[0xff, 0], 8, 5, true, out.as_mut_ptr());
        }
        assert_eq!(&out[..4], &[31, 28, 0, 0]);
    }
    #[test]
    fn output_guards_and_immutable_input() {
        let input = b"abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw";
        let mut out = [0xa5; 92];
        assert!(
            unsafe { bech32_decode(input.as_ptr(), input.len(), out.as_mut_ptr().add(1)) } >= 0
        );
        assert_eq!(out[0], 0xa5);
        assert_eq!(out[91], 0xa5);
        assert_eq!(encode(b"", b"", false, &mut [0; 90]), Err(2));
        assert_eq!(encode(b"aB", b"", false, &mut [0; 90]), Err(3));
        assert_eq!(encode(b"a", &[32], false, &mut [0; 90]), Err(6));
        assert_eq!(encode(&[b'a'; 83], b"", true, &mut [0; 90]), Ok(90));
        assert_eq!(encode(&[b'a'; 83], &[0], true, &mut [0; 90]), Err(1));
    }
}

#[cfg(test)]
mod conversion_tests;
