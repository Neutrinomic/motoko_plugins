//! Independent protocol fixtures shared with the public Motoko suite.
//! All calls cross the guarded native ABI helpers, including preparation.
use super::*;

fn fixture(name: &str) -> Vec<u8> {
    let value = include_str!("../../../../tests/crypto-audit/round5/bls/vectors.tsv")
        .lines()
        .find_map(|line| {
            let (key, value) = line.split_once('\t').unwrap();
            (key == name).then_some(value)
        })
        .unwrap_or_else(|| panic!("missing fixture {name}"));
    hex(value)
}

#[test]
fn round5_ic_ciphersuites_framing_and_independent_handles() {
    let key = fixture("icKey");
    let message = fixture("message");
    let prepared = call(22, &key, &[], &[]).unwrap();
    for (name, expected) in [
        ("icSignature", true), ("icPopSignature", false), ("icAugSignature", false),
    ] {
        let signature = fixture(name);
        assert_eq!(call(14, &key, &message, &signature), Ok(vec![u8::from(expected)]), "{name}");
        assert_eq!(call(25, &prepared, &message, &signature), Ok(vec![u8::from(expected)]), "{name}");
        let row = [AggregateInput { key: &prepared, proof: &[], message: &message }];
        assert_eq!(aggregate_call(27, &row, &signature), Ok(expected), "{name}");
    }
    let framed_signature = fixture("icFramedSignature");
    let direct = [AggregateInput { key: &key, proof: &[], message: &message }];
    assert_eq!(aggregate_call(19, &direct, &fixture("icPopSignature")), Ok(false));
    let framed = fixture("icFramedMessage");
    assert_eq!(call(14, &key, &framed, &framed_signature), Ok(vec![1]));
    assert_eq!(call(14, &key, &fixture("icRoot"), &framed_signature), Ok(vec![0]));
    assert_eq!(call(25, &prepared, &framed, &framed_signature), Ok(vec![1]));
    let other = fixture("otherMessage");
    let independent = call(22, &key, &[], &[]).unwrap();
    assert_ne!(prepared.as_ptr(), independent.as_ptr());
    let mut rows = [
        AggregateInput { key: &prepared, proof: &[], message: &message },
        AggregateInput { key: &independent, proof: &[], message: &other },
    ];
    assert_eq!(aggregate_call(27, &rows, &fixture("icSameKeyAggregate")), Ok(true));
    rows[1].message = &message;
    assert_eq!(aggregate_call(27, &rows, &[]), Err(DUPLICATE_MESSAGE));
}

#[test]
fn round5_ethereum_ciphersuites_and_independent_handles() {
    let key = fixture("ethKey");
    let message = fixture("message");
    let prepared = call(23, &key, &[], &[]).unwrap();
    let proven = call(24, &key, &fixture("ethProof"), &[]).unwrap();
    for (name, expected) in [
        ("ethSignature", true), ("ethBasicSignature", false), ("ethAugSignature", false),
    ] {
        let signature = fixture(name);
        assert_eq!(call(15, &key, &message, &signature), Ok(vec![u8::from(expected)]), "{name}");
        assert_eq!(call(26, &prepared, &message, &signature), Ok(vec![u8::from(expected)]), "{name}");
        let row = [AggregateInput { key: &proven, proof: &[], message: &message }];
        for op in [28, 29] {
            assert_eq!(aggregate_call(op, &row, &signature), Ok(expected), "{name}, op {op}");
        }
    }
    let independent = call(24, &key, &fixture("ethProof"), &[]).unwrap();
    let proof = fixture("ethProof");
    let direct = [AggregateInput { key: &key, proof: &proof, message: &message }];
    assert_eq!(aggregate_call(20, &direct, &fixture("ethBasicSignature")), Ok(false));
    assert_eq!(aggregate_call(21, &direct, &fixture("ethAugSignature")), Ok(false));
    assert_ne!(proven.as_ptr(), independent.as_ptr());
    let rows = [
        AggregateInput { key: &proven, proof: &[], message: &message },
        AggregateInput { key: &independent, proof: &[], message: &message },
    ];
    for op in [28, 29] {
        assert_eq!(aggregate_call(op, &rows, &fixture("ethRepeatedSignature")), Ok(true));
    }
}

#[test]
fn round5_proof_and_signature_domains() {
    let key = fixture("ethKey");
    let signature = fixture("ethSignatureOnKey");
    let proof = fixture("ethProof");
    assert_eq!(call(15, &key, &key, &signature), Ok(vec![1]));
    assert_eq!(call(16, &key, &signature, &[]), Ok(vec![0]));
    assert_eq!(call(24, &key, &signature, &[]), Err(INVALID_PROOF));
    assert_eq!(call(16, &key, &proof, &[]), Ok(vec![1]));
    assert_eq!(call(15, &key, &key, &proof), Ok(vec![0]));
}

#[test]
fn round5_dst_boundary_independent_outputs() {
    let message = fixture("message");
    for length in [255, 256] {
        let dst = fixture(&format!("dst{length}"));
        assert_eq!(dst.len(), length);
        assert_eq!(call(11, &message, &dst, &[]), Ok(fixture(&format!("hashG1Dst{length}"))));
        assert_eq!(call(12, &message, &dst, &[]), Ok(fixture(&format!("hashG2Dst{length}"))));
    }
}
