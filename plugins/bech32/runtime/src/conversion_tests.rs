use super::*;

fn reference(input: &[u8], from: u64, to: u64, pad: bool) -> Result<Vec<u8>, i64> {
    if !(1..=8).contains(&from) || !(1..=8).contains(&to) {
        return Err(8);
    }
    if input.len() > LIMIT {
        return Err(1);
    }
    let count = if pad {
        (input.len() * from as usize).div_ceil(to as usize)
    } else {
        input.len() * from as usize / to as usize
    };
    if count > LIMIT {
        return Err(1);
    }
    if input
        .iter()
        .any(|byte| u16::from(*byte) >= 2u16.pow(from as u32))
    {
        return Err(6);
    }
    let bits: Vec<bool> = input
        .iter()
        .flat_map(|byte| (0..from).rev().map(move |bit| byte & (1 << bit) != 0))
        .collect();
    let mut output = Vec::new();
    for group in bits.chunks(to as usize) {
        if group.len() < to as usize && !pad {
            if group.len() >= from as usize || group.iter().any(|bit| *bit) {
                return Err(7);
            }
            break;
        }
        let mut value = 0;
        for bit in 0..to as usize {
            value = value * 2 + u8::from(group.get(bit).copied().unwrap_or(false));
        }
        output.push(value);
    }
    Ok(output)
}

fn check(input: &[u8], from: u64, to: u64, pad: bool) {
    let original = input.to_vec();
    let expected = reference(input, from, to, pad);
    let actual_len =
        unsafe { bech32_convert_size(input.as_ptr(), input.len(), from, to, u64::from(pad)) };
    match expected {
        Err(error) => assert_eq!(
            actual_len, -error,
            "input={input:?}, {from}->{to}, pad={pad}"
        ),
        Ok(expected) => {
            assert_eq!(actual_len, expected.len() as i64);
            let mut guarded = vec![0xa5; expected.len() + 32];
            unsafe {
                bech32_convert(
                    input.as_ptr(),
                    input.len(),
                    from,
                    to,
                    u64::from(pad),
                    guarded.as_mut_ptr().add(16),
                );
            }
            assert!(guarded[..16].iter().all(|b| *b == 0xa5));
            assert!(guarded[16 + expected.len()..].iter().all(|b| *b == 0xa5));
            assert_eq!(
                &guarded[16..16 + expected.len()],
                &expected,
                "input={input:?}, {from}->{to}, pad={pad}"
            );
        }
    }
    assert_eq!(input, original);
}

#[test]
fn independent_allwidth_bitstream_model() {
    let mut state = 0x4d59_5df4_d0f3_3173u64;
    for from in 1..=8 {
        for to in 1..=8 {
            for len in 0..=129 {
                let mask = ((1u16 << from) - 1) as u8;
                let mut random: Vec<u8> = (0..len)
                    .map(|_| {
                        state ^= state << 13;
                        state ^= state >> 7;
                        state ^= state << 17;
                        state as u8 & mask
                    })
                    .collect();
                for input in [vec![0; len], vec![mask; len], random.clone()] {
                    for pad in [false, true] {
                        check(&input, from, to, pad);
                    }
                }
                let remaining = (len * from as usize) % to as usize;
                if remaining < from as usize {
                    if let Some(last) = random.last_mut() {
                        *last &= !((1u16 << remaining) - 1) as u8;
                    }
                    check(&random, from, to, false);
                }
            }
            for byte in 0..=255 {
                check(&[byte], from, to, false);
                check(&[byte], from, to, true);
            }
        }
    }
}

#[test]
fn errors_keep_precedence_and_limits() {
    for width in [0, 9, u64::MAX] {
        check(&[255], width, 8, false);
        check(&[255], 8, width, false);
    }
    for from in 1..8 {
        for to in 1..=8 {
            for length in [1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 17, 40, 65] {
                let mut bytes = vec![0; length];
                bytes[length - 1] = 1 << from;
                check(&bytes, from, to, true);
                check(&bytes, from, to, false);
            }
        }
    }
    let input = vec![255; LIMIT + 1];
    assert_eq!(converted_len(&input, 0, 8, false), Err(8));
    assert_eq!(converted_len(&input, 5, 8, false), Err(1));
    assert_eq!(converted_len(&input[..LIMIT], 5, 1, true), Err(1));
    assert_eq!(converted_len(&input[..LIMIT], 8, 8, false), Ok(LIMIT));
    assert_eq!(converted_len(&input[..LIMIT], 8, 8, true), Ok(LIMIT));
    assert_eq!(converted_len(&input[..LIMIT], 5, 8, false), Err(6));
    let threshold = LIMIT * 5 / 8;
    assert_eq!(converted_len(&input[..threshold], 8, 5, true), Ok(LIMIT));
    assert_eq!(converted_len(&input[..threshold + 1], 8, 5, true), Err(1));
    // Same width copy reaches both bounds at the largest legal input.
    let mut guarded = vec![0xa5; LIMIT + 2];
    unsafe { convert_valid(&input[..LIMIT], 8, 8, false, guarded.as_mut_ptr().add(1)) };
    assert_eq!(guarded[0], 0xa5);
    assert_eq!(guarded[LIMIT + 1], 0xa5);
    assert_eq!(&guarded[1..LIMIT + 1], &input[..LIMIT]);
}
