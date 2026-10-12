use original::elliptic_curve::sec1::ToEncodedPoint;
use original::sha2::{Digest, Sha256};

const VECTORS: &str = include_str!("../bip340.csv");
const LENGTHS: &[usize] = &[0, 1, 17, 31, 32, 33, 63, 64, 65, 127, 128, 255, 1024, 4096];
fn hex(s: &str) -> Vec<u8> {
    assert_eq!(s.len() % 2, 0);
    s.as_bytes().chunks_exact(2).map(|p| u8::from_str_radix(core::str::from_utf8(p).unwrap(), 16).unwrap()).collect()
}
fn hex_string(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
fn generated(label: &[u8], index: usize) -> [u8; 32] {
    Sha256::new().chain_update(label).chain_update((index as u64).to_be_bytes()).finalize().into()
}
fn message(pair: usize, len: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(len);
    for block in 0..len.div_ceil(32) {
        out.extend_from_slice(&Sha256::new()
            .chain_update(b"secp256k1-vendor-comparator/message")
            .chain_update((pair as u64).to_be_bytes())
            .chain_update((len as u64).to_be_bytes())
            .chain_update((block as u64).to_be_bytes()).finalize());
    }
    out.truncate(len);
    out
}
fn compare_key(secret: &[u8; 32], transcript: &mut Sha256) -> (original::schnorr::SigningKey, patched::schnorr::SigningKey, bool) {
    let raw_o = original::SecretKey::from_slice(secret).expect("original raw key");
    let raw_p = patched::SecretKey::from_slice(secret).expect("patched raw key");
    let sec1_o = raw_o.public_key().to_encoded_point(true);
    let sec1_p = raw_p.public_key().to_encoded_point(true);
    assert_eq!(sec1_o.as_bytes(), sec1_p.as_bytes(), "unnormalized compressed public key");
    let sec1_o_u = raw_o.public_key().to_encoded_point(false);
    let sec1_p_u = raw_p.public_key().to_encoded_point(false);
    assert_eq!(sec1_o_u.as_bytes(), sec1_p_u.as_bytes(), "unnormalized uncompressed public key");
    let odd = sec1_o.as_bytes()[0] == 3;
    let o = original::schnorr::SigningKey::from_bytes(secret).expect("original Schnorr key");
    let p = patched::schnorr::SigningKey::from_bytes(secret).expect("patched Schnorr key");
    assert_eq!(o.to_bytes().as_slice(), p.to_bytes().as_slice(), "normalized secret");
    assert_eq!(o.as_nonzero_scalar().to_bytes().as_slice(), p.as_nonzero_scalar().to_bytes().as_slice(), "borrowed normalized scalar");
    assert_eq!(o.verifying_key().to_bytes().as_slice(), p.verifying_key().to_bytes().as_slice(), "x-only public key");
    let expected = if odd { (-*raw_o.to_nonzero_scalar().as_ref()).to_bytes() } else { raw_o.to_bytes() };
    assert_eq!(o.to_bytes(), expected, "normalization follows original public parity");
    let normalized_public = original::SecretKey::from_slice(o.to_bytes().as_slice()).unwrap().public_key().to_encoded_point(true);
    assert_eq!(normalized_public.as_bytes()[0], 2, "normalized key has even Y");
    assert_eq!(&normalized_public.as_bytes()[1..], o.verifying_key().to_bytes().as_slice());
    transcript.update(sec1_o.as_bytes());
    transcript.update(o.to_bytes());
    transcript.update(o.verifying_key().to_bytes());
    (o, p, odd)
}
fn compare_signature(
    o: &original::schnorr::SigningKey,
    p: &patched::schnorr::SigningKey,
    msg: &[u8],
    aux: &[u8; 32],
    transcript: &mut Sha256,
) -> [u8; 64] {
    let so = o.sign_raw(msg, aux).expect("original sign");
    let sp = p.sign_raw(msg, aux).expect("patched sign");
    assert_eq!(so.to_bytes(), sp.to_bytes(), "exact raw Schnorr signature");
    // Cross-library verification reparses the opposite implementation's bytes.
    let opposite_for_original = original::schnorr::Signature::try_from(sp.to_bytes().as_slice()).unwrap();
    let opposite_for_patched = patched::schnorr::Signature::try_from(so.to_bytes().as_slice()).unwrap();
    o.verifying_key().verify_raw(msg, &opposite_for_original).expect("original verifies patched signature");
    p.verifying_key().verify_raw(msg, &opposite_for_patched).expect("patched verifies original signature");
    transcript.update((msg.len() as u64).to_be_bytes());
    transcript.update(msg);
    transcript.update(aux);
    transcript.update(so.to_bytes());
    so.to_bytes()
}
fn main() {
    let mut transcript = Sha256::new();
    let mut official = 0usize;
    let mut official_even = 0usize;
    let mut official_odd = 0usize;
    for line in VECTORS.lines().skip(1) {
        let f: Vec<_> = line.split(',').collect();
        if f[1].is_empty() { continue; }
        let secret: [u8; 32] = hex(f[1]).try_into().unwrap();
        let aux: [u8; 32] = hex(f[3]).try_into().unwrap();
        let msg = hex(f[4]);
        let (o, p, odd) = compare_key(&secret, &mut transcript);
        assert_eq!(o.verifying_key().to_bytes().as_slice(), hex(f[2]), "official public key vector {}", f[0]);
        let sig = compare_signature(&o, &p, &msg, &aux, &mut transcript);
        assert_eq!(sig.as_slice(), hex(f[5]), "official signature vector {}", f[0]);
        assert_eq!(f[6], "TRUE");
        official += 1;
        if odd { official_odd += 1; } else { official_even += 1; }
    }
    assert_eq!(official, 8, "all official vectors with secrets included");
    let mut base_even = 0usize;
    let mut base_odd = 0usize;
    let pairs = 32usize;
    let mut pair_cases = 0usize;
    for pair in 0..pairs {
        let secret = if pair < 4 {
            let mut small = [0u8; 32];
            small[31] = (pair + 1) as u8;
            small
        } else {
            generated(b"secp256k1-vendor-comparator/secret", pair)
        };
        let raw = original::SecretKey::from_slice(&secret).expect("fixed deterministic secret within field");
        let opposite: [u8; 32] = (-*raw.to_nonzero_scalar().as_ref()).to_bytes().into();
        assert_ne!(secret, opposite);
        let (o1, p1, odd1) = compare_key(&secret, &mut transcript);
        let (o2, p2, odd2) = compare_key(&opposite, &mut transcript);
        assert_ne!(odd1, odd2, "d and n-d have opposite raw public parity");
        assert_eq!(o1.to_bytes(), o2.to_bytes(), "paired original normalized secret");
        assert_eq!(p1.to_bytes(), p2.to_bytes(), "paired patched normalized secret");
        assert_eq!(o1.verifying_key().to_bytes(), o2.verifying_key().to_bytes(), "paired x-only public");
        if odd1 { base_odd += 1; } else { base_even += 1; }
        let auxiliary = [[0; 32], [0xff; 32], [0x55; 32], generated(b"secp256k1-vendor-comparator/aux", pair)];
        for &len in LENGTHS {
            let msg = message(pair, len);
            for aux in &auxiliary {
                let s1 = compare_signature(&o1, &p1, &msg, aux, &mut transcript);
                let s2 = compare_signature(&o2, &p2, &msg, aux, &mut transcript);
                assert_eq!(s1, s2, "d and n-d exact signatures");
                pair_cases += 1;
            }
        }
    }
    assert!(base_even > 0 && base_odd > 0, "base secrets cover both raw public parities");
    let compared_signatures = official + 2 * pair_cases;
    println!("{{\"status\":\"passed\",\"official_signing_vectors\":{official},\"official_raw_even\":{official_even},\"official_raw_odd\":{official_odd},\"deterministic_pairs\":{pairs},\"base_raw_even\":{base_even},\"base_raw_odd\":{base_odd},\"message_lengths\":{:?},\"auxiliary_variants\":4,\"paired_message_auxiliary_cases\":{pair_cases},\"exact_signature_comparisons\":{compared_signatures},\"cross_verifications\":{},\"key_comparisons\":{},\"transcript_sha256\":\"{}\"}}",
        LENGTHS, 2 * compared_signatures, official + 2 * pairs, hex_string(&transcript.finalize()));
}

