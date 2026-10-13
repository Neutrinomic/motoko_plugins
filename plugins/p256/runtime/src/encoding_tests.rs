//! Exact encoding and error-status regressions with OpenSSL-produced answers.
use super::*;

fn hex(value: &str) -> Vec<u8> {
    (0..value.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&value[i..i + 2], 16).unwrap())
        .collect()
}

fn vectors() -> serde_json::Value {
    serde_json::from_str(include_str!("../../tests/vectors/encoding.json")).unwrap()
}

#[test]
fn openssl_der_lengths_padding_and_normalization() {
    let vectors = vectors();
    let mut lengths = [false; 73];
    for row in vectors["der"].as_array().unwrap() {
        let name = row["name"].as_str().unwrap();
        let compact = hex(row["compact"].as_str().unwrap());
        let expected = hex(row["der"].as_str().unwrap());
        let normalized = hex(row["normalized"].as_str().unwrap());
        let mut out = [0; 72];
        assert_eq!(
            signature_to_der(&compact, &mut out),
            Ok(expected.len()),
            "{name}"
        );
        assert_eq!(&out[..expected.len()], expected, "{name}");
        assert_eq!(signature_from_der(&expected, &mut out), Ok(64), "{name}");
        assert_eq!(&out[..64], compact, "{name}");
        assert_eq!(normalize_signature(&compact, &mut out), Ok(64), "{name}");
        assert_eq!(&out[..64], normalized, "{name}");
        assert_eq!(normalize_signature(&normalized, &mut out), Ok(64), "{name}");
        assert_eq!(&out[..64], normalized, "{name}");
        lengths[expected.len()] = true;
    }
    assert!(lengths[8..=72].iter().all(|seen| *seen));
}

#[test]
fn der_mutations_return_typed_errors_before_verification() {
    // Assert the decoder result itself. A combined decode-and-verify boolean
    // would hide malformed DER accepted as an ordinary incorrect signature.
    let vectors = vectors();
    for row in vectors["der"].as_array().unwrap() {
        let name = row["name"].as_str().unwrap();
        let der = hex(row["der"].as_str().unwrap());
        let mut bad = Vec::new();
        for length in 0..der.len() {
            bad.push(der[..length].to_vec());
        }
        let mut appended = der.clone();
        appended.push(0);
        bad.push(appended);
        let mut long_sequence = der.clone();
        long_sequence.insert(1, 0x81);
        bad.push(long_sequence);
        for start in [2, 4 + der[3] as usize] {
            let mut padded = der.clone();
            padded.insert(start + 2, 0);
            padded[start + 1] += 1;
            padded[1] += 1;
            bad.push(padded);
            let mut long_integer = der.clone();
            long_integer.insert(start + 1, 0x81);
            long_integer[1] += 1;
            bad.push(long_integer);
            if der[start + 2] == 0 {
                let mut negative = der.clone();
                negative.remove(start + 2);
                negative[start + 1] -= 1;
                negative[1] -= 1;
                bad.push(negative);
            }
        }
        for input in bad {
            assert_eq!(
                signature_from_der(&input, &mut [0; 64]),
                Err(INVALID_SIGNATURE),
                "{name}: {input:02x?}"
            );
        }
    }
}

fn invalid_key(key: &[u8]) {
    for compressed in [false, true] {
        assert_eq!(
            convert_public_key(key, compressed, &mut [0; 65]),
            Err(INVALID_PUBLIC_KEY)
        );
    }
    assert_eq!(
        prepare_public_key(key, &mut [0; prepared_table::BYTES]),
        Err(INVALID_PUBLIC_KEY)
    );
    assert_eq!(verify_prehash(key, &[], &[]), Err(INVALID_PUBLIC_KEY));
}

#[test]
fn openssl_sec1_canonical_coordinates_tags_and_lengths() {
    let vectors = vectors();
    for row in vectors["sec1"].as_array().unwrap() {
        let key = hex(row["compressed"].as_str().unwrap());
        let Some(uncompressed) = row["uncompressed"].as_str() else {
            invalid_key(&key);
            continue;
        };
        let uncompressed = hex(uncompressed);
        for encoded in [&key, &uncompressed] {
            let mut out = [0; 65];
            assert_eq!(convert_public_key(encoded, true, &mut out), Ok(33));
            assert_eq!(&out[..33], key);
            assert_eq!(convert_public_key(encoded, false, &mut out), Ok(65));
            assert_eq!(&out[..65], uncompressed);
            assert_eq!(
                prepare_public_key(encoded, &mut [0; prepared_table::BYTES]),
                Ok(prepared_table::BYTES)
            );
        }
    }

    let row = &vectors["sec1"][0];
    for (key, allowed) in [
        (hex(row["compressed"].as_str().unwrap()), &[2u8, 3][..]),
        (hex(row["uncompressed"].as_str().unwrap()), &[4u8][..]),
    ] {
        for tag in 0..=255u8 {
            if !allowed.contains(&tag) {
                let mut changed = key.clone();
                changed[0] = tag;
                invalid_key(&changed);
            }
        }
        for length in 0..key.len() {
            invalid_key(&key[..length]);
        }
        let mut appended = key;
        appended.push(0);
        invalid_key(&appended);
    }
}
