//! Bounded varied-input tests of production pointer ABIs with independent bytes.
#![allow(dead_code)]
#[path = "../../../../plugins/blake3/runtime/src/lib.rs"]
mod b3;
#[path = "../../../../plugins/hmac-sha2/runtime/src/lib.rs"]
mod hmac;
#[path = "blake3_reference.rs"]
mod reference;
#[path = "../../../../plugins/ripemd160/runtime/src/lib.rs"]
mod ripe;
#[path = "../../../../plugins/sha256/runtime/src/lib.rs"]
mod sha256;
#[path = "../../../../plugins/sha512/runtime/src/lib.rs"]
mod sha512;

fn bytes(mut seed: u32, len: usize) -> Vec<u8> {
    (0..len)
        .map(|_| {
            seed ^= seed << 13;
            seed ^= seed >> 17;
            seed ^= seed << 5;
            seed as u8
        })
        .collect()
}
fn unhex(s: &str) -> Vec<u8> {
    s.as_bytes()
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(core::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}
// Every address residue is exercised; an untouched prefix/suffix surrounds outputs.
fn output(size: usize, offset: usize, f: impl FnOnce(*mut u8)) -> Vec<u8> {
    let start = 16 + offset;
    let mut arena = vec![0xa5; start + size + 16];
    f(unsafe { arena.as_mut_ptr().add(start) });
    assert!(
        arena[..start]
            .iter()
            .chain(&arena[start + size..])
            .all(|&b| b == 0xa5)
    );
    arena[start..start + size].to_vec()
}
fn borrowed(input: &[u8], offset: usize) -> Vec<u8> {
    let mut arena = vec![0x5a; 16 + offset];
    arena.extend_from_slice(input);
    arena.extend_from_slice(&[0x5a; 16]);
    arena
}
fn digest(alg: usize, key: &[u8], input: &[u8], offset: usize) -> Vec<u8> {
    let size = [32, 64, 48, 20, 32, 64][alg];
    output(size, offset, |out| unsafe {
        match alg {
            0 => sha256::sha256_digest(input.as_ptr(), input.len(), out),
            1 => sha512::sha512_digest(input.as_ptr(), input.len(), out),
            2 => sha512::sha512_digest384(input.as_ptr(), input.len(), out),
            3 => ripe::ripemd160_digest(input.as_ptr(), input.len(), out),
            4 => hmac::hmac_sha256(key.as_ptr(), key.len(), input.as_ptr(), input.len(), out),
            _ => hmac::hmac_sha512(key.as_ptr(), key.len(), input.as_ptr(), input.len(), out),
        }
    })
}
fn state_size(alg: usize) -> usize {
    [0, 216, 216, 104, 136, 272][alg]
}
fn init(alg: usize, key: &[u8], offset: usize) -> Vec<u8> {
    output(state_size(alg), offset, |out| unsafe {
        match alg {
            1 => sha512::sha512_init(out),
            2 => sha512::sha512_init384(out),
            3 => ripe::ripemd160_init(out),
            4 => hmac::hmac_sha256_init(key.as_ptr(), key.len(), out),
            _ => hmac::hmac_sha512_init(key.as_ptr(), key.len(), out),
        }
    })
}
fn update(alg: usize, state: &[u8], input: &[u8], offset: usize) -> Vec<u8> {
    output(state_size(alg), offset, |out| unsafe {
        match alg {
            1 | 2 => assert_eq!(
                sha512::sha512_update(
                    state.as_ptr(),
                    state.len(),
                    input.as_ptr(),
                    input.len(),
                    out
                ),
                1
            ),
            3 => assert_eq!(
                ripe::ripemd160_update(
                    state.as_ptr(),
                    state.len(),
                    input.as_ptr(),
                    input.len(),
                    out
                ),
                1
            ),
            4 => hmac::hmac_sha256_update(
                state.as_ptr(),
                state.len(),
                input.as_ptr(),
                input.len(),
                out,
            ),
            _ => hmac::hmac_sha512_update(
                state.as_ptr(),
                state.len(),
                input.as_ptr(),
                input.len(),
                out,
            ),
        }
    })
}
fn sum(alg: usize, state: &[u8], offset: usize) -> Vec<u8> {
    output([0, 64, 48, 20, 32, 64][alg], offset, |out| unsafe {
        match alg {
            1 => assert_eq!(sha512::sha512_sum(state.as_ptr(), state.len(), out), 1),
            2 => assert_eq!(sha512::sha512_sum384(state.as_ptr(), state.len(), out), 1),
            3 => assert_eq!(
                ripe::ripemd160_finalize(state.as_ptr(), state.len(), out),
                1
            ),
            4 => hmac::hmac_sha256_sum(state.as_ptr(), state.len(), out),
            _ => hmac::hmac_sha512_sum(state.as_ptr(), state.len(), out),
        }
    })
}
fn irregular(alg: usize, mut state: Vec<u8>, input: &[u8], offset: usize) -> Vec<u8> {
    let mut pos = 0;
    let sizes = [1, 127, 3, 64, 129, 7, 55, 128];
    let mut i = offset;
    while pos < input.len() {
        let end = (pos + sizes[i % sizes.len()]).min(input.len());
        let arena = borrowed(&state, i % 16);
        let saved = arena.clone();
        state = update(
            alg,
            &arena[16 + i % 16..16 + i % 16 + state.len()],
            &input[pos..end],
            i % 16,
        );
        assert_eq!(arena, saved);
        assert_eq!(update(alg, &state, &[], i % 16), state);
        pos = end;
        i += 1;
    }
    state
}
#[test]
fn audit5_varied_bytes_offsets_snapshots_and_prepared_hmac() {
    for (case, line) in include_str!("vectors.tsv").lines().enumerate() {
        let fields: Vec<_> = line.split('\t').collect();
        let seed: u32 = fields[0].parse().unwrap();
        let len: usize = fields[1].parse().unwrap();
        let split: usize = fields[2].parse().unwrap();
        let key = bytes(seed ^ 0xa5a55a5a, fields[3].parse().unwrap());
        let input = bytes(seed, len);
        let expected: Vec<_> = fields[4..].iter().map(|v| unhex(v)).collect();
        for offset in 0..16 {
            let arena = borrowed(&input, offset);
            let saved = arena.clone();
            let message = &arena[16 + offset..16 + offset + len];
            for alg in 0..6 {
                assert_eq!(
                    digest(alg, &key, message, offset),
                    expected[alg],
                    "case={case}, alg={alg}, offset={offset}"
                );
            }
            // The two immutable input parameters may alias, including long keys.
            for alg in 4..6 {
                assert_eq!(
                    digest(alg, message, message, offset),
                    expected[14 + alg - 4]
                );
            }
            assert_eq!(arena, saved);
        }
        for alg in 1..6 {
            let initial = init(alg, &key, case % 16);
            let prefix = irregular(alg, initial.clone(), &input[..split], case % 16);
            assert_eq!(sum(alg, &prefix, case % 16), expected[6 + alg]);
            let retained = prefix.clone();
            let streamed = irregular(alg, prefix.clone(), &input[split..], case % 16);
            let branch = update(alg, &prefix, &input[split..], case % 16);
            assert_eq!(sum(alg, &streamed, 1), expected[alg]);
            assert_eq!(sum(alg, &branch, 15), expected[alg]);
            assert_eq!(sum(alg, &prefix, 7), expected[6 + alg]);
            assert_eq!(prefix, retained);
            if alg >= 4 {
                assert_eq!(sum(alg, &initial, 3), expected[12 + alg - 4]);
                for state in [&initial, &prefix] {
                    let suffix = if state == &initial {
                        &input[..]
                    } else {
                        &input[split..]
                    };
                    let prepared = output([32, 64][alg - 4], 5, |out| unsafe {
                        if alg == 4 {
                            hmac::hmac_sha256_prepared(
                                state.as_ptr(),
                                state.len(),
                                suffix.as_ptr(),
                                suffix.len(),
                                out,
                            );
                        } else {
                            hmac::hmac_sha512_prepared(
                                state.as_ptr(),
                                state.len(),
                                suffix.as_ptr(),
                                suffix.len(),
                                out,
                            );
                        }
                    });
                    assert_eq!(prepared, expected[alg]);
                }
            }
        }
    }
}
fn b3_call(op: u64, a: &[u8], b: &[u8], seek: u64, len: usize) -> Vec<u8> {
    output(len, 3, |out| unsafe {
        let code = if op == 2 {
            b3::blake3_derive_key(a.as_ptr(), a.len(), b.as_ptr(), b.len(), out)
        } else {
            b3::blake3_run(op, a.as_ptr(), a.len(), b.as_ptr(), b.len(), seek, out, len)
        };
        assert_eq!(code, 0);
    })
}
#[test]
fn audit5_blake3_independent_context_tree_boundaries() {
    // This small, unoptimized upstream reference shares no production kernel.
    for context in [
        String::new(),
        "a\0b".into(),
        "é".repeat(32),
        "é".repeat(512),
        format!("{}z", "é".repeat(512)),
    ] {
        for len in [0, 1, 63, 64, 1024, 1025, 4097] {
            let input = bytes(0x572bd581, len);
            let mut oracle = reference::Hasher::new_derive_key(&context);
            oracle.update(&input);
            let mut expected = [0; 257];
            oracle.finalize(&mut expected);
            assert_eq!(
                b3_call(2, context.as_bytes(), &input, 0, 32),
                expected[..32]
            );
            let initial = b3_call(6, context.as_bytes(), &[], 0, 2816);
            let mut state = initial.clone();
            for chunk in input.chunks(127) {
                state = b3_call(7, &state, chunk, 0, 2816);
            }
            for (seek, count) in [(0, 257), (63, 65), (127, 130), (257, 0)] {
                assert_eq!(
                    b3_call(8, &state, &[], seek, count),
                    expected[seek as usize..seek as usize + count]
                );
            }
            assert_eq!(b3_call(7, &state, &[], 0, 2816), state);
        }
    }
}
