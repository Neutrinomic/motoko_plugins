//! BLS12-381 kernels using canonical IETF compressed point encodings.
//!
//! No borrowed input pointer survives the call. Direct pairing precomputation
//! uses bounded ephemeral managed scratch (at most 128 terms), as does MSM.
//! Explicit prepared keys use immutable caller-owned managed Blobs containing
//! only initialized limbs; an immutable generator table is shared by both paths. MSM is
//! variable time and intended for public scalars. Other kernels use fixed
//! stack storage. Every point decoder checks the prime-order
//! subgroup. Scalars and map-to-curve field elements are canonical big endian.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(alloc_error_handler))]

extern crate alloc;

use alloc::vec::Vec;
use bls12_381::{
    G1Affine, G1Projective, G2Affine, G2Prepared, G2Projective, Gt, Scalar,
    hash_to_curve::{ExpandMsgXmd, HashToCurve, HashToField, MapToCurve},
};
use bls12_381::plugin_prepared::{
    G1_AFFINE_BYTES, G2_PREPARED_BYTES, G2PreparedSource,
    multi_miller_loop as prepared_miller_loop,
    read_g1_affine_trusted, write_g1_affine, write_g2_prepared,
};
// bls12_381 0.8 exposes generic-array 0.14 in its hash-to-field interface.
#[allow(deprecated)]
use generic_array::GenericArray;
use sha2::Sha256;

#[cfg(not(test))]
mod host {
    use core::alloc::{GlobalAlloc, Layout};

    #[link(wasm_import_module = "env")]
    unsafe extern "C" {
        fn compute_plugin_alloc(size: usize, align: usize) -> *mut u8;
        fn compute_plugin_trap(ptr: *const u8, len: usize) -> !;
    }

    struct Ephemeral;
    unsafe impl GlobalAlloc for Ephemeral {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            unsafe { compute_plugin_alloc(layout.size(), layout.align()) }
        }
        unsafe fn dealloc(&self, _: *mut u8, _: Layout) {}
    }

    #[global_allocator]
    static ALLOCATOR: Ephemeral = Ephemeral;

    #[alloc_error_handler]
    fn allocation_failed(_: Layout) -> ! {
        fail()
    }

    #[panic_handler]
    fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
        fail()
    }

    fn fail() -> ! {
        let message = b"BLS12-381 plugin: allocation or invariant failure";
        unsafe { compute_plugin_trap(message.as_ptr(), message.len()) }
    }
}

const MAX_BATCH: usize = 128;
const INVALID_LENGTH: u32 = 1;
const INVALID_POINT: u32 = 2;
const INVALID_SCALAR: u32 = 3;
const INVALID_FIELD: u32 = 4;
const TOO_MANY_ITEMS: u32 = 5;
const EMPTY_BATCH: u32 = 6;
const IDENTITY: u32 = 7;
const INVALID_PROOF: u32 = 8;
const DUPLICATE_MESSAGE: u32 = 9;
const INVALID_ARGUMENT: u32 = 10;

const IC_DST: &[u8] = b"BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_";
const ETH_DST: &[u8] = b"BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_";
const ETH_POP_DST: &[u8] = b"BLS_POP_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_";

// These private, nonstable representations are created only by the plugin's
// protected factories. Every byte is initialized; neither format contains
// native pointers, allocator metadata, padding, or retained scratch storage.
const PREPARED_IC_BYTES: usize = 96 + G2_PREPARED_BYTES;
const PREPARED_ETH_BYTES: usize = 48 + G1_AFFINE_BYTES;

#[repr(align(8))]
struct AlignedGeneratorTable([u8; G2_PREPARED_BYTES]);
// Generated through the same explicit-limb writer and checked byte-for-byte
// against fresh upstream preparation in native tests. Direct and prepared
// APIs share this immutable constant; it is not a mutable cross-call cache.
static G2_GENERATOR_TABLE: AlignedGeneratorTable = AlignedGeneratorTable(
    *include_bytes!("../vectors/g2-generator-prepared.bin"));

fn dynamic_g2_preparation(point: G2Affine) -> Option<G2Prepared> {
    if point == G2Affine::generator() { None } else { Some(G2Prepared::from(point)) }
}

fn pairing_source(prepared: &Option<G2Prepared>) -> G2PreparedSource<'_> {
    match prepared {
        Some(prepared) => G2PreparedSource::Owned(prepared),
        None => G2PreparedSource::TrustedBytes(&G2_GENERATOR_TABLE.0),
    }
}

#[derive(Clone, Copy)]
struct PreparedIC<'a> {
    canonical: &'a [u8; 96],
    table: &'a [u8; G2_PREPARED_BYTES],
}

fn prepared_ic(bytes: &[u8]) -> Result<PreparedIC<'_>, u32> {
    if bytes.len() != PREPARED_IC_BYTES { return Err(INVALID_LENGTH); }
    Ok(PreparedIC {
        canonical: bytes[..96].try_into().map_err(|_| INVALID_LENGTH)?,
        table: bytes[96..].try_into().map_err(|_| INVALID_LENGTH)?,
    })
}

fn prepared_eth(bytes: &[u8]) -> Result<G1Affine, u32> {
    if bytes.len() != PREPARED_ETH_BYTES { return Err(INVALID_LENGTH); }
    // The SDK nominal type prevents importing arbitrary bytes into this path.
    // Factories have already checked canonical encoding, subgroup and identity;
    // the separate PoP nominal type additionally certifies its proof equation.
    Ok(read_g1_affine_trusted(bytes[48..].try_into().map_err(|_| INVALID_LENGTH)?))
}

fn prepare_key(op: u32, key: &[u8], proof: &[u8], output: &mut [u8]) -> Result<(), u32> {
    if op == 22 {
        if output.len() != PREPARED_IC_BYTES { return Err(INVALID_LENGTH); }
        let point = g2(key)?;
        if bool::from(point.is_identity()) { return Err(IDENTITY); }
        let table = (&mut output[96..]).try_into().map_err(|_| INVALID_LENGTH)?;
        if !write_g2_prepared(&point, table) { return Err(IDENTITY); }
        output[..96].copy_from_slice(key);
    } else {
        if output.len() != PREPARED_ETH_BYTES { return Err(INVALID_LENGTH); }
        let point = g1(key)?;
        if op == 24 {
            // Decode both operands before identity rejection, as verifyPoP does.
            let proof = g2(proof)?;
            if bool::from(point.is_identity()) || bool::from(proof.is_identity()) {
                return Err(IDENTITY);
            }
            if !pair_equal(point, G2Affine::from(hash_g2(key, ETH_POP_DST)),
                G1Affine::generator(), proof) {
                return Err(INVALID_PROOF);
            }
        } else if bool::from(point.is_identity()) { return Err(IDENTITY); }
        let affine = (&mut output[48..]).try_into().map_err(|_| INVALID_LENGTH)?;
        if !write_g1_affine(&point, affine) { return Err(IDENTITY); }
        output[..48].copy_from_slice(key);
    }
    Ok(())
}

// BLS12-381's base field modulus in canonical big-endian order.
const FP_MODULUS: [u8; 48] = [
    0x1a, 0x01, 0x11, 0xea, 0x39, 0x7f, 0xe6, 0x9a, 0x4b, 0x1b, 0xa7, 0xb6, 0x43, 0x4b, 0xac, 0xd7,
    0x64, 0x77, 0x4b, 0x84, 0xf3, 0x85, 0x12, 0xbf, 0x67, 0x30, 0xd2, 0xa0, 0xf6, 0xb0, 0xf6, 0x24,
    0x1e, 0xab, 0xff, 0xfe, 0xb1, 0x53, 0xff, 0xff, 0xb9, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xaa, 0xab,
];

fn g1(bytes: &[u8]) -> Result<G1Affine, u32> {
    let bytes: &[u8; 48] = bytes.try_into().map_err(|_| INVALID_LENGTH)?;
    // Only this one complete, canonical encoding bypasses the costly curve
    // decoder. The identity is on the curve and in the prime-order subgroup.
    if bytes[0] == 0xc0 && bytes[1..].iter().all(|b| *b == 0) {
        return Ok(G1Affine::identity());
    }
    Option::from(G1Affine::from_compressed(bytes)).ok_or(INVALID_POINT)
}

fn g2(bytes: &[u8]) -> Result<G2Affine, u32> {
    let bytes: &[u8; 96] = bytes.try_into().map_err(|_| INVALID_LENGTH)?;
    if bytes[0] == 0xc0 && bytes[1..].iter().all(|b| *b == 0) {
        return Ok(G2Affine::identity());
    }
    Option::from(G2Affine::from_compressed(bytes)).ok_or(INVALID_POINT)
}

fn scalar(bytes: &[u8]) -> Result<Scalar, u32> {
    let mut bytes: [u8; 32] = bytes.try_into().map_err(|_| INVALID_LENGTH)?;
    bytes.reverse();
    Option::from(Scalar::from_bytes(&bytes)).ok_or(INVALID_SCALAR)
}

fn field(bytes: &[u8]) -> Result<&[u8; 48], u32> {
    let bytes: &[u8; 48] = bytes.try_into().map_err(|_| INVALID_LENGTH)?;
    if bytes >= &FP_MODULUS {
        return Err(INVALID_FIELD);
    }
    Ok(bytes)
}

fn batch_len(bytes: &[u8], width: usize) -> Result<usize, u32> {
    if bytes.len() % width != 0 {
        return Err(INVALID_LENGTH);
    }
    let count = bytes.len() / width;
    if count > MAX_BATCH {
        return Err(TOO_MANY_ITEMS);
    }
    Ok(count)
}

fn hash_g1(message: &[u8], dst: &[u8]) -> G1Projective {
    <G1Projective as HashToCurve<ExpandMsgXmd<Sha256>>>::hash_to_curve(message, dst)
}

fn hash_g2(message: &[u8], dst: &[u8]) -> G2Projective {
    let mut fields = [<G2Projective as MapToCurve>::Field::default(); 2];
    <G2Projective as MapToCurve>::Field::hash_to_field::<ExpandMsgXmd<Sha256>>(
        message,
        dst,
        &mut fields,
    );
    (map_g2_field(&fields[0]) + map_g2_field(&fields[1])).clear_h()
}

fn map_g2_field(value: &<G2Projective as MapToCurve>::Field) -> G2Projective {
    if value == &<G2Projective as MapToCurve>::Field::default() {
        // bls12_381 0.8.0 (and 0.9.0) map_g2.rs overwrites the valid x0/y0
        // solution at u=0: every alternate eta candidate becomes zero and
        // its equality check spuriously succeeds. Use the fixed RFC 9380
        // SSWU+isogeny image for this single exceptional input. This constant
        // is BEFORE cofactor clearing; it was independently computed using
        // py_ecc 8.0.0 and the OCaml RFC implementation. See vectors/README.md.
        // Both field mapping and hash-to-curve use this helper, including
        // the theoretical case where a hash-to-field element is zero.
        const ZERO_IMAGE: [u8; 96] = [
            0x88, 0x69, 0x82, 0x26, 0x66, 0xfe, 0x85, 0x0c, 0xb9, 0x3d, 0xfd, 0x4f, 0xa6, 0x4e,
            0xbd, 0x9e, 0xf7, 0x7b, 0xa6, 0x2b, 0x5c, 0x12, 0x05, 0x5e, 0xad, 0xb6, 0xe7, 0xcc,
            0x89, 0x72, 0xf6, 0x4e, 0x01, 0xc4, 0x57, 0x7d, 0x3d, 0x52, 0x45, 0x6c, 0x26, 0x86,
            0x76, 0x47, 0xf5, 0x36, 0x65, 0x19, 0x0c, 0xdf, 0xcc, 0x95, 0x23, 0x30, 0x5c, 0x43,
            0xef, 0x59, 0xa4, 0xe3, 0x47, 0xcb, 0x3f, 0xc7, 0x66, 0x88, 0xc6, 0x0b, 0x05, 0xba,
            0xfe, 0xbd, 0x44, 0x5a, 0x65, 0x90, 0x1b, 0x5d, 0xd4, 0x06, 0x44, 0xe2, 0x1d, 0x35,
            0xdc, 0xbe, 0x50, 0xa9, 0x59, 0x55, 0xe4, 0xf8, 0xe2, 0x4f, 0xbe, 0x6f,
        ];
        // This fixed pre-cofactor point is on the curve, but intentionally
        // not yet in the subgroup. All caller-supplied points use checked
        // deserialization; only this implementation constant is unchecked.
        G2Projective::from(G2Affine::from_compressed_unchecked(&ZERO_IMAGE).unwrap())
    } else {
        G2Projective::map_to_curve(value)
    }
}

#[allow(deprecated)]
fn map_g1(bytes: &[u8]) -> Result<G1Projective, u32> {
    let mut padded = [0u8; 64];
    padded[16..].copy_from_slice(field(bytes)?);
    let value = <<G1Projective as MapToCurve>::Field as HashToField>::from_okm(
        GenericArray::from_slice(&padded),
    );
    Ok(G1Projective::map_to_curve(&value).clear_h())
}

#[allow(deprecated)]
fn map_g2(bytes: &[u8]) -> Result<G2Projective, u32> {
    if bytes.len() != 96 {
        return Err(INVALID_LENGTH);
    }
    let mut padded = [0u8; 128];
    // HashToField Fp2 consumes the real component before the imaginary one.
    padded[16..64].copy_from_slice(field(&bytes[..48])?);
    padded[80..128].copy_from_slice(field(&bytes[48..])?);
    let value = <<G2Projective as MapToCurve>::Field as HashToField>::from_okm(
        GenericArray::from_slice(&padded),
    );
    Ok(map_g2_field(&value).clear_h())
}

fn pair_equal(a: G1Affine, b: G2Affine, c: G1Affine, d: G2Affine) -> bool {
    bls12_381::plugin_prepared::two_term_miller_loop(
        [(&a, &b), (&-c, &d)], &G2_GENERATOR_TABLE.0)
        .final_exponentiation() == Gt::identity()
}

fn verify_ic(pk: &[u8], message: &[u8], signature: &[u8]) -> Result<bool, u32> {
    let pk = g2(pk)?;
    let signature = g1(signature)?;
    if bool::from(pk.is_identity()) || bool::from(signature.is_identity()) {
        return Err(IDENTITY);
    }
    Ok(pair_equal(
        signature,
        G2Affine::generator(),
        G1Affine::from(hash_g1(message, IC_DST)),
        pk,
    ))
}

fn verify_eth(pk: &[u8], message: &[u8], signature: &[u8], dst: &[u8]) -> Result<bool, u32> {
    let pk = g1(pk)?;
    let signature = g2(signature)?;
    if bool::from(pk.is_identity()) || bool::from(signature.is_identity()) {
        return Err(IDENTITY);
    }
    Ok(pair_equal(
        pk,
        G2Affine::from(hash_g2(message, dst)),
        G1Affine::generator(),
        signature,
    ))
}

fn verify_ic_prepared(key: &[u8], message: &[u8], signature: &[u8]) -> Result<bool, u32> {
    let key = prepared_ic(key)?;
    let signature = g1(signature)?;
    if bool::from(signature.is_identity()) { return Err(IDENTITY); }
    let hash = -G1Affine::from(hash_g1(message, IC_DST));
    Ok(prepared_miller_loop(&[
        (&signature, G2PreparedSource::TrustedBytes(&G2_GENERATOR_TABLE.0)),
        (&hash, G2PreparedSource::TrustedBytes(key.table)),
    ]).final_exponentiation() == Gt::identity())
}

fn verify_eth_prepared(key: &[u8], message: &[u8], signature: &[u8]) -> Result<bool, u32> {
    let key = prepared_eth(key)?;
    let signature = g2(signature)?;
    if bool::from(signature.is_identity()) { return Err(IDENTITY); }
    Ok(pair_equal(key, G2Affine::from(hash_g2(message, ETH_DST)),
        G1Affine::generator(), signature))
}

fn pairing_check(bytes: &[u8]) -> Result<bool, u32> {
    let count = batch_len(bytes, 144)?;
    // Decode every point before allocating the larger Miller precomputations.
    let mut points = Vec::with_capacity(count);
    for pair in bytes.chunks_exact(144) {
        let p = g1(&pair[..48])?;
        let q = g2(&pair[48..])?;
        // Validate both operands before dropping a neutral pairing term.
        if !bool::from(p.is_identity()) && !bool::from(q.is_identity()) {
            points.push((p, q));
        }
    }
    Ok(pairing_product(points))
}

// All operands passed here have already been decoded and subgroup-checked,
// or were produced by hash-to-curve. No unchecked external points enter here.
fn pairing_product(mut points: Vec<(G1Affine, G2Affine)>) -> bool {
    // Pairing is bilinear: terms sharing Q can add their P operands before
    // Miller preparation. All original encodings were checked above, even
    // terms that cancel. Keep unique P affine to avoid unnecessary inversions.
    for i in 0..points.len() {
        let (before, after) = points.split_at_mut(i + 1);
        let (p, q) = &mut before[i];
        if bool::from(p.is_identity()) {
            continue;
        }
        let mut combined = None;
        for (other_p, other_q) in after {
            if !bool::from(other_p.is_identity()) && q == other_q {
                combined = Some(combined.unwrap_or_else(|| G1Projective::from(*p)) + *other_p);
                *other_p = G1Affine::identity();
            }
        }
        if let Some(sum) = combined {
            *p = G1Affine::from(sum);
        }
    }
    points.retain(|(p, _)| !bool::from(p.is_identity()));
    if points.is_empty() {
        return true;
    }
    let prepared: Vec<_> = points.iter().map(|(_, q)| dynamic_g2_preparation(*q)).collect();
    let terms: Vec<_> = points
        .iter()
        .zip(&prepared)
        .map(|((p, _), q)| (p, pairing_source(q)))
        .collect();
    prepared_miller_loop(&terms).final_exponentiation() == Gt::identity()
}

// Width-four non-adjacent form for a canonical public scalar. A carry may
// create bit 255 even though canonical scalar encodings have only 255 bits.
fn public_wnaf(scalar: &[u8; 33]) -> [i8; 256] {
    let mut digits = [0; 256];
    let mut bit = 0;
    let mut carry = 0u16;
    while bit < 256 {
        let byte = bit / 8;
        let word = (scalar[byte] as u16) | ((scalar[byte + 1] as u16) << 8);
        let value = ((word >> (bit % 8)) & 15) + carry;
        if value & 1 == 0 {
            bit += 1;
        } else {
            carry = u16::from(value >= 8);
            digits[bit] = (value as i16 - (carry as i16 * 16)) as i8;
            bit += 4;
        }
    }
    digits
}

// Bounded public-scalar MSM: small batches share doublings using Straus;
// larger batches use signed Pippenger buckets. All scalar-dependent choices
// here are variable time. Single multiplication retains its constant-time path.
macro_rules! define_msm {
    ($name:ident, $point:ident, $decode:ident, $width:literal) => {
        fn $name(points: &[u8], scalars: &[u8]) -> Result<$point, u32> {
            let count = batch_len(points, $width)?;
            if batch_len(scalars, 32)? != count {
                return Err(INVALID_LENGTH);
            }
            if count < 2 {
                let mut sum = $point::identity();
                for (p, s) in points.chunks_exact($width).zip(scalars.chunks_exact(32)) {
                    sum += $decode(p)? * scalar(s)?;
                }
                return Ok(sum);
            }
            let mut inputs = Vec::with_capacity(count);
            for (p, s) in points.chunks_exact($width).zip(scalars.chunks_exact(32)) {
                let point = $decode(p)?;
                scalar(s)?;
                let mut little = [0u8; 33];
                for (a, b) in little[..32].iter_mut().zip(s.iter().rev()) {
                    *a = *b;
                }
                inputs.push((point, little));
            }
            if count < 4 {
                let mut tables = [[$point::identity(); 4]; 3];
                let mut digits = [[0i8; 256]; 3];
                for (i, (point, scalar)) in inputs.iter().enumerate() {
                    digits[i] = public_wnaf(scalar);
                    tables[i][0] = $point::from(*point);
                    let twice = tables[i][0].double();
                    for j in 1..4 {
                        tables[i][j] = tables[i][j - 1] + twice;
                    }
                }
                let mut result = $point::identity();
                for bit in (0..256).rev() {
                    result = result.double();
                    for i in 0..count {
                        let digit = digits[i][bit];
                        if digit > 0 {
                            result += tables[i][digit as usize / 2];
                        } else if digit < 0 {
                            result -= tables[i][(-digit) as usize / 2];
                        }
                    }
                }
                return Ok(result);
            }
            let window = match count {
                0..=4 => 3,
                5..=16 => 4,
                17..=64 => 5,
                _ => 6,
            };
            let half = 1usize << (window - 1);
            let mut buckets = [$point::identity(); 33];
            let mut result = $point::identity();
            // The extra top bit accounts for a negative digit at bit 254.
            for k in (0..256usize.div_ceil(window)).rev() {
                for _ in 0..window {
                    result = result.double();
                }
                buckets[..=half].fill($point::identity());
                let bit = k * window;
                let byte = bit / 8;
                for (point, scalar) in &inputs {
                    let word = (scalar[byte] as usize) | ((scalar[byte + 1] as usize) << 8);
                    let raw = (word >> (bit % 8)) & ((half << 1) - 1);
                    let previous = if bit == 0 { 0 } else {
                        ((scalar[(bit - 1) / 8] >> ((bit - 1) % 8)) & 1) as usize
                    };
                    // Overlapping signed radix digits (Booth recoding):
                    // lower half + preceding bit - the signed upper bit.
                    let digit = (raw & (half - 1)) as isize + previous as isize
                        - (raw & half) as isize;
                    if digit > 0 {
                        buckets[digit as usize] += point;
                    } else if digit < 0 {
                        buckets[(-digit) as usize] -= point;
                    }
                }
                let mut running = $point::identity();
                for bucket in buckets[1..=half].iter().rev() {
                    running += bucket;
                    result += running;
                }
            }
            Ok(result)
        }
    };
}
define_msm!(msm_g1, G1Projective, g1, 48);
define_msm!(msm_g2, G2Projective, g2, 96);

const G1_IDENTITY_BYTES: [u8; 48] = { let mut bytes = [0; 48]; bytes[0] = 0xc0; bytes };
const G2_IDENTITY_BYTES: [u8; 96] = { let mut bytes = [0; 96]; bytes[0] = 0xc0; bytes };

enum Output {
    G1([u8; 48]),
    G2([u8; 96]),
    Bool(bool),
}

fn execute(op: u32, a: &[u8], b: &[u8], c: &[u8]) -> Result<Output, u32> {
    match op {
        1 => Ok(Output::G1(g1(a)?.to_compressed())),
        2 => Ok(Output::G2(g2(a)?.to_compressed())),
        3 => Ok(Output::G1(
            G1Affine::from(G1Projective::from(g1(a)?) + g1(b)?).to_compressed(),
        )),
        4 => Ok(Output::G2(
            G2Affine::from(G2Projective::from(g2(a)?) + g2(b)?).to_compressed(),
        )),
        5 => Ok(Output::G1(
            G1Affine::from(g1(a)? * scalar(b)?).to_compressed(),
        )),
        6 => Ok(Output::G2(
            G2Affine::from(g2(a)? * scalar(b)?).to_compressed(),
        )),
        7 => {
            let sum = msm_g1(a, b)?;
            // Preserve the full batch/scalar error contract before the empty
            // shortcut; avoid an unnecessary projective identity inversion.
            Ok(Output::G1(if a.is_empty() { G1_IDENTITY_BYTES }
                else { G1Affine::from(sum).to_compressed() }))
        }
        8 => {
            let sum = msm_g2(a, b)?;
            Ok(Output::G2(if a.is_empty() { G2_IDENTITY_BYTES }
                else { G2Affine::from(sum).to_compressed() }))
        }
        9 => Ok(Output::G1(G1Affine::from(map_g1(a)?).to_compressed())),
        10 => Ok(Output::G2(G2Affine::from(map_g2(a)?).to_compressed())),
        11 | 12 => {
            if b.is_empty() {
                return Err(INVALID_ARGUMENT);
            }
            if op == 11 {
                Ok(Output::G1(G1Affine::from(hash_g1(a, b)).to_compressed()))
            } else {
                Ok(Output::G2(G2Affine::from(hash_g2(a, b)).to_compressed()))
            }
        }
        13 => Ok(Output::Bool(pairing_check(a)?)),
        14 => Ok(Output::Bool(verify_ic(a, b, c)?)),
        15 => Ok(Output::Bool(verify_eth(a, b, c, ETH_DST)?)),
        16 => Ok(Output::Bool(verify_eth(a, a, b, ETH_POP_DST)?)),
        17 => {
            batch_len(a, 48)?;
            if a.is_empty() { return Ok(Output::G1(G1_IDENTITY_BYTES)); }
            let mut sum = G1Projective::identity();
            for p in a.chunks_exact(48) {
                sum += g1(p)?;
            }
            Ok(Output::G1(G1Affine::from(sum).to_compressed()))
        }
        18 => {
            batch_len(a, 96)?;
            if a.is_empty() { return Ok(Output::G2(G2_IDENTITY_BYTES)); }
            let mut sum = G2Projective::identity();
            for p in a.chunks_exact(96) {
                sum += g2(p)?;
            }
            Ok(Output::G2(G2Affine::from(sum).to_compressed()))
        }
        25 => Ok(Output::Bool(verify_ic_prepared(a, b, c)?)),
        26 => Ok(Output::Bool(verify_eth_prepared(a, b, c)?)),
        _ => Err(INVALID_ARGUMENT),
    }
}

/// Uniform ABI: ops 1/3/5/7/9/11/17 write 48 bytes; 2/4/6/8/10/12/18
/// write 96 bytes; 13/14/15/16 write one boolean byte. A nonzero status leaves
/// the output unchanged. Unused inputs may be empty.
///
/// # Safety
/// Each input denotes the stated number of readable bytes, no larger than
/// isize::MAX. Null pointers are accepted only for zero length. Output denotes
/// the complete writable result size and does not overlap any input. No GC
/// safepoint occurs during the call. Allocated scratch is reclaimed by the
/// host after the synchronous frame, not by this kernel.
/// For prepared consumers, the first input must be the immutable payload
/// created by this plugin's matching protected factory. It is not a raw-byte
/// import API. Factory outputs contain only explicit initialized limbs.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bls_call(
    op: u32,
    p1: *const u8,
    n1: usize,
    p2: *const u8,
    n2: usize,
    p3: *const u8,
    n3: usize,
    out: *mut u8,
) -> u32 {
    unsafe fn input<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
        if len == 0 {
            &[]
        } else {
            unsafe { core::slice::from_raw_parts(ptr, len) }
        }
    }
    let first = unsafe { input(p1, n1) };
    let second = unsafe { input(p2, n2) };
    if (22..=24).contains(&op) {
        // Write directly into the compiler-owned output Blob. A 19.6KB table
        // must not enlarge the common output enum or be copied through stack.
        let size = if op == 22 { PREPARED_IC_BYTES } else { PREPARED_ETH_BYTES };
        let output = unsafe { core::slice::from_raw_parts_mut(out, size) };
        return match prepare_key(op, first, second, output) {
            Ok(()) => 0,
            Err(code) => code,
        };
    }
    let result = execute(op, first, second, unsafe { input(p3, n3) });
    match result {
        Ok(Output::G1(bytes)) => unsafe { core::ptr::copy_nonoverlapping(bytes.as_ptr(), out, 48) },
        Ok(Output::G2(bytes)) => unsafe { core::ptr::copy_nonoverlapping(bytes.as_ptr(), out, 96) },
        Ok(Output::Bool(value)) => unsafe { out.write(u8::from(value)) },
        Err(code) => return code,
    }
    0
}

// The generated bridge passes only borrowed Blob payloads. Each row is six
// native-width words: key pointer/length, proof pointer/length, message
// pointer/length. It checks array shape and batch bounds before allocating
// this bounded descriptor buffer. Payloads are never copied or retained.
#[derive(Clone, Copy, Default)]
struct AggregateInput<'a> {
    key: &'a [u8],
    proof: &'a [u8],
    message: &'a [u8],
}

fn distinct_messages(inputs: &[AggregateInput<'_>]) -> bool {
    let prefix = if inputs.len() < 16 { inputs.len() } else { 8 };
    for i in 0..prefix {
        if inputs[..i].iter().any(|previous| previous.message == inputs[i].message) {
            return false;
        }
    }
    if inputs.len() < 16 {
        return true;
    }
    // Sorting bounded indices avoids copying payloads and keeps large common
    // prefixes from turning a distinct-message check into quadratic work.
    let mut order = [0usize; MAX_BATCH];
    for (index, slot) in order[..inputs.len()].iter_mut().enumerate() {
        *slot = index;
    }
    let order = &mut order[..inputs.len()];
    order.sort_unstable_by(|a, b| {
        let a = inputs[*a].message;
        let b = inputs[*b].message;
        a.len().cmp(&b.len()).then_with(|| a.cmp(b))
    });
    !order.windows(2).any(|pair| inputs[pair[0]].message == inputs[pair[1]].message)
}

fn aggregate_ic(inputs: &[AggregateInput<'_>], signature: &[u8]) -> Result<bool, u32> {
    if !distinct_messages(inputs) {
        return Err(DUPLICATE_MESSAGE);
    }
    let signature = g1(signature)?;
    if bool::from(signature.is_identity()) {
        return Err(IDENTITY);
    }
    let mut terms = Vec::with_capacity(inputs.len() + 1);
    terms.push((-signature, G2Affine::generator()));
    for input in inputs {
        let key = g2(input.key)?;
        if bool::from(key.is_identity()) {
            return Err(IDENTITY);
        }
        terms.push((G1Affine::from(hash_g1(input.message, IC_DST)), key));
    }
    Ok(pairing_product(terms))
}

fn aggregate_ic_prepared(inputs: &[AggregateInput<'_>], signature: &[u8]) -> Result<bool, u32> {
    if !distinct_messages(inputs) { return Err(DUPLICATE_MESSAGE); }
    let signature = -g1(signature)?;
    if bool::from(signature.is_identity()) { return Err(IDENTITY); }
    let mut points = Vec::with_capacity(inputs.len());
    for input in inputs {
        let key = prepared_ic(input.key)?;
        points.push((G1Affine::from(hash_g1(input.message, IC_DST)), key));
    }
    // A canonical prefix identifies the key without comparing its 19.6KB
    // table. Preserve bilinear consolidation, including cancelling sums.
    for i in 0..points.len() {
        let (before, after) = points.split_at_mut(i + 1);
        let (point, key) = &mut before[i];
        if bool::from(point.is_identity()) { continue; }
        let mut combined = None;
        for (other, other_key) in after {
            if !bool::from(other.is_identity()) && key.canonical == other_key.canonical {
                combined = Some(combined.unwrap_or_else(|| G1Projective::from(*point)) + *other);
                *other = G1Affine::identity();
            }
        }
        if let Some(sum) = combined { *point = G1Affine::from(sum); }
    }
    let mut terms = Vec::with_capacity(points.len() + 1);
    terms.push((&signature, G2PreparedSource::TrustedBytes(&G2_GENERATOR_TABLE.0)));
    for (point, key) in &points {
        if !bool::from(point.is_identity()) {
            terms.push((point, G2PreparedSource::TrustedBytes(key.table)));
        }
    }
    Ok(prepared_miller_loop(&terms).final_exponentiation() == Gt::identity())
}

fn proof_checked_keys(inputs: &[AggregateInput<'_>]) -> Result<Vec<G1Affine>, u32> {
    let mut keys = Vec::with_capacity(inputs.len());
    for (i, input) in inputs.iter().enumerate() {
        if let Some(previous) = inputs[..i].iter().position(|previous| {
            previous.key == input.key && previous.proof == input.proof
        }) {
            // Reuse only an exactly equal pair whose proof already passed in
            // this call. A different proof for a repeated key is still checked.
            keys.push(keys[previous]);
            continue;
        }
        let key = g1(input.key)?;
        let proof = g2(input.proof)?;
        if bool::from(key.is_identity()) || bool::from(proof.is_identity()) {
            return Err(IDENTITY);
        }
        if !pair_equal(key, G2Affine::from(hash_g2(input.key, ETH_POP_DST)),
            G1Affine::generator(), proof) {
            return Err(INVALID_PROOF);
        }
        keys.push(key);
    }
    Ok(keys)
}

fn aggregate_eth(inputs: &[AggregateInput<'_>], signature: &[u8]) -> Result<bool, u32> {
    // Preserve the public error order: signature first, then all proofs, then
    // message hashing. This prevents any unproved key from reaching the sum.
    let signature = g2(signature)?;
    if bool::from(signature.is_identity()) {
        return Err(IDENTITY);
    }
    let keys = proof_checked_keys(inputs)?;
    Ok(aggregate_eth_with_keys(inputs, &keys, signature))
}

fn prepared_eth_keys(inputs: &[AggregateInput<'_>]) -> Result<Vec<G1Affine>, u32> {
    inputs.iter().map(|input| prepared_eth(input.key)).collect()
}

fn aggregate_eth_prepared(inputs: &[AggregateInput<'_>], signature: &[u8]) -> Result<bool, u32> {
    let signature = g2(signature)?;
    if bool::from(signature.is_identity()) { return Err(IDENTITY); }
    let keys = prepared_eth_keys(inputs)?;
    Ok(aggregate_eth_with_keys(inputs, &keys, signature))
}

fn aggregate_eth_with_keys(inputs: &[AggregateInput<'_>], keys: &[G1Affine], signature: G2Affine) -> bool {
    let mut terms = Vec::with_capacity(inputs.len() + 1);
    terms.push((-G1Affine::generator(), signature));
    for (i, input) in inputs.iter().enumerate() {
        let previous = if input.message.len() <= 1024 {
            inputs[..i].iter().position(|previous| previous.message == input.message)
        } else { None };
        let hash = match previous {
            Some(previous) => terms[previous + 1].1,
            None => G2Affine::from(hash_g2(input.message, ETH_DST)),
        };
        terms.push((keys[i], hash));
    }
    pairing_product(terms)
}

fn fast_aggregate_eth(inputs: &[AggregateInput<'_>], signature: &[u8]) -> Result<bool, u32> {
    let keys = proof_checked_keys(inputs)?;
    fast_aggregate_eth_with_keys(inputs, &keys, signature)
}

fn fast_aggregate_eth_prepared(inputs: &[AggregateInput<'_>], signature: &[u8]) -> Result<bool, u32> {
    let keys = prepared_eth_keys(inputs)?;
    fast_aggregate_eth_with_keys(inputs, &keys, signature)
}

fn fast_aggregate_eth_with_keys(inputs: &[AggregateInput<'_>], keys: &[G1Affine], signature: &[u8]) -> Result<bool, u32> {
    let mut key = G1Projective::identity();
    for part in keys {
        key += part;
    }
    let key = G1Affine::from(key);
    // Decode both operands before identity rejection, matching verifyEthereum.
    let signature = g2(signature)?;
    if bool::from(key.is_identity()) || bool::from(signature.is_identity()) {
        return Err(IDENTITY);
    }
    Ok(pair_equal(key, G2Affine::from(hash_g2(inputs[0].message, ETH_DST)),
        G1Affine::generator(), signature))
}

/// Fused profile verification. The public compiler bridge enforces matching
/// array lengths and populates every descriptor. No payload pointer survives
/// the synchronous call and no GC safepoint occurs while descriptors are live.
///
/// # Safety
/// `rows` denotes `count * 6` readable native-width words, each pointer/length
/// pair describing readable bytes (null is allowed only for empty payloads).
/// `signature` denotes `signature_len` readable bytes; `out` is one writable
/// byte disjoint from the descriptors and all payloads. Fast aggregate rows
/// must all describe the same message. Invalid statuses leave `out` unchanged.
/// Prepared operations 27–29 require matching protected-factory payloads;
/// operations 28–29 specifically require proof-validated Ethereum payloads.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bls_aggregate(
    op: u32, rows: *const usize, count: usize,
    signature: *const u8, signature_len: usize, out: *mut u8,
) -> u32 {
    let maximum = match op {
        19 | 20 | 27 | 28 => MAX_BATCH - 1,
        21 | 29 => MAX_BATCH,
        _ => return INVALID_ARGUMENT,
    };
    if count == 0 { return EMPTY_BATCH; }
    if count > maximum { return TOO_MANY_ITEMS; }
    unsafe fn bytes<'a>(pointer: *const u8, length: usize) -> &'a [u8] {
        if length == 0 { &[] } else { unsafe { core::slice::from_raw_parts(pointer, length) } }
    }
    let mut inputs = [AggregateInput::default(); MAX_BATCH];
    for (index, input) in inputs[..count].iter_mut().enumerate() {
        let row = unsafe { rows.add(index * 6).cast::<[usize; 6]>().read_unaligned() };
        *input = AggregateInput {
            key: unsafe { bytes(row[0] as *const u8, row[1]) },
            proof: unsafe { bytes(row[2] as *const u8, row[3]) },
            message: unsafe { bytes(row[4] as *const u8, row[5]) },
        };
    }
    let signature = unsafe { bytes(signature, signature_len) };
    let result = match op {
        19 => aggregate_ic(&inputs[..count], signature),
        20 => aggregate_eth(&inputs[..count], signature),
        21 => fast_aggregate_eth(&inputs[..count], signature),
        27 => aggregate_ic_prepared(&inputs[..count], signature),
        28 => aggregate_eth_prepared(&inputs[..count], signature),
        29 => fast_aggregate_eth_prepared(&inputs[..count], signature),
        _ => unreachable!(),
    };
    match result {
        Ok(value) => { unsafe { out.write(u8::from(value)) }; 0 }
        Err(error) => error,
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod prepared_tests;
