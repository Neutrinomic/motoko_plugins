use super::*;

#[path = "../vectors/ethereum.rs"]
mod ethereum;
#[path = "../vectors/rfc9380.rs"]
mod rfc9380;

fn hex(bytes: &str) -> Vec<u8> {
    bytes
        .trim_start_matches("0x")
        .as_bytes()
        .chunks_exact(2)
        .map(|b| {
            let digit = |c: u8| match c {
                b'0'..=b'9' => c - b'0',
                b'a'..=b'f' => c - b'a' + 10,
                _ => panic!("hex"),
            };
            digit(b[0]) * 16 + digit(b[1])
        })
        .collect()
}

// Exercise the exported ABI at unaligned addresses, guard every output byte,
// and prove input immutability even on early failures.
fn call(op: u32, a: &[u8], b: &[u8], c: &[u8]) -> Result<Vec<u8>, u32> {
    let size = match op {
        1 | 3 | 5 | 7 | 9 | 11 | 17 => 48,
        2 | 4 | 6 | 8 | 10 | 12 | 18 => 96,
        _ => 1,
    };
    let buffers: Vec<_> = [a, b, c]
        .iter()
        .map(|bytes| {
            let mut padded = vec![0xa5];
            padded.extend_from_slice(bytes);
            padded.push(0x5a);
            padded
        })
        .collect();
    let saved = buffers.clone();
    let mut output = vec![0x5a; size + 2];
    let code = unsafe {
        bls_call(
            op,
            buffers[0].as_ptr().add(1),
            a.len(),
            buffers[1].as_ptr().add(1),
            b.len(),
            buffers[2].as_ptr().add(1),
            c.len(),
            output.as_mut_ptr().add(1),
        )
    };
    assert_eq!(buffers, saved);
    assert_eq!(output[0], 0x5a);
    assert_eq!(output[size + 1], 0x5a);
    if code != 0 {
        assert!(output.iter().all(|b| *b == 0x5a));
        return Err(code);
    }
    Ok(output[1..size + 1].to_vec())
}

fn small_scalar(n: u8) -> [u8; 32] {
    let mut scalar = [0; 32];
    scalar[31] = n;
    scalar
}

#[test]
fn rfc9380_hash_vectors_and_field_maps() {
    for v in rfc9380::G1_VECTORS {
        assert_eq!(
            call(11, v.message.as_bytes(), rfc9380::G1_DST, &[]),
            Ok(hex(v.point))
        );
        let p0 = call(9, &hex(v.u0), &[], &[]).unwrap();
        let p1 = call(9, &hex(v.u1), &[], &[]).unwrap();
        assert_eq!(call(3, &p0, &p1, &[]), Ok(hex(v.point)));
        // Published pre-cofactor Q0 is on the curve but outside the subgroup.
        let q0: [u8; 48] = hex(v.q0).try_into().unwrap();
        assert!(bool::from(
            G1Affine::from_compressed_unchecked(&q0).is_some()
        ));
        assert_eq!(call(1, &q0, &[], &[]), Err(INVALID_POINT));
    }
    for v in rfc9380::G2_VECTORS {
        assert_eq!(
            call(12, v.message.as_bytes(), rfc9380::G2_DST, &[]),
            Ok(hex(v.point))
        );
        let p0 = call(10, &hex(v.u0), &[], &[]).unwrap();
        let p1 = call(10, &hex(v.u1), &[], &[]).unwrap();
        assert_eq!(call(4, &p0, &p1, &[]), Ok(hex(v.point)));
        let q0: [u8; 96] = hex(v.q0).try_into().unwrap();
        assert!(bool::from(
            G2Affine::from_compressed_unchecked(&q0).is_some()
        ));
        assert_eq!(call(2, &q0, &[], &[]), Err(INVALID_POINT));
    }
}

#[test]
fn ethereum_official_decode_vectors() {
    for (op, vectors) in [(1, ethereum::DECODE_G1), (2, ethereum::DECODE_G2)] {
        for (bytes, valid) in vectors {
            assert_eq!(
                call(op, &hex(bytes), &[], &[]).is_ok(),
                *valid,
                "op={op} {bytes}"
            );
        }
    }
}

#[test]
fn ethereum_official_signature_vectors() {
    for (pk, message, signature, expected) in ethereum::VERIFY {
        let actual = call(15, &hex(pk), &hex(message), &hex(signature));
        assert_eq!(
            actual == Ok(vec![1]),
            *expected,
            "pk={pk} msg={message} actual={actual:?}"
        );
    }
}

#[test]
fn ethereum_official_aggregate_vectors() {
    for (signatures, expected) in ethereum::AGGREGATE {
        let packed: Vec<_> = signatures
            .iter()
            .flat_map(|signature| hex(signature))
            .collect();
        assert_eq!(call(18, &packed, &[], &[]), Ok(hex(expected)));
    }
}

#[test]
fn ic_certificate_and_mutated_message() {
    // Independent agent-rs/IC certificate vector from ic-verify-bls-signature 0.6.0.
    let signature = hex(
        "ace9fcdd9bc977e05d6328f889dc4e7c99114c737a494653cb27a1f55c06f4555e0f160980af5ead098acc195010b2f7",
    );
    let message = hex(
        "0d69632d73746174652d726f6f74e6c01e909b4923345ce5970962bcfe3004bfd8474a21dae28f50692502f46d90",
    );
    let key = hex(
        "814c0e6ec71fab583b08bd81373c255c3c371b2e84863c98a4f1e08b74235d14fb5d9c0cd546d9685f913a0c0b2cc5341583bf4b4392e467db96d65b9bb4cb717112f8472e0d5a4d14505ffd7484b01291091c5f87b98883463f98091a0baaae",
    );
    assert_eq!(call(14, &key, &message, &signature), Ok(vec![1]));
    let mut wrong_message = message;
    wrong_message[0] ^= 1;
    assert_eq!(call(14, &key, &wrong_message, &signature), Ok(vec![0]));
}

#[test]
fn profiles_and_proof_of_possession_have_distinct_domains() {
    let sk = Scalar::from(42u64);
    let pk = G1Affine::from(G1Projective::generator() * sk).to_compressed();
    let sig = G2Affine::from(hash_g2(&pk, ETH_DST) * sk).to_compressed();
    let proof = G2Affine::from(hash_g2(&pk, ETH_POP_DST) * sk).to_compressed();
    // Independent py_ecc 8.0.0 fixture, with derivation in vectors/README.md.
    assert_eq!(
        pk.as_slice(),
        hex(
            "8ce3b57b791798433fd323753489cac9bca43b98deaafaed91f4cb010730ae1e38b186ccd37a09b8aed62ce23b699c48"
        )
    );
    assert_eq!(
        proof.as_slice(),
        hex(
            "969a1f7e520bcd7e3da791bb788383062d30c8b0f2b3ebd6700e041e1ba1e983bbd5e310380f6c5ba25da81c916487f9192bc33c0c95781dd4b2316bbd9a9ea34a20ffac329cf617f668f847f407194fdbb4777ea2b9357bd97e2069116b04a1"
        )
    );
    assert_eq!(call(16, &pk, &proof, &[]), Ok(vec![1]));
    assert_eq!(call(16, &pk, &sig, &[]), Ok(vec![0]));
    assert_eq!(call(15, &pk, &pk, &proof), Ok(vec![0]));
    assert_eq!(call(15, &pk, &pk, &sig), Ok(vec![1]));
    let wrong_pk = G1Affine::generator().to_compressed();
    assert_eq!(call(16, &wrong_pk, &proof, &[]), Ok(vec![0]));
}

#[test]
fn group_operations_scalar_endianness_and_msm() {
    for (g, validate, add, mul, msm, aggregate) in [
        (
            G1Affine::generator().to_compressed().to_vec(),
            1,
            3,
            5,
            7,
            17,
        ),
        (
            G2Affine::generator().to_compressed().to_vec(),
            2,
            4,
            6,
            8,
            18,
        ),
    ] {
        let identity = call(aggregate, &[], &[], &[]).unwrap();
        assert_eq!(call(validate, &identity, &[], &[]), Ok(identity.clone()));
        assert_eq!(call(mul, &g, &small_scalar(0), &[]), Ok(identity.clone()));
        assert_eq!(call(mul, &g, &small_scalar(1), &[]), Ok(g.clone()));
        assert_eq!(call(add, &g, &identity, &[]), Ok(g.clone()));
        let doubled = call(add, &g, &g, &[]).unwrap();
        assert_eq!(call(mul, &g, &small_scalar(2), &[]), Ok(doubled.clone()));
        assert_eq!(
            call(aggregate, &[g.clone(), g.clone()].concat(), &[], &[]),
            Ok(doubled.clone())
        );
        let points = [g.clone(), doubled].concat();
        let scalars = [small_scalar(3), small_scalar(5)].concat();
        assert_eq!(
            call(msm, &points, &scalars, &[]),
            call(mul, &g, &small_scalar(13), &[])
        );
        assert_eq!(call(msm, &[], &[], &[]), Ok(identity));
    }
}

#[test]
fn pairing_product_cancellation_and_identity() {
    let p = G1Affine::generator();
    let q = G2Affine::generator();
    let pair = [p.to_compressed().as_slice(), q.to_compressed().as_slice()].concat();
    let inverse = [
        (-p).to_compressed().as_slice(),
        q.to_compressed().as_slice(),
    ]
    .concat();
    assert_eq!(call(13, &pair, &[], &[]), Ok(vec![0]));
    assert_eq!(call(13, &[pair, inverse].concat(), &[], &[]), Ok(vec![1]));
    assert_eq!(call(13, &[], &[], &[]), Ok(vec![1]));
    let pair = [
        G1Affine::identity().to_compressed().as_slice(),
        q.to_compressed().as_slice(),
    ]
    .concat();
    assert_eq!(call(13, &pair, &[], &[]), Ok(vec![1]));
}

#[test]
fn reject_identity_in_signature_profiles() {
    let p = G1Affine::generator().to_compressed();
    let q = G2Affine::generator().to_compressed();
    let i1 = G1Affine::identity().to_compressed();
    let i2 = G2Affine::identity().to_compressed();
    assert_eq!(call(14, &i2, b"hello", &p), Err(IDENTITY));
    assert_eq!(call(14, &q, b"hello", &i1), Err(IDENTITY));
    assert_eq!(call(15, &i1, b"hello", &q), Err(IDENTITY));
    assert_eq!(call(15, &p, b"hello", &i2), Err(IDENTITY));
    assert_eq!(call(16, &i1, &q, &[]), Err(IDENTITY));
}

#[test]
fn bounds_and_canonical_scalars_and_fields() {
    let p = G1Affine::generator().to_compressed();
    let order = hex("73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");
    assert_eq!(call(5, &p, &order, &[]), Err(INVALID_SCALAR));
    assert_eq!(call(5, &p, &[0xff; 32], &[]), Err(INVALID_SCALAR));
    assert_eq!(call(5, &p, &[1; 31], &[]), Err(INVALID_LENGTH));
    assert_eq!(call(9, &FP_MODULUS, &[], &[]), Err(INVALID_FIELD));
    assert_eq!(
        call(10, &[vec![0; 48], FP_MODULUS.to_vec()].concat(), &[], &[]),
        Err(INVALID_FIELD)
    );
    assert_eq!(
        call(10, &[vec![0; 47], FP_MODULUS.to_vec()].concat(), &[], &[]),
        Err(INVALID_LENGTH)
    );
    assert!(call(9, &[0; 48], &[], &[]).is_ok());
    assert!(call(10, &[0; 96], &[], &[]).is_ok());
    assert_eq!(call(7, &p, &[], &[]), Err(INVALID_LENGTH));
    assert_eq!(call(7, &[], &[0; 32 * 129], &[]), Err(TOO_MANY_ITEMS));
    for (op, width) in [(7, 48), (8, 96), (13, 144), (17, 48), (18, 96)] {
        assert_eq!(
            call(op, &vec![0; width * 129], &[], &[]),
            Err(TOO_MANY_ITEMS)
        );
        assert_eq!(call(op, &[0], &[], &[]), Err(INVALID_LENGTH));
    }
    assert_eq!(call(999, &[], &[], &[]), Err(INVALID_ARGUMENT));
    assert_eq!(call(11, b"message", &[], &[]), Err(INVALID_ARGUMENT));
    assert_eq!(call(12, b"message", &[], &[]), Err(INVALID_ARGUMENT));
    // Errors follow operand order, including partially processed MSM batches.
    let points = [p.as_slice(), &[0; 48]].concat();
    let scalars = [order.as_slice(), &[0; 32]].concat();
    assert_eq!(call(7, &points, &scalars, &[]), Err(INVALID_SCALAR));
    assert_eq!(
        call(
            14,
            &G2Affine::identity().to_compressed(),
            b"hello",
            &[0; 48]
        ),
        Err(INVALID_POINT)
    );
    assert_eq!(
        call(
            15,
            &G1Affine::identity().to_compressed(),
            b"hello",
            &[0; 96]
        ),
        Err(INVALID_POINT)
    );
}

#[test]
fn maximum_batches_and_empty_null_inputs() {
    let i1 = G1Affine::identity().to_compressed();
    let i2 = G2Affine::identity().to_compressed();
    assert_eq!(call(17, &i1.repeat(128), &[], &[]), Ok(i1.to_vec()));
    assert_eq!(call(18, &i2.repeat(128), &[], &[]), Ok(i2.to_vec()));
    assert_eq!(
        call(7, &i1.repeat(128), &[0; 32 * 128], &[]),
        Ok(i1.to_vec())
    );
    assert_eq!(
        call(8, &i2.repeat(128), &[0; 32 * 128], &[]),
        Ok(i2.to_vec())
    );
    let pair = [i1.as_slice(), i2.as_slice()].concat();
    assert_eq!(call(13, &pair.repeat(128), &[], &[]), Ok(vec![1]));
    let mut output = [0xff; 48];
    assert_eq!(
        unsafe {
            bls_call(
                17,
                core::ptr::null(),
                0,
                core::ptr::null(),
                0,
                core::ptr::null(),
                0,
                output.as_mut_ptr(),
            )
        },
        0
    );
    assert_eq!(output, i1);
}

#[test]
fn maps_match_independent_ocaml_zero_and_unit_fields() {
    // The exceptional raw image must be a valid curve point before clearing;
    // its lack of subgroup membership is why only this constant uses the
    // unchecked-subgroup decoder. Caller encodings never use it.
    let raw_zero = G2Affine::from(map_g2_field(&Default::default()));
    assert!(bool::from(raw_zero.is_on_curve()));
    assert!(!bool::from(raw_zero.is_torsion_free()));
    assert!(!bool::from(raw_zero.is_identity()));
    let zero = [0; 48];
    let mut one = zero;
    one[47] = 1;
    assert_eq!(
        call(9, &zero, &[], &[]),
        Ok(hex(
            "91a9a0372b8f332d5c30de9ad14e50372a73fa4c45d5f2fa5097f2d6fb93bcac592f2e1711ac43db0519870c7d0ea415"
        ))
    );
    assert_eq!(
        call(9, &one, &[], &[]),
        Ok(hex(
            "9073311196f8ef19477219ccee3a48035ff432295aa9419eed45d186027d88b90832e14c4f0e2aa4d15f54d1c3ed0f93"
        ))
    );
    for (real, imag, expected) in [
        (
            zero,
            zero,
            "8a67d12118b5a35bb02d2e86b3ebfa7e23410db93de39fb06d7025fa95e96ffa428a7a27c3ae4dd4b40bd251ac658892018320896ec9eef9d5e619848dc29ce266f413d02dd31d9b9d44ec0c79cd61f18b075ddba6d7bd20b7ff27a4b324bfce",
        ),
        (
            one,
            zero,
            "a0e12b55d801607d9760f8637ac80a4fececd3eb74045b342ee3c7dddd2037e72dedccc27e9a89491d4e57bde555fead1770d4f641225e1a1c0f7d05857299763e98e47ec6355b81dd6cdaf6db6825052f71d35ede3af8b70f046474c48d712e",
        ),
        (
            zero,
            one,
            "a5d991fb690fdad1923ac1834188ed45d160a15ee5547a4476b836a158a9884236846408b8abd5d99217876d12f8f5d60f5ab9ab512bac0e5aa9d4be326afefbfa5db2dba6c88000f1cfeaa0cd62b2b2604935e2794933d76f9887bae7ed2851",
        ),
    ] {
        assert_eq!(
            call(10, &[real, imag].concat(), &[], &[]),
            Ok(hex(expected))
        );
    }
}

#[test]
fn oversized_dst_matches_rfc9380_normalization() {
    use sha2::Digest;
    let dst = vec![b'X'; 300];
    let mut h = Sha256::new();
    h.update(b"H2C-OVERSIZE-DST-");
    h.update(&dst);
    let normalized = h.finalize();
    for op in [11, 12] {
        assert_eq!(
            call(op, b"abc", &dst, &[]),
            call(op, b"abc", &normalized, &[])
        );
    }
}

#[test]
fn pippenger_full_width_distinct_inputs() {
    use sha2::Digest;
    for count in [4usize, 5, 16, 17, 64, 65, 128] {
        let mut points1 = Vec::new();
        let mut points2 = Vec::new();
        let mut scalars = Vec::new();
        let mut expected1 = G1Projective::identity();
        let mut expected2 = G2Projective::identity();
        for i in 0..count {
            let p = G1Affine::from(G1Projective::generator() * Scalar::from((i + 1) as u64));
            let q = G2Affine::from(G2Projective::generator() * Scalar::from((i + 1) as u64));
            let mut s = Sha256::digest(&(i as u64).to_be_bytes()).to_vec();
            s[0] &= 0x3f;
            let s_value = scalar(&s).unwrap();
            points1.extend_from_slice(&p.to_compressed());
            points2.extend_from_slice(&q.to_compressed());
            scalars.extend_from_slice(&s);
            expected1 += p * s_value;
            expected2 += q * s_value;
        }
        assert_eq!(msm_g1(&points1, &scalars).unwrap(), expected1);
        assert_eq!(msm_g2(&points2, &scalars).unwrap(), expected2);
    }
}

#[test]
fn pippenger_scalar_window_edges_and_errors() {
    let mut order_minus_one =
        hex("73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001");
    order_minus_one[31] -= 1;
    let mut high_bit = [0; 32];
    high_bit[0] = 0x40;
    let scalar_cases = [
        small_scalar(0).to_vec(),
        small_scalar(1).to_vec(),
        order_minus_one,
        high_bit.to_vec(),
    ];
    for count in [4usize, 16, 64, 128] {
        let p = G1Affine::generator();
        let q = G2Affine::generator();
        let scalars: Vec<u8> = (0..count)
            .flat_map(|i| scalar_cases[i % 4].iter().copied())
            .collect();
        let mut total = Scalar::zero();
        for s in scalars.chunks_exact(32) {
            total += scalar(s).unwrap();
        }
        assert_eq!(
            msm_g1(&p.to_compressed().repeat(count), &scalars).unwrap(),
            p * total
        );
        assert_eq!(
            msm_g2(&q.to_compressed().repeat(count), &scalars).unwrap(),
            q * total
        );
    }
    let mut points = G1Affine::generator().to_compressed().repeat(4);
    points[48..96].fill(0);
    let mut scalars = small_scalar(1).repeat(4);
    scalars[..32].fill(0xff);
    assert_eq!(msm_g1(&points, &scalars), Err(INVALID_SCALAR));
}

#[test]
fn signed_msm_randomized_small_and_boundaries() {
    use sha2::Digest;
    for round in 0..4u64 {
        for count in [2usize, 3, 4, 5, 16, 17, 64, 65, 128] {
            let mut points1 = Vec::new();
            let mut points2 = Vec::new();
            let mut scalars = Vec::new();
            let mut expected1 = G1Projective::identity();
            let mut expected2 = G2Projective::identity();
            for i in 0..count {
                let j = (i as u64 + 1) * (round + 1);
                let p = G1Affine::from(G1Projective::generator() * Scalar::from(j));
                let q = G2Affine::from(G2Projective::generator() * Scalar::from(j));
                let mut s = Sha256::digest(&[round.to_be_bytes(), (i as u64).to_be_bytes()].concat()).to_vec();
                s[0] &= 0x3f;
                let s_value = scalar(&s).unwrap();
                points1.extend_from_slice(&p.to_compressed());
                points2.extend_from_slice(&q.to_compressed());
                scalars.extend_from_slice(&s);
                expected1 += p * s_value;
                expected2 += q * s_value;
            }
            assert_eq!(msm_g1(&points1, &scalars).unwrap(), expected1, "G1 round={round} count={count}");
            assert_eq!(msm_g2(&points2, &scalars).unwrap(), expected2, "G2 round={round} count={count}");
        }
    }
}

#[test]
fn signed_digits_reconstruct_every_bit_and_carry_boundaries() {
    let mut cases = Vec::new();
    for bit in 0..255 {
        let mut s = [0u8; 33];
        s[bit / 8] = 1 << (bit % 8);
        cases.push(s);
        if bit > 0 {
            let mut s = s;
            for lower in &mut s[..bit / 8] { *lower = 255; }
            s[bit / 8] -= 1;
            cases.push(s);
        }
    }
    let mut order_minus_one = hex("73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000");
    order_minus_one.reverse();
    let mut last = [0; 33];
    last[..32].copy_from_slice(&order_minus_one);
    cases.push(last);
    for s in cases {
        let actual = Scalar::from_bytes(s[..32].try_into().unwrap()).unwrap();
        let digits = public_wnaf(&s);
        let mut reconstructed = Scalar::zero();
        for digit in digits.iter().rev() {
            reconstructed = reconstructed + reconstructed;
            if *digit > 0 { reconstructed += Scalar::from(*digit as u64); }
            if *digit < 0 { reconstructed -= Scalar::from((-*digit) as u64); }
        }
        assert_eq!(actual, reconstructed);
        for window in 3..=6 {
            let half = 1usize << (window - 1);
            let mut reconstructed = Scalar::zero();
            for k in (0..256usize.div_ceil(window)).rev() {
                for _ in 0..window { reconstructed += reconstructed; }
                let bit = k * window;
                let word = s[bit / 8] as usize | ((s[bit / 8 + 1] as usize) << 8);
                let raw = (word >> (bit % 8)) & ((half << 1) - 1);
                let previous = if bit == 0 { 0 } else { ((s[(bit - 1) / 8] >> ((bit - 1) % 8)) & 1) as usize };
                let digit = (raw & (half - 1)) as isize + previous as isize - (raw & half) as isize;
                if digit > 0 { reconstructed += Scalar::from(digit as u64); }
                if digit < 0 { reconstructed -= Scalar::from((-digit) as u64); }
            }
            assert_eq!(actual, reconstructed, "window={window}");
        }
    }
}

#[test]
fn neutral_pairing_terms_still_validate_both_operands() {
    let p = G1Affine::generator().to_compressed();
    let q = G2Affine::generator().to_compressed();
    let i1 = G1Affine::identity().to_compressed();
    let i2 = G2Affine::identity().to_compressed();
    for bad_at in 0..3 {
        let mut pairs = [i1.as_slice(), i2.as_slice()].concat().repeat(3);
        pairs[bad_at * 144 + 48..bad_at * 144 + 144].fill(0);
        assert_eq!(call(13, &pairs, &[], &[]), Err(INVALID_POINT));
        let mut pairs = [i1.as_slice(), i2.as_slice()].concat().repeat(3);
        pairs[bad_at * 144..bad_at * 144 + 48].fill(0);
        assert_eq!(call(13, &pairs, &[], &[]), Err(INVALID_POINT));
    }
    let pairs = [
        [i1.as_slice(), q.as_slice()].concat(),
        [p.as_slice(), q.as_slice()].concat(),
        [p.as_slice(), i2.as_slice()].concat(),
    ].concat();
    assert_eq!(call(13, &pairs, &[], &[]), Ok(vec![0]));
    for width in [48usize, 96] {
        let op = if width == 48 { 1 } else { 2 };
        for bit in 0..width * 8 {
            let mut input = vec![0u8; width];
            input[0] = 0xc0;
            input[bit / 8] ^= 1 << (bit % 8);
            assert_eq!(call(op, &input, &[], &[]), Err(INVALID_POINT), "width={width} bit={bit}");
        }
    }
}

fn baseline_pairing_check(bytes: &[u8]) -> Result<bool, u32> {
    let count = batch_len(bytes, 144)?;
    let mut points = Vec::with_capacity(count);
    for pair in bytes.chunks_exact(144) {
        points.push((g1(&pair[..48])?, g2(&pair[48..])?));
    }
    let prepared: Vec<_> = points.iter().map(|(_, q)| G2Prepared::from(*q)).collect();
    let terms: Vec<_> = points.iter().zip(&prepared).map(|((p, _), q)| (p, q)).collect();
    Ok(multi_miller_loop(&terms).final_exponentiation() == Gt::identity())
}

#[test]
fn grouped_pairings_match_full_pairing_product() {
    for count in [0usize, 1, 2, 3, 8, 32, 128] {
        for unique in [1usize, 2, 3, 128] {
            let mut pairs = Vec::new();
            for i in 0..count {
                let p = G1Affine::from(G1Projective::generator() * Scalar::from((i + 1) as u64));
                let q = G2Affine::from(G2Projective::generator() * Scalar::from((i % unique + 1) as u64));
                pairs.extend_from_slice(&p.to_compressed());
                pairs.extend_from_slice(&q.to_compressed());
            }
            assert_eq!(pairing_check(&pairs), baseline_pairing_check(&pairs), "count={count} unique={unique}");
            let mut inverse = pairs.clone();
            for pair in inverse.chunks_exact_mut(144) {
                let negated = (-g1(&pair[..48]).unwrap()).to_compressed();
                pair[..48].copy_from_slice(&negated);
            }
            if count <= 64 {
                pairs.extend_from_slice(&inverse);
                assert_eq!(pairing_check(&pairs), Ok(true));
            }
        }
    }
    // Cancellation must not hide a malformed, later input.
    let p = G1Affine::generator();
    let q = G2Affine::generator().to_compressed();
    let pairs = [
        [p.to_compressed().as_slice(), q.as_slice()].concat(),
        [(-p).to_compressed().as_slice(), q.as_slice()].concat(),
        [p.to_compressed().as_slice(), &[0; 96]].concat(),
    ].concat();
    assert_eq!(pairing_check(&pairs), Err(INVALID_POINT));
}

#[test]
fn empty_public_batches_preserve_errors_and_canonical_identity() {
    for (msm,aggregate,expected) in [(7,17,G1Affine::identity().to_compressed().to_vec()),
        (8,18,G2Affine::identity().to_compressed().to_vec())] {
        assert_eq!(call(msm,&[],&[],&[]),Ok(expected.clone()));
        assert_eq!(call(aggregate,&[],&[],&[]),Ok(expected));
        assert_eq!(call(msm,&[],&[0],&[]),Err(INVALID_LENGTH));
        assert_eq!(call(msm,&[],&[0;32],&[]),Err(INVALID_LENGTH));
        assert_eq!(call(msm,&[],&[0;32*129],&[]),Err(TOO_MANY_ITEMS));
        assert_eq!(call(msm,&[],&[0;32*129+1],&[]),Err(INVALID_LENGTH));
    }
}

#[path = "aggregate_tests.rs"]
mod aggregate;
