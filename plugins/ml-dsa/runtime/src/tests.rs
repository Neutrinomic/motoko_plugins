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


#[test]
fn prepared_official_vectors_and_immutable_reuse() {
    stack(|| {
        for row in corpus()["sigGen"].as_array().unwrap() {
            let secret = bytes(row, "seed");
            let public = bytes(row, "pk");
            let message = bytes(row, "message");
            let context = bytes(row, "context");
            let randomness = bytes(row, "rnd");
            let mut prepared_secret = [0; SECRET_LEN];
            let mut prepared_public = [0; PUBLIC_LEN];
            assert_eq!(prepare_secret_key(&secret, &mut prepared_secret), Ok(SECRET_LEN));
            assert_eq!(prepare_public_key(&public, &mut prepared_public), Ok(PUBLIC_LEN));
            let secret_before = prepared_secret;
            let public_before = prepared_public;
            let mut output = [0; SIG_LEN];
            for _ in 0..2 {
                assert_eq!(sign_prepared(&prepared_secret, &message, &context, &randomness, &mut output), Ok(SIG_LEN));
                assert_eq!(output.as_slice(), bytes(row, "signature"), "prepared sigGen {}", row["tcId"]);
                assert_eq!(verify_prepared(&prepared_public, &message, &output, &context), Ok(true));
            }
            assert_eq!(prepared_secret, secret_before);
            assert_eq!(prepared_public, public_before);
        }
        for row in corpus()["sigVer"].as_array().unwrap() {
            let mut public = [0; PUBLIC_LEN];
            prepare_public_key(&bytes(row, "pk"), &mut public).unwrap();
            assert_eq!(verify_prepared(&public, &bytes(row, "message"), &bytes(row, "signature"), &bytes(row, "context")),
                Ok(row["testPassed"].as_bool().unwrap()));
        }
    });
}

#[test]
fn prepared_factory_boundaries_and_error_precedence() {
    stack(|| {
        let mut secret = [0; SECRET_LEN];
        let mut public = [0; PUBLIC_LEN];
        for length in [0, 1, 31, 33, 2560, SECRET_LEN] {
            assert_eq!(prepare_secret_key(&vec![0; length], &mut secret), Err(INVALID_SECRET_KEY));
        }
        for length in [0, 1, PK_LEN-1, PK_LEN+1, PUBLIC_LEN] {
            assert_eq!(prepare_public_key(&vec![0; length], &mut public), Err(INVALID_PUBLIC_KEY));
        }
        for seed in [[0; 32], [255; 32]] {
            let mut raw_public = [0; PK_LEN];
            public_key(&seed, &mut raw_public).unwrap();
            prepare_secret_key(&seed, &mut secret).unwrap();
            prepare_public_key(&raw_public, &mut public).unwrap();
            let mut signature = [0; SIG_LEN];
            for context in [vec![], vec![1; 255]] {
                sign_prepared(&secret, &[], &context, &[0; 32], &mut signature).unwrap();
                assert_eq!(verify_prepared(&public, &[], &signature, &context), Ok(true));
            }
            assert_eq!(sign_prepared(&secret, &[], &[0; 256], &[], &mut signature), Err(INVALID_CONTEXT));
            assert_eq!(sign_prepared(&secret, &[], &[], &[], &mut signature), Err(INVALID_RANDOMNESS));
            assert_eq!(verify_prepared(&public, &[], &[], &[0; 256]), Err(INVALID_SIGNATURE));
            assert_eq!(verify_prepared(&public, &[], &signature, &[0; 256]), Err(INVALID_CONTEXT));
        }
    });
}

#[test]
fn prepared_abi_bounds_unaligned_payloads_and_error_initialization() {
    stack(|| {
        let seed = [7; 32];
        let mut public = [0; PK_LEN];
        public_key(&seed, &mut public).unwrap();
        let mut public_guard = vec![0xa5; PUBLIC_LEN + 2];
        let mut secret_guard = vec![0xa5; SECRET_LEN + 2];
        let mut signature_guard = [0xa5; SIG_LEN + 2];
        unsafe {
            assert_eq!(mldsa_prepare_public_key(public.as_ptr(), PK_LEN, public_guard[1..].as_mut_ptr()), PUBLIC_LEN as i64);
            assert_eq!(mldsa_prepare_secret_key(seed.as_ptr(), 32, secret_guard[1..].as_mut_ptr()), SECRET_LEN as i64);
        }
        let public_before = public_guard.clone();
        let secret_before = secret_guard.clone();
        unsafe {
            assert_eq!(mldsa_sign_prepared(secret_guard[1..].as_ptr(), core::ptr::null(), 0,
                core::ptr::null(), 0, signature_guard[1..].as_mut_ptr()), SIG_LEN as i64);
            assert_eq!(mldsa_verify_prepared(public_guard[1..].as_ptr(), core::ptr::null(), 0,
                signature_guard[1..].as_ptr(), SIG_LEN, core::ptr::null(), 0), 1);
            assert_eq!(mldsa_sign_randomized_prepared(secret_guard[1..].as_ptr(), core::ptr::null(), 0,
                core::ptr::null(), 0, seed.as_ptr(), 32, signature_guard[1..].as_mut_ptr()), SIG_LEN as i64);
            assert_eq!(mldsa_verify_prepared(public_guard[1..].as_ptr(), core::ptr::null(), 0,
                signature_guard[1..].as_ptr(), SIG_LEN, core::ptr::null(), 0), 1);
        }
        assert_eq!(public_guard, public_before);
        assert_eq!(secret_guard, secret_before);
        assert_eq!((signature_guard[0], signature_guard[SIG_LEN + 1]), (0xa5, 0xa5));
        unsafe {
            assert_eq!(mldsa_prepare_public_key(core::ptr::null(), 0, public_guard[1..].as_mut_ptr()), INVALID_PUBLIC_KEY);
            assert_eq!(mldsa_prepare_secret_key(core::ptr::null(), 0, secret_guard[1..].as_mut_ptr()), INVALID_SECRET_KEY);
        }
        for (guard, length) in [(&public_guard, PUBLIC_LEN), (&secret_guard, SECRET_LEN)] {
            assert_eq!((guard[0], guard[length + 1]), (0xa5, 0xa5));
            assert!(guard[1..=length].iter().all(|&byte| byte == 0));
        }
    });
}

// Round-five tests reuse official answers; malformed encodings preserve the
// mathematical hint set, so challenge mismatch cannot hide a lax decoder.
#[test]
fn canonical_hint_malleability_for_each_polynomial() {
    stack(|| {
        let data = corpus();
        for id in [4, 373] {
            let row = data["sigGen"].as_array().unwrap().iter()
                .find(|row| row["tcId"] == id).unwrap();
            let public = bytes(row, "pk");
            let message = bytes(row, "message");
            let ctx = bytes(row, "context");
            let signature = bytes(row, "signature");
            let mut prepared_public = [0; PUBLIC_LEN];
            prepare_public_key(&public, &mut prepared_public).unwrap();
            let check = |sig: &[u8], expected| {
                assert_eq!(verify(&public, &message, sig, &ctx), Ok(expected));
                assert_eq!(verify_prepared(&prepared_public, &message, sig, &ctx), Ok(expected));
            };
            check(&signature, true);
            let used = usize::from(signature[2419]);
            assert!(used < 79);
            let mut start = 0;
            for row in 0..4 {
                let end = usize::from(signature[2416 + row]);
                assert!(end >= start + 2);
                // Unsorting leaves precisely the same set of hint positions.
                let mut bad = signature.clone();
                bad.swap(2336 + start, 2336 + start + 1);
                check(&bad, false);
                // Inserting a duplicate also leaves the decoded bitset intact.
                // Shift later positions and every affected row endpoint.
                let mut bad = signature.clone();
                bad.copy_within(2336 + start..2336 + used, 2336 + start + 1);
                for count in &mut bad[2416 + row..2420] { *count += 1; }
                check(&bad, false);
                start = end;
            }
            // Ignoring either end of the unused padding must not be accepted.
            for position in [2336 + used, 2415] {
                let mut bad = signature.clone();
                assert_eq!(bad[position], 0);
                bad[position] = 1;
                check(&bad, false);
            }
            check(&signature, true);
        }
    });
}

// Every guard has a nonempty prefix/suffix, and allocations can be deliberately
// unaligned. Inputs are snapshotted in full, including their surrounding bytes.
struct AbiGuard {
    bytes: Vec<u8>,
    offset: usize,
    length: usize,
}
impl AbiGuard {
    fn new(value: &[u8], offset: usize) -> Self {
        let mut bytes = vec![0xa5; offset + value.len() + 9];
        bytes[offset..offset + value.len()].copy_from_slice(value);
        Self { bytes, offset, length: value.len() }
    }
    fn ptr(&self) -> *const u8 { self.bytes[self.offset..].as_ptr() }
    fn mut_ptr(&mut self) -> *mut u8 { self.bytes[self.offset..].as_mut_ptr() }
    fn payload(&self) -> &[u8] { &self.bytes[self.offset..self.offset + self.length] }
    fn assert_output(&self, value: &[u8]) {
        assert_eq!(self.payload(), value);
        assert!(self.bytes[..self.offset].iter().all(|&b| b == 0xa5));
        assert!(self.bytes[self.offset + self.length..].iter().all(|&b| b == 0xa5));
    }
    fn poison(&mut self) { self.bytes.fill(0xa5); }
}

#[test]
fn abi_all_byte_alignments_match_official_answers() {
    stack(|| {
        let data = corpus();
        for id in [4, 373] {
            let row = data["sigGen"].as_array().unwrap().iter()
                .find(|row| row["tcId"] == id).unwrap();
            for offset in 1..=8 {
                let secret = AbiGuard::new(&bytes(row, "seed"), offset);
                let message = AbiGuard::new(&bytes(row, "message"), 9 - offset);
                let ctx = AbiGuard::new(&bytes(row, "context"), offset);
                let rnd = AbiGuard::new(&bytes(row, "rnd"), 9 - offset);
                let inputs = [&secret, &message, &ctx, &rnd].map(|g| g.bytes.clone());
                let mut public = AbiGuard::new(&[0xa5; PK_LEN], 9 - offset);
                let mut signature = AbiGuard::new(&[0xa5; SIG_LEN], offset);
                let mut pk = AbiGuard::new(&[0xa5; PUBLIC_LEN], offset);
                let mut sk = AbiGuard::new(&[0xa5; SECRET_LEN], 9 - offset);
                unsafe {
                    assert_eq!(mldsa_public_key(secret.ptr(), 32, public.mut_ptr()), PK_LEN as i64);
                    public.assert_output(&bytes(row, "pk"));
                    assert_eq!(mldsa_prepare_public_key(public.ptr(), PK_LEN, pk.mut_ptr()), PUBLIC_LEN as i64);
                    assert_eq!(mldsa_prepare_secret_key(secret.ptr(), 32, sk.mut_ptr()), SECRET_LEN as i64);
                    let saved_pk = pk.bytes.clone();
                    let saved_sk = sk.bytes.clone();
                    assert_eq!(mldsa_sign_randomized(secret.ptr(), 32, message.ptr(), message.length,
                        ctx.ptr(), ctx.length, rnd.ptr(), 32, signature.mut_ptr()), SIG_LEN as i64);
                    signature.assert_output(&bytes(row, "signature"));
                    assert_eq!(mldsa_verify(public.ptr(), PK_LEN, message.ptr(), message.length,
                        signature.ptr(), SIG_LEN, ctx.ptr(), ctx.length), 1);
                    signature.poison();
                    assert_eq!(mldsa_sign_randomized_prepared(sk.ptr(), message.ptr(), message.length,
                        ctx.ptr(), ctx.length, rnd.ptr(), 32, signature.mut_ptr()), SIG_LEN as i64);
                    signature.assert_output(&bytes(row, "signature"));
                    assert_eq!(mldsa_verify_prepared(pk.ptr(), message.ptr(), message.length,
                        signature.ptr(), SIG_LEN, ctx.ptr(), ctx.length), 1);
                    if row["deterministic"].as_bool().unwrap() {
                        signature.poison();
                        assert_eq!(mldsa_sign(secret.ptr(), 32, message.ptr(), message.length,
                            ctx.ptr(), ctx.length, signature.mut_ptr()), SIG_LEN as i64);
                        signature.assert_output(&bytes(row, "signature"));
                        signature.poison();
                        assert_eq!(mldsa_sign_prepared(sk.ptr(), message.ptr(), message.length,
                            ctx.ptr(), ctx.length, signature.mut_ptr()), SIG_LEN as i64);
                        signature.assert_output(&bytes(row, "signature"));
                    }
                    pk.assert_output(&saved_pk[pk.offset..pk.offset + PUBLIC_LEN]);
                    sk.assert_output(&saved_sk[sk.offset..sk.offset + SECRET_LEN]);
                    assert_eq!(pk.bytes, saved_pk);
                    assert_eq!(sk.bytes, saved_sk);
                }
                public.assert_output(&bytes(row, "pk"));
                for (input, before) in [&secret, &message, &ctx, &rnd].into_iter().zip(inputs) {
                    assert_eq!(input.bytes, before);
                }
            }
        }
    });
}

#[test]
fn abi_failures_zero_exact_outputs_and_leave_live_handles_usable() {
    stack(|| {
        let seed = [7; 33];
        let mut public = [0; PK_LEN];
        public_key(&seed[..32], &mut public).unwrap();
        let mut pk = [0; PUBLIC_LEN];
        let mut sk = [0; SECRET_LEN];
        prepare_public_key(&public, &mut pk).unwrap();
        prepare_secret_key(&seed[..32], &mut sk).unwrap();
        let saved_pk = pk;
        let saved_sk = sk;
        let ctx = [0; 256];
        let rnd = [0; 33];
        for offset in 1..=8 {
            let mut output = AbiGuard::new(&[0xa5; PK_LEN], offset);
            unsafe { assert_eq!(mldsa_public_key(seed.as_ptr(), 31, output.mut_ptr()), INVALID_SECRET_KEY); }
            output.assert_output(&[0; PK_LEN]);
            let mut output = AbiGuard::new(&[0xa5; PUBLIC_LEN], offset);
            unsafe { assert_eq!(mldsa_prepare_public_key(public.as_ptr(), PK_LEN - 1, output.mut_ptr()), INVALID_PUBLIC_KEY); }
            output.assert_output(&[0; PUBLIC_LEN]);
            let mut output = AbiGuard::new(&[0xa5; SECRET_LEN], offset);
            unsafe { assert_eq!(mldsa_prepare_secret_key(seed.as_ptr(), 33, output.mut_ptr()), INVALID_SECRET_KEY); }
            output.assert_output(&[0; SECRET_LEN]);
            let mut output = AbiGuard::new(&[0xa5; SIG_LEN], offset);
            // All combinations exercise status priority and initialization through
            // the exported ABI, including simultaneous context/randomness errors.
            for (secret_len, context_len, rnd_len, expected) in [
                (31, 256, 31, INVALID_SECRET_KEY), (32, 256, 31, INVALID_CONTEXT),
                (32, 0, 0, INVALID_RANDOMNESS), (32, 0, 31, INVALID_RANDOMNESS),
                (32, 0, 33, INVALID_RANDOMNESS),
            ] {
                output.poison();
                unsafe { assert_eq!(mldsa_sign_randomized(seed.as_ptr(), secret_len, core::ptr::null(), 0,
                    ctx.as_ptr(), context_len, rnd.as_ptr(), rnd_len, output.mut_ptr()), expected); }
                output.assert_output(&[0; SIG_LEN]);
                if secret_len == 32 {
                    output.poison();
                    unsafe { assert_eq!(mldsa_sign_randomized_prepared(sk.as_ptr(), core::ptr::null(), 0,
                        ctx.as_ptr(), context_len, rnd.as_ptr(), rnd_len, output.mut_ptr()), expected); }
                    output.assert_output(&[0; SIG_LEN]);
                }
            }
            output.poison();
            unsafe { assert_eq!(mldsa_sign(seed.as_ptr(), 32, core::ptr::null(), 0,
                ctx.as_ptr(), 256, output.mut_ptr()), INVALID_CONTEXT); }
            output.assert_output(&[0; SIG_LEN]);
            output.poison();
            unsafe { assert_eq!(mldsa_sign_prepared(sk.as_ptr(), core::ptr::null(), 0,
                ctx.as_ptr(), 256, output.mut_ptr()), INVALID_CONTEXT); }
            output.assert_output(&[0; SIG_LEN]);
        }
        assert_eq!(pk, saved_pk);
        assert_eq!(sk, saved_sk);
        let mut signature = [0; SIG_LEN];
        sign_prepared(&sk, b"still usable", &[], &[0; 32], &mut signature).unwrap();
        assert_eq!(verify_prepared(&pk, b"still usable", &signature, &[]), Ok(true));
    });
}

#[test]
fn binary_context_framing_and_shared_readonly_inputs() {
    stack(|| {
        let seed = [0x80; 32];
        let mut public = [0; PK_LEN];
        public_key(&seed, &mut public).unwrap();
        let mut pk = [0; PUBLIC_LEN];
        let mut sk = [0; SECRET_LEN];
        prepare_public_key(&public, &mut pk).unwrap();
        prepare_secret_key(&seed, &mut sk).unwrap();
        for (message, ctx, other_message, other_ctx) in [
            (&b"b\0c"[..], &b"a"[..], &b"\0c"[..], &b"ab"[..]),
            (&b"\0\xffa"[..], &b""[..], &b"a"[..], &b"\0\xff"[..]),
        ] {
            assert_eq!([ctx, message].concat(), [other_ctx, other_message].concat());
            let mut signature = [0; SIG_LEN];
            sign(&seed, message, ctx, &[0; 32], &mut signature).unwrap();
            let mut repeated = [0; SIG_LEN];
            sign_prepared(&sk, message, ctx, &[0; 32], &mut repeated).unwrap();
            assert_eq!(signature, repeated);
            assert_eq!(verify(&public, message, &signature, ctx), Ok(true));
            assert_eq!(verify_prepared(&pk, other_message, &signature, other_ctx), Ok(false));
            assert_eq!(verify(&public, other_message, &signature, other_ctx), Ok(false));
        }
        // The ABI permits overlapping immutable inputs. Here all four inputs
        // alias, whereas the output remains disjoint as the contract requires.
        let mut expected = [0; SIG_LEN];
        sign(&seed, &seed, &seed, &seed, &mut expected).unwrap();
        let mut output = [0; SIG_LEN];
        unsafe {
            assert_eq!(mldsa_sign_randomized(seed.as_ptr(), 32, seed.as_ptr(), 32,
                seed.as_ptr(), 32, seed.as_ptr(), 32, output.as_mut_ptr()), SIG_LEN as i64);
            assert_eq!(output, expected);
            assert_eq!(mldsa_sign_randomized_prepared(sk.as_ptr(), seed.as_ptr(), 32,
                seed.as_ptr(), 32, seed.as_ptr(), 32, output.as_mut_ptr()), SIG_LEN as i64);
        }
        assert_eq!(output, expected);
        assert_eq!(seed, [0x80; 32]);
        assert_eq!(verify(&public, &seed, &output, &seed), Ok(true));
    });
}

#[test]
fn public_key_coefficient_extremes_are_canonical_encodings() {
    stack(|| {
        let data = corpus();
        let row = &data["sigGen"][3];
        for byte in [0, 255] {
            // t1 uses the full ten-bit range. In particular, all-one packed t1
            // scales to q-1, not an out-of-range or noncanonical coefficient.
            let public = [byte; PK_LEN];
            let decoded = PublicKey::try_from_bytes(public).unwrap();
            assert_eq!(decoded.into_bytes(), public);
            let mut prepared = [0; PUBLIC_LEN];
            assert_eq!(prepare_public_key(&public, &mut prepared), Ok(PUBLIC_LEN));
            let message = bytes(row, "message");
            let signature = bytes(row, "signature");
            let context = bytes(row, "context");
            assert_eq!(verify(&public, &message, &signature, &context), Ok(false));
            assert_eq!(verify_prepared(&prepared, &message, &signature, &context), Ok(false));
        }
    });
}
