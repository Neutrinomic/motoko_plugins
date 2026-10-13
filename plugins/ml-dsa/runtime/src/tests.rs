use super::*;
use serde_json::Value;

fn hex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}
fn bytes(row: &Value, field: &str) -> Vec<u8> {
    hex(row[field].as_str().unwrap())
}
fn corpus() -> Value {
    serde_json::from_str(include_str!("../../tests/vectors/acvp-ml-dsa-44.json")).unwrap()
}
// Debug-build polynomial temporaries use more native stack than optimized Wasm.
fn stack(test: impl FnOnce() + Send + 'static) {
    std::thread::Builder::new()
        .stack_size(8 * 1024 * 1024)
        .spawn(test)
        .unwrap()
        .join()
        .unwrap();
}

#[test]
fn official_acvp_25_keygen_answers() {
    stack(|| {
        for row in corpus()["keyGen"].as_array().unwrap() {
            let mut output = [0; PK_LEN];
            assert_eq!(public_key(&bytes(row, "seed"), &mut output), Ok(PK_LEN));
            assert_eq!(
                output.as_slice(),
                bytes(row, "pk"),
                "keyGen tcId {}",
                row["tcId"]
            );
        }
    });
}

#[test]
fn official_acvp_30_external_deterministic_and_randomized_signatures() {
    stack(|| {
        for row in corpus()["sigGen"].as_array().unwrap() {
            let mut output = [0; SIG_LEN];
            let secret = bytes(row, "seed");
            let message = bytes(row, "message");
            let context = bytes(row, "context");
            let randomness = bytes(row, "rnd");
            let signature = bytes(row, "signature");
            assert_eq!(
                sign(&secret, &message, &context, &randomness, &mut output),
                Ok(SIG_LEN)
            );
            assert_eq!(output.as_slice(), signature, "sigGen tcId {}", row["tcId"]);
            assert_eq!(
                verify(&bytes(row, "pk"), &message, &output, &context),
                Ok(true)
            );
        }
    });
}

#[test]
fn official_acvp_15_external_verification_answers() {
    stack(|| {
        for row in corpus()["sigVer"].as_array().unwrap() {
            assert_eq!(
                verify(
                    &bytes(row, "pk"),
                    &bytes(row, "message"),
                    &bytes(row, "signature"),
                    &bytes(row, "context")
                ),
                Ok(row["testPassed"].as_bool().unwrap()),
                "sigVer tcId {}: {}",
                row["tcId"],
                row["reason"]
            );
        }
    });
}

#[test]
fn input_boundaries_and_error_precedence() {
    stack(|| {
        let mut output = [0; SIG_LEN];
        let seed = [0; 32];
        let pk = [0; PK_LEN];
        let sig = [0; SIG_LEN];
        let long_context = [0; 256];
        for len in [0, 1, 31, 33, 2560] {
            let invalid = vec![0; len];
            assert_eq!(public_key(&invalid, &mut output), Err(INVALID_SECRET_KEY));
            assert_eq!(
                sign(&invalid, &[], &long_context, &[], &mut output),
                Err(INVALID_SECRET_KEY)
            );
        }
        for len in [0, 1, PK_LEN - 1, PK_LEN + 1] {
            assert_eq!(
                verify(&vec![0; len], &[], &[], &long_context),
                Err(INVALID_PUBLIC_KEY)
            );
        }
        for len in [0, 1, SIG_LEN - 1, SIG_LEN + 1] {
            assert_eq!(
                verify(&pk, &[], &vec![0; len], &long_context),
                Err(INVALID_SIGNATURE)
            );
        }
        assert_eq!(verify(&pk, &[], &sig, &long_context), Err(INVALID_CONTEXT));
        assert_eq!(
            sign(&seed, &[], &long_context, &[], &mut output),
            Err(INVALID_CONTEXT)
        );
        for len in [0, 1, 31, 33] {
            assert_eq!(
                sign(&seed, &[], &[], &vec![0; len], &mut output),
                Err(INVALID_RANDOMNESS)
            );
        }
        // Every 32-byte seed is valid; no scalar-range restriction applies.
        for seed in [[0; 32], [255; 32]] {
            let mut public = [0; PK_LEN];
            assert_eq!(public_key(&seed, &mut public), Ok(PK_LEN));
            for context in [vec![], vec![0; 255]] {
                assert_eq!(
                    sign(&seed, &[], &context, &[0; 32], &mut output),
                    Ok(SIG_LEN)
                );
                assert_eq!(verify(&public, &[], &output, &context), Ok(true));
            }
        }
    });
}

#[test]
fn context_message_randomness_and_key_are_bound() {
    stack(|| {
        let seed = [42; 32];
        let mut pk = [0; PK_LEN];
        let mut wrong_pk = [0; PK_LEN];
        let mut signature = [0; SIG_LEN];
        let mut randomized = [0; SIG_LEN];
        public_key(&seed, &mut pk).unwrap();
        public_key(&[43; 32], &mut wrong_pk).unwrap();
        sign(&seed, b"payload", b"domain", &[0; 32], &mut signature).unwrap();
        sign(&seed, b"payload", b"domain", &[1; 32], &mut randomized).unwrap();
        assert_ne!(signature, randomized);
        assert_eq!(verify(&pk, b"payload", &randomized, b"domain"), Ok(true));
        assert_eq!(verify(&pk, b"payload!", &signature, b"domain"), Ok(false));
        assert_eq!(verify(&pk, b"payload", &signature, b"other"), Ok(false));
        assert_eq!(verify(&pk, b"payload", &signature, b""), Ok(false));
        assert_eq!(
            verify(&wrong_pk, b"payload", &signature, b"domain"),
            Ok(false)
        );
        let mut repeated = [0; SIG_LEN];
        sign(&seed, b"payload", b"domain", &[0; 32], &mut repeated).unwrap();
        assert_eq!(signature, repeated);
    });
}

#[test]
fn malformed_hints_norms_and_commitment_return_false_without_panics() {
    stack(|| {
        let data = corpus();
        let row = &data["sigGen"][3]; // Official deterministic one-byte message.
        let pk = bytes(row, "pk");
        let message = bytes(row, "message");
        let context = bytes(row, "context");
        let signature = bytes(row, "signature");
        let check = |bad: &[u8]| assert_eq!(verify(&pk, &message, bad, &context), Ok(false));
        let mut bad = signature.clone();
        bad[0] ^= 1; // challenge commitment
        check(&bad);
        bad = signature.clone();
        bad[32] = 0;
        bad[33] = 0;
        bad[34] &= 0xfc; // z[0] = gamma1: norm too large
        check(&bad);
        bad = signature.clone();
        bad[2416] = 81; // hint count exceeds omega
        check(&bad);
        bad = signature.clone();
        bad[2416] = 2;
        bad[2417] = 1; // decreasing count
        check(&bad);
        bad = signature.clone();
        bad[2336..].fill(0);
        bad[2336] = 1;
        bad[2337] = 1;
        bad[2416..].fill(2); // duplicate hint positions
        check(&bad);
        bad = signature.clone();
        bad[2336..].fill(0);
        bad[2336] = 1; // unused hint padding
        check(&bad);
        check(&[0; SIG_LEN]);
        check(&[255; SIG_LEN]);
        // Deterministic mutation corpus spreads changes through c, z and hints.
        for index in (0..SIG_LEN).step_by(37) {
            bad = signature.clone();
            bad[index] ^= 1;
            check(&bad);
        }
        assert_eq!(verify(&pk, &message, &signature, &context), Ok(true));
    });
}

#[test]
fn abi_outputs_are_bounded_initialized_and_independent() {
    stack(|| {
        let mut public_guard = [0xa5; PK_LEN + 2];
        let seed = [7; 32];
        let mut sig_guard = [0xa5; SIG_LEN + 2];
        unsafe {
            assert_eq!(
                mldsa_public_key(seed.as_ptr(), seed.len(), public_guard[1..].as_mut_ptr()),
                PK_LEN as i64
            );
            assert_eq!(
                mldsa_sign(
                    seed.as_ptr(),
                    seed.len(),
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0,
                    sig_guard[1..].as_mut_ptr()
                ),
                SIG_LEN as i64
            );
            assert_eq!(
                mldsa_verify(
                    public_guard[1..].as_ptr(),
                    PK_LEN,
                    core::ptr::null(),
                    0,
                    sig_guard[1..].as_ptr(),
                    SIG_LEN,
                    core::ptr::null(),
                    0
                ),
                1
            );
        }
        assert_eq!((public_guard[0], public_guard[PK_LEN + 1]), (0xa5, 0xa5));
        assert_eq!((sig_guard[0], sig_guard[SIG_LEN + 1]), (0xa5, 0xa5));
        let saved = sig_guard;
        unsafe {
            assert_eq!(
                mldsa_sign(
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0,
                    core::ptr::null(),
                    0,
                    sig_guard[1..].as_mut_ptr()
                ),
                INVALID_SECRET_KEY
            );
        }
        assert!(sig_guard[1..=SIG_LEN].iter().all(|&b| b == 0));
        assert_eq!((sig_guard[0], sig_guard[SIG_LEN + 1]), (0xa5, 0xa5));
        assert_eq!(
            verify(&public_guard[1..=PK_LEN], &[], &saved[1..=SIG_LEN], &[]),
            Ok(true)
        );
    });
}
