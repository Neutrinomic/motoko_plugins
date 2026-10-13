use super::*;

#[path = "round5_tests.rs"]
mod round5;

#[path = "../vectors/aggregate.rs"]
mod fixtures;

// Exercise unaligned descriptors and outputs. Keep all original inputs and
// their guards intact; every error must leave the complete output untouched.
fn aggregate_call(op: u32, rows: &[AggregateInput<'_>], signature: &[u8]) -> Result<bool, u32> {
    let saved: Vec<_> = rows.iter().map(|r| (r.key.to_vec(), r.proof.to_vec(), r.message.to_vec())).collect();
    let saved_signature = signature.to_vec();
    let mut descriptors = vec![0xa5];
    for row in rows {
        for part in [row.key, row.proof, row.message] {
            let pointer = if part.is_empty() { 0 } else { part.as_ptr() as usize };
            descriptors.extend_from_slice(&pointer.to_ne_bytes());
            descriptors.extend_from_slice(&part.len().to_ne_bytes());
        }
    }
    descriptors.push(0x5a);
    let saved_descriptors = descriptors.clone();
    let mut output = [0x5a; 3];
    let status = unsafe { bls_aggregate(op, descriptors.as_ptr().add(1).cast(), rows.len(),
        signature.as_ptr(), signature.len(), output.as_mut_ptr().add(1)) };
    assert_eq!(descriptors, saved_descriptors);
    assert_eq!(signature, saved_signature);
    for (actual, expected) in rows.iter().zip(saved) {
        assert_eq!(actual.key, expected.0);
        assert_eq!(actual.proof, expected.1);
        assert_eq!(actual.message, expected.2);
    }
    assert_eq!(output[0], 0x5a);
    assert_eq!(output[2], 0x5a);
    if status == 0 { assert!(output[1] <= 1); Ok(output[1] == 1) }
    else { assert_eq!(output, [0x5a; 3]); Err(status) }
}

#[test]
fn official_profile_aggregates_and_invalid_inputs() {
    let eth_keys = fixtures::ETH_KEYS.map(hex);
    let proofs = fixtures::ETH_PROOFS.map(hex);
    let ic_keys = fixtures::IC_KEYS.map(hex);
    let messages = fixtures::MESSAGES.map(hex);
    let ic_signature = hex(fixtures::IC_AGGREGATE);
    let eth_signature = hex(fixtures::ETH_AGGREGATE);
    let same_signature = hex(fixtures::ETH_SAME_MESSAGE_AGGREGATE);
    let ic_rows: Vec<_> = (0..2).map(|i| AggregateInput { key: &ic_keys[i], proof: &[], message: &messages[i] }).collect();
    let rows: Vec<_> = (0..2).map(|i| AggregateInput { key: &eth_keys[i], proof: &proofs[i], message: &messages[i] }).collect();
    let fast: Vec<_> = rows.iter().map(|r| AggregateInput { message: &messages[0], ..*r }).collect();
    assert_eq!(aggregate_call(19, &ic_rows, &ic_signature), Ok(true));
    assert_eq!(aggregate_call(20, &rows, &eth_signature), Ok(true));
    assert_eq!(aggregate_call(21, &fast, &same_signature), Ok(true));
    assert_eq!(aggregate_call(19, &ic_rows, &hex(fixtures::IC_SIGNATURES[0])), Ok(false));
    assert_eq!(aggregate_call(20, &rows, &hex(fixtures::ETH_SIGNATURES[0])), Ok(false));
    assert_eq!(aggregate_call(21, &fast, &eth_signature), Ok(false));
    for position in 0..2 {
        let mut changed = rows.clone();
        changed[position].proof = &proofs[1-position];
        assert_eq!(aggregate_call(20, &changed, &eth_signature), Err(INVALID_PROOF));
        changed[position].proof = &[];
        assert_eq!(aggregate_call(20, &changed, &eth_signature), Err(INVALID_LENGTH));
        let mut changed = ic_rows.clone();
        changed[position].key = &[];
        assert_eq!(aggregate_call(19, &changed, &ic_signature), Err(INVALID_LENGTH));
    }
    let mut duplicate = ic_rows.clone();
    duplicate[1].message = duplicate[0].message;
    duplicate[0].key = &[];
    assert_eq!(aggregate_call(19, &duplicate, &[]), Err(DUPLICATE_MESSAGE));
    // The signature's error takes precedence over a malformed proof in the
    // general Ethereum API; the fast API checks proofs first.
    let mut malformed = rows.clone();
    malformed[0].proof = &[];
    assert_eq!(aggregate_call(20, &malformed, &[0;96]), Err(INVALID_POINT));
    assert_eq!(aggregate_call(21, &malformed, &[0;96]), Err(INVALID_LENGTH));
    for op in [19, 20, 21] {
        assert_eq!(aggregate_call(op, &[], &[]), Err(EMPTY_BATCH));
        assert_eq!(aggregate_call(op, &vec![AggregateInput::default(); 129], &[]), Err(TOO_MANY_ITEMS));
    }
    assert_eq!(aggregate_call(19, &vec![AggregateInput::default(); 128], &[]), Err(TOO_MANY_ITEMS));
    assert_eq!(aggregate_call(20, &vec![AggregateInput::default(); 128], &[]), Err(TOO_MANY_ITEMS));
    assert_eq!(aggregate_call(99, &[], &[]), Err(INVALID_ARGUMENT));
}

#[test]
fn repeated_proofs_are_reused_only_after_success_and_within_call() {
    let key = hex(fixtures::ETH_KEYS[0]);
    let proof = hex(fixtures::ETH_PROOFS[0]);
    let other_proof = hex(fixtures::ETH_PROOFS[1]);
    let message = hex(fixtures::MESSAGES[0]);
    let one = g2(&hex(fixtures::ETH_SIGNATURES[0])).unwrap();
    for count in [1usize,2,8,127,128] {
        let signature = G2Affine::from(one * Scalar::from(count as u64)).to_compressed();
        let rows = vec![AggregateInput { key: &key, proof: &proof, message: &message }; count];
        if count < 128 { assert_eq!(aggregate_call(20, &rows, &signature), Ok(true)); }
        assert_eq!(aggregate_call(21, &rows, &signature), Ok(true));
        let mut bad = rows.clone();
        bad[count-1].proof = &other_proof;
        assert_eq!(aggregate_call(21, &bad, &signature), Err(INVALID_PROOF));
        let mut bad = rows;
        bad[0].proof = &other_proof;
        assert_eq!(aggregate_call(21, &bad, &signature), Err(INVALID_PROOF));
    }
}

#[test]
fn cancelling_aggregate_key_keeps_signature_decode_precedence() {
    let secret = Scalar::from(42u64);
    let positive = G1Affine::from(G1Projective::generator() * secret).to_compressed();
    let negative = G1Affine::from(G1Projective::generator() * -secret).to_compressed();
    let proof1 = G2Affine::from(hash_g2(&positive, ETH_POP_DST) * secret).to_compressed();
    let proof2 = G2Affine::from(hash_g2(&negative, ETH_POP_DST) * -secret).to_compressed();
    let rows = [AggregateInput { key: &positive, proof: &proof1, message: b"test" },
        AggregateInput { key: &negative, proof: &proof2, message: b"test" }];
    assert_eq!(aggregate_call(21, &rows, &[0;96]), Err(INVALID_POINT));
    assert_eq!(aggregate_call(21, &rows, &[]), Err(INVALID_LENGTH));
    assert_eq!(aggregate_call(21, &rows, &G2Affine::generator().to_compressed()), Err(IDENTITY));
}

#[test]
fn duplicate_message_sort_handles_long_prefixes_and_boundaries() {
    for count in [1usize,2,8,15,16,17,127] {
        let messages: Vec<_> = (0..count).map(|i| { let mut m=vec![1;4096];m.extend_from_slice(&i.to_be_bytes());m }).collect();
        let mut inputs: Vec<_> = messages.iter().map(|m| AggregateInput { message:m,..Default::default() }).collect();
        assert!(distinct_messages(&inputs));
        if count > 1 {
            inputs[count-1].message=inputs[count-2].message;
            assert!(!distinct_messages(&inputs));
        }
    }
}
