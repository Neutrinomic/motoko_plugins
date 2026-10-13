use super::*;

#[path = "../vectors/aggregate.rs"]
mod vectors;

fn hex(input: &str) -> Vec<u8> {
    input.as_bytes().chunks_exact(2).map(|pair| {
        u8::from_str_radix(core::str::from_utf8(pair).unwrap(), 16).unwrap()
    }).collect()
}

fn call(op: u32, a: &[u8], b: &[u8], c: &[u8]) -> Result<Vec<u8>, u32> {
    let size = match op { 22 => PREPARED_IC_BYTES, 23 | 24 => PREPARED_ETH_BYTES, _ => 1 };
    let mut guarded = vec![0xa5; size + 16];
    let before = [a.to_vec(), b.to_vec(), c.to_vec()];
    let status = unsafe { bls_call(op, a.as_ptr(), a.len(), b.as_ptr(), b.len(),
        c.as_ptr(), c.len(), guarded.as_mut_ptr().add(8)) };
    assert_eq!(&guarded[..8], &[0xa5; 8]);
    assert_eq!(&guarded[size + 8..], &[0xa5; 8]);
    assert_eq!([a, b, c], [&before[0][..], &before[1][..], &before[2][..]]);
    if status == 0 { Ok(guarded[8..size + 8].to_vec()) }
    else { assert!(guarded.iter().all(|byte| *byte == 0xa5)); Err(status) }
}

#[test]
fn immutable_generator_table_matches_fresh_preparation() {
    let mut table = [0xa5; G2_PREPARED_BYTES];
    assert!(write_g2_prepared(&G2Affine::generator(), &mut table));
    assert_eq!(&table, &G2_GENERATOR_TABLE.0);
    assert_eq!((G2_GENERATOR_TABLE.0.as_ptr() as usize) % 8, 0);
    let point = G1Affine::generator();
    let ordinary = G2Prepared::from(G2Affine::generator());
    assert_eq!(prepared_miller_loop(&[(&point, G2PreparedSource::TrustedBytes(&table))])
        .final_exponentiation(), bls12_381::multi_miller_loop(&[(&point, &ordinary)])
        .final_exponentiation());
}

#[test]
fn prepared_factories_and_interleaved_single_verification() {
    let messages = vectors::MESSAGES.map(hex);
    for (prepare, verify, keys, signatures) in [
        (22, 25, vectors::IC_KEYS.map(hex), vectors::IC_SIGNATURES.map(hex)),
        (23, 26, vectors::ETH_KEYS.map(hex), vectors::ETH_SIGNATURES.map(hex)),
    ] {
        let prepared = keys.each_ref().map(|key| call(prepare, key, &[], &[]).unwrap());
        for i in [0, 1, 0, 1] {
            assert_eq!(&prepared[i][..keys[i].len()], &keys[i]);
            assert_eq!(call(prepare, &keys[i], &[], &[]).unwrap(), prepared[i]);
            assert_eq!(call(verify, &prepared[i], &messages[i], &signatures[i]), Ok(vec![1]));
            assert_eq!(call(verify, &prepared[i], &messages[1 - i], &signatures[i]), Ok(vec![0]));
            assert_eq!(call(verify, &prepared[i], &messages[i], &[]), Err(INVALID_LENGTH));
        }
    }
    for i in 0..2 {
        let key = hex(vectors::ETH_KEYS[i]);
        let proof = hex(vectors::ETH_PROOFS[i]);
        assert_eq!(call(24, &key, &proof, &[]), call(23, &key, &[], &[]));
        assert_eq!(call(24, &key, &hex(vectors::ETH_PROOFS[1-i]), &[]), Err(INVALID_PROOF));
        assert_eq!(call(24, &key, &[], &[]), Err(INVALID_LENGTH));
    }
}

#[test]
fn factories_reject_external_invalid_keys_without_writing_output() {
    for (op, identity) in [(22, G2_IDENTITY_BYTES.to_vec()), (23, G1_IDENTITY_BYTES.to_vec())] {
        assert_eq!(call(op, &[], &[], &[]), Err(INVALID_LENGTH));
        assert_eq!(call(op, &identity, &[], &[]), Err(IDENTITY));
        assert_eq!(call(op, &vec![0; identity.len()], &[], &[]), Err(INVALID_POINT));
        assert_eq!(call(op, &vec![0xff; identity.len()], &[], &[]), Err(INVALID_POINT));
        assert_eq!(call(op, &identity[..identity.len()-1], &[], &[]), Err(INVALID_LENGTH));
    }
    // PoP retains the raw verification decoder precedence: both points decode
    // before a valid identity is rejected, and no failed proof creates a token.
    assert_eq!(call(24, &G1_IDENTITY_BYTES, &[], &[]), Err(INVALID_LENGTH));
    assert_eq!(call(24, &G1_IDENTITY_BYTES, &G2_IDENTITY_BYTES, &[]), Err(IDENTITY));
    assert_eq!(call(24, &hex(vectors::ETH_KEYS[0]), &G2_IDENTITY_BYTES, &[]), Err(IDENTITY));
}

#[test]
fn prepared_aggregates_match_independent_profile_vectors() {
    let messages = vectors::MESSAGES.map(hex);
    let ic = vectors::IC_KEYS.map(|key| call(22, &hex(key), &[], &[]).unwrap());
    let eth: [Vec<u8>; 2] = core::array::from_fn(|i| {
        call(24, &hex(vectors::ETH_KEYS[i]), &hex(vectors::ETH_PROOFS[i]), &[]).unwrap()
    });
    fn rows<'a>(keys: &'a [Vec<u8>; 2], messages: &'a [Vec<u8>; 2]) -> [AggregateInput<'a>; 2] {
        core::array::from_fn(|i| AggregateInput { key: &keys[i], proof: &[], message: &messages[i] })
    }
    assert_eq!(aggregate_ic_prepared(&rows(&ic, &messages), &hex(vectors::IC_AGGREGATE)), Ok(true));
    assert_eq!(aggregate_eth_prepared(&rows(&eth, &messages), &hex(vectors::ETH_AGGREGATE)), Ok(true));
    let fast: [_; 2] = core::array::from_fn(|i| AggregateInput {
        key: &eth[i], proof: &[], message: &messages[0],
    });
    assert_eq!(fast_aggregate_eth_prepared(&fast, &hex(vectors::ETH_SAME_MESSAGE_AGGREGATE)), Ok(true));
    let duplicate: [_; 2] = core::array::from_fn(|i| AggregateInput {
        key: &ic[i], proof: &[], message: &messages[0],
    });
    assert_eq!(aggregate_ic_prepared(&duplicate, &[]), Err(DUPLICATE_MESSAGE));
    assert_eq!(aggregate_eth_prepared(&rows(&eth, &messages), &G2_IDENTITY_BYTES), Err(IDENTITY));
    assert_eq!(fast_aggregate_eth_prepared(&fast, &G2_IDENTITY_BYTES), Err(IDENTITY));
    for op in [27, 28, 29] {
        let mut output = 0xa5;
        assert_eq!(unsafe { bls_aggregate(op, core::ptr::null(), 0,
            core::ptr::null(), 0, &mut output) }, EMPTY_BATCH);
        assert_eq!(unsafe { bls_aggregate(op, core::ptr::null(), 129,
            core::ptr::null(), 0, &mut output) }, TOO_MANY_ITEMS);
        assert_eq!(output, 0xa5);
    }
}
