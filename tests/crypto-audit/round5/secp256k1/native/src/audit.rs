use super::{call, hex};

#[test]
fn audit5_independent_schnorr_padding_boundaries() {
    for (index, line) in include_str!("../../schnorr-boundaries.tsv").lines().enumerate() {
        let fields: Vec<Vec<u8>> = line.split('\t').map(hex).collect();
        assert_eq!(fields.len(), 6);
        // Offset all inputs by one byte, including the factory-owned prepared blobs.
        let unaligned: Vec<Vec<u8>> = fields.iter().map(|field| {
            let mut bytes = vec![0x5a]; bytes.extend(field); bytes
        }).collect();
        let f: Vec<&[u8]> = unaligned.iter().map(|field| &field[1..]).collect();
        let secret = call(21, f[0], &[], &[], 64);
        let public = call(19, f[1], &[], &[], 512);
        assert_eq!((secret.0, public.0), (64, 512));
        let mut secret_bytes = vec![0x5a]; secret_bytes.extend(&secret.1);
        let mut public_bytes = vec![0x5a]; public_bytes.extend(&public.1);
        assert_eq!(call(13, f[0], f[2], f[3], 64), (64, fields[4].clone()), "direct row {index}");
        assert_eq!(call(22, &secret_bytes[1..], f[2], f[3], 64), (64, fields[4].clone()), "prepared row {index}");
        for (signature, expected) in [(f[4], 1), (f[5], 0)] {
            assert_eq!(call(14, f[1], f[2], signature, 0).0, expected);
            assert_eq!(call(20, &public_bytes[1..], f[2], signature, 0).0, expected);
        }
    }
}

#[test]
fn audit5_all_operation_alignments_and_input_aliases() {
    let mut secret = [0; 32]; secret[31] = 1;
    let digest = [7; 32];
    let key = call(0, &secret, &[], &[], 33).1;
    let signature = call(7, &secret, &digest, &[], 64).1;
    let der = call(9, &signature, &[], &[], 72);
    let public_cache = call(17, &key, &[], &[], 512).1;
    let xonly = key[1..].to_vec();
    let schnorr = call(13, &secret, &digest, &digest, 64).1;
    let schnorr_cache = call(19, &xonly, &[], &[], 512).1;
    let secret_cache = call(21, &secret, &[], &[], 64).1;
    let cases: Vec<(usize, &[u8], &[u8], &[u8], usize)> = vec![
        (0, &secret, &[], &[], 33), (1, &key, &[], &[], 33), (2, &key, &[], &[], 65),
        (3, &key, &key, &[], 33), (4, &key, &secret, &[], 33), (5, &secret, &[], &[], 33),
        (6, &key, &secret, &[], 33), (7, &secret, &digest, &[], 64),
        (8, &key, &digest, &signature, 0), (9, &signature, &[], &[], 72),
        (10, &der.1[..der.0 as usize], &[], &[], 64), (11, &signature, &[], &[], 64),
        (12, &key, &[], &[], 32), (13, &secret, &digest, &digest, 64),
        (14, &xonly, &digest, &schnorr, 0), (15, &xonly, &secret, &[], 33),
        (16, &secret, &secret, &[], 32), (17, &key, &[], &[], 512),
        (18, &public_cache, &digest, &signature, 0), (19, &xonly, &[], &[], 512),
        (20, &schnorr_cache, &digest, &schnorr, 0), (21, &secret, &[], &[], 64),
        (22, &secret_cache, &digest, &digest, 64),
    ];
    for (op, a, b, c, capacity) in cases {
        let expected = call(op, a, b, c, capacity);
        assert!(expected.0 >= 0, "valid operation {op}");
        for offset in [1, 3, 7] {
            let mut arena = vec![0x5a; offset];
            arena.extend(a); arena.extend(b); arena.extend(c);
            let before = arena.clone();
            assert_eq!(call(op, &arena[offset..offset+a.len()], &arena[offset+a.len()..offset+a.len()+b.len()], &arena[offset+a.len()+b.len()..], capacity), expected, "operation {op}, offset {offset}");
            assert_eq!(arena, before);
        }
    }
    // Three equal input pointers and overlap between SEC1 payload/scalar slices
    // are legal. Only output/input aliasing is excluded by the FFI contract.
    assert_eq!(call(13, &secret, &secret, &secret, 64), call(13, &secret.to_vec(), &secret.to_vec(), &secret.to_vec(), 64));
    assert_eq!(call(3, &key, &key, &[], 33), call(6, &key, &secret, &[], 33));
    assert_eq!(call(4, &key, &key[1..], &[], 33), call(4, &key, &key[1..].to_vec(), &[], 33));
}

#[test]
fn audit5_lengths_error_precedence_and_initialized_outputs() {
    let mut secret = [0; 32]; secret[31] = 1;
    let key = call(0, &secret, &[], &[], 33).1;
    let public = call(17, &key, &[], &[], 512).1;
    let xonly = key[1..].to_vec();
    let schnorr_public = call(19, &xonly, &[], &[], 512).1;
    let schnorr_secret = call(21, &secret, &[], &[], 64).1;
    for size in [0, 1, 31, 33, 63, 64, 65, 511, 512, 513] {
        let bad = vec![0; size];
        assert_eq!(call(0, &bad, &[], &[], 33).0, -1);
        assert_eq!(call(7, &bad, &[], &[], 64).0, -1);
        assert_eq!(call(13, &bad, &[], &[], 64).0, -1);
        assert_eq!(call(16, &bad, &[], &[], 32).0, -1);
        assert_eq!(call(21, &bad, &[], &[], 64).0, -1);
        assert_eq!(call(7, &secret, &bad, &[], 64).0, -4);
        assert_eq!(call(8, &key, &bad, &[], 0).0, -4);
        assert_eq!(call(18, &public, &bad, &[], 0).0, -4);
        assert_eq!(call(13, &secret, &bad, &bad, 64).0, -6);
        assert_eq!(call(22, &schnorr_secret, &bad, &bad, 64).0, -6);
        assert_eq!(call(14, &xonly, &bad, &[], 0).0, -5);
        assert_eq!(call(20, &schnorr_public, &bad, &[], 0).0, -5);
        assert_eq!(call(8, &bad, &[], &[], 0).0, -2);
        assert_eq!(call(14, &bad, &[], &[], 0).0, -2);
        if size != 512 {
            assert_eq!(call(18, &bad, &[], &[], 0).0, -2);
            assert_eq!(call(20, &bad, &[], &[], 0).0, -2);
        }
        assert_eq!(call(22, &bad, &[], &[], 64).0, -1);
    }
    for size in [0, 1, 31, 32, 33, 63, 65, 511, 512, 513] {
        let bad = vec![0; size];
        assert_eq!(call(8, &key, &secret, &bad, 0).0, -5);
        assert_eq!(call(18, &public, &secret, &bad, 0).0, -5);
        assert_eq!(call(14, &xonly, &[], &bad, 0).0, -5);
        assert_eq!(call(20, &schnorr_public, &[], &bad, 0).0, -5);
        for op in [9, 10, 11] { assert_eq!(call(op, &bad, &[], &[], if op == 9 { 72 } else { 64 }).0, -5); }
    }
}
