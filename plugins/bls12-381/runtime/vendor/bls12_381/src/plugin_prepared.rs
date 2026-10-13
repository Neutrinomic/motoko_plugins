//! Private prepared-key payload hooks for the Motoko BLS plugin.
//!
//! These bytes are **not an external serialization format**. Only an immutable,
//! protected plugin value created by the matching validated-key factory may
//! supply a trusted reader. No key, subgroup, proof, or payload validation is
//! performed by the trusted readers. Never pass arbitrary caller bytes.
//!
//! The representation is explicit little-endian Montgomery limbs, contains no
//! native pointers or padding, and is private to this pinned crate version.
//! Readers support any byte alignment. All pairing arithmetic is the existing
//! implementation; this module only changes coefficient storage and retrieval.

use super::{
    addition_step, doubling_step, ell, miller_loop, G2Prepared, MillerLoopDriver, MillerLoopResult,
};
use crate::{fp::Fp, fp12::Fp12, fp2::Fp2, G1Affine, G2Affine, G2Projective};
use subtle::{Choice, ConditionallySelectable};

const FP_BYTES: usize = 6 * 8;
const COEFFICIENT_BYTES: usize = 3 * 2 * FP_BYTES;
const COEFFICIENT_COUNT: usize = 68;

/// Byte length of a nonidentity G2 Miller-loop coefficient table.
pub const G2_PREPARED_BYTES: usize = COEFFICIENT_COUNT * COEFFICIENT_BYTES;

/// Byte length of nonidentity G1 affine x/y coordinates in private limb form.
pub const G1_AFFINE_BYTES: usize = 2 * FP_BYTES;

fn write_fp(value: &Fp, out: &mut [u8]) {
    for (limb, bytes) in value.0.iter().zip(out.chunks_exact_mut(8)) {
        bytes.copy_from_slice(&limb.to_le_bytes());
    }
}

fn read_fp_trusted(bytes: &[u8]) -> Fp {
    let mut limbs = [0; 6];
    for (limb, bytes) in limbs.iter_mut().zip(bytes.chunks_exact(8)) {
        *limb = u64::from_le_bytes(bytes.try_into().unwrap());
    }
    Fp(limbs)
}

fn write_coefficient(value: &(Fp2, Fp2, Fp2), out: &mut [u8]) {
    let values = [
        &value.0.c0,
        &value.0.c1,
        &value.1.c0,
        &value.1.c1,
        &value.2.c0,
        &value.2.c1,
    ];
    for (value, bytes) in values.iter().zip(out.chunks_exact_mut(FP_BYTES)) {
        write_fp(value, bytes);
    }
}

fn read_coefficient_trusted(bytes: &[u8]) -> (Fp2, Fp2, Fp2) {
    let fp = |index| read_fp_trusted(&bytes[index * FP_BYTES..(index + 1) * FP_BYTES]);
    (
        Fp2 {
            c0: fp(0),
            c1: fp(1),
        },
        Fp2 {
            c0: fp(2),
            c1: fp(3),
        },
        Fp2 {
            c0: fp(4),
            c1: fp(5),
        },
    )
}

/// Writes every byte of a validated, nonidentity G1 affine point.
///
/// The caller must first validate the external key's canonical encoding, curve,
/// and subgroup. Returns false for identity without changing `out`.
/// The output is x then y; each field is six reduced Montgomery limbs in
/// little-endian order. It is not a standard point encoding.
pub fn write_g1_affine(point: &G1Affine, out: &mut [u8; G1_AFFINE_BYTES]) -> bool {
    if bool::from(point.is_identity()) {
        return false;
    }
    write_fp(&point.x, &mut out[..FP_BYTES]);
    write_fp(&point.y, &mut out[FP_BYTES..]);
    true
}

/// Restores a nonidentity G1 point from an immutable protected plugin payload.
///
/// `bytes` must be the unchanged output of `write_g1_affine` returning true,
/// from this same crate version. This does not validate field limbs, the curve,
/// or the subgroup. Never use it to deserialize caller-controlled bytes.
pub fn read_g1_affine_trusted(bytes: &[u8; G1_AFFINE_BYTES]) -> G1Affine {
    G1Affine::from_plugin_coordinates_trusted(
        read_fp_trusted(&bytes[..FP_BYTES]),
        read_fp_trusted(&bytes[FP_BYTES..]),
    )
}

/// Writes all 68 Miller-loop coefficients of a validated, nonidentity G2 point.
///
/// The caller must first validate the external key's canonical encoding, curve,
/// and subgroup. Returns false for identity without changing `out`.
/// No table allocation occurs: the existing Miller-loop driver writes directly
/// into the supplied buffer. Coefficients use loop order, then tuple order,
/// then Fp2 c0/c1 order, then six little-endian Montgomery limbs per field.
pub fn write_g2_prepared(point: &G2Affine, out: &mut [u8; G2_PREPARED_BYTES]) -> bool {
    if bool::from(point.is_identity()) {
        return false;
    }

    struct Writer<'a> {
        cur: G2Projective,
        base: G2Affine,
        out: &'a mut [u8; G2_PREPARED_BYTES],
        index: usize,
    }

    impl Writer<'_> {
        fn push(&mut self, coefficient: (Fp2, Fp2, Fp2)) {
            let start = self.index * COEFFICIENT_BYTES;
            write_coefficient(
                &coefficient,
                &mut self.out[start..start + COEFFICIENT_BYTES],
            );
            self.index += 1;
        }
    }

    impl MillerLoopDriver for Writer<'_> {
        type Output = ();

        fn doubling_step(&mut self, _: ()) {
            let coefficient = doubling_step(&mut self.cur);
            self.push(coefficient);
        }
        fn addition_step(&mut self, _: ()) {
            let coefficient = addition_step(&mut self.cur, &self.base);
            self.push(coefficient);
        }
        fn square_output(_: ()) {}
        fn conjugate(_: ()) {}
        fn one() {}
    }

    let mut writer = Writer {
        cur: G2Projective::from(*point),
        base: *point,
        out,
        index: 0,
    };
    miller_loop(&mut writer);
    assert_eq!(writer.index, COEFFICIENT_COUNT);
    true
}

/// A freshly prepared point or a borrowed protected coefficient table.
#[derive(Copy, Clone, Debug)]
pub enum G2PreparedSource<'a> {
    /// Ordinary upstream preparation; may represent the identity point.
    Owned(&'a G2Prepared),
    /// Unchanged bytes from `write_g2_prepared` returning true, made by this
    /// same crate version and kept in an immutable protected plugin value.
    /// Never construct this variant from arbitrary caller-controlled bytes.
    TrustedBytes(&'a [u8; G2_PREPARED_BYTES]),
}

impl G2PreparedSource<'_> {
    fn apply(&self, f: Fp12, index: usize, point: &G1Affine) -> Fp12 {
        let (new_f, infinity) = match self {
            Self::Owned(prepared) => (ell(f, &prepared.coeffs[index], point), prepared.infinity),
            Self::TrustedBytes(bytes) => {
                let start = index * COEFFICIENT_BYTES;
                let coefficient =
                    read_coefficient_trusted(&bytes[start..start + COEFFICIENT_BYTES]);
                (ell(f, &coefficient, point), Choice::from(0))
            }
        };
        Fp12::conditional_select(&new_f, &f, point.is_identity() | infinity)
    }
}

/// Runs the existing Miller loop with mixed owned and borrowed preparations.
///
/// Each `TrustedBytes` term must satisfy the protected-payload contract above.
/// Borrowed tables are decoded one coefficient at a time into stack values;
/// this function neither copies nor allocates complete preparation tables.
pub fn multi_miller_loop(terms: &[(&G1Affine, G2PreparedSource<'_>)]) -> MillerLoopResult {
    struct Adder<'a, 'b, 'c> {
        terms: &'a [(&'b G1Affine, G2PreparedSource<'c>)],
        index: usize,
    }

    impl Adder<'_, '_, '_> {
        fn step(&mut self, mut f: Fp12) -> Fp12 {
            for (point, prepared) in self.terms {
                f = prepared.apply(f, self.index, point);
            }
            self.index += 1;
            f
        }
    }

    impl MillerLoopDriver for Adder<'_, '_, '_> {
        type Output = Fp12;

        fn doubling_step(&mut self, f: Fp12) -> Fp12 {
            self.step(f)
        }
        fn addition_step(&mut self, f: Fp12) -> Fp12 {
            self.step(f)
        }
        fn square_output(f: Fp12) -> Fp12 {
            f.square()
        }
        fn conjugate(f: Fp12) -> Fp12 {
            f.conjugate()
        }
        fn one() -> Fp12 {
            Fp12::one()
        }
    }

    MillerLoopResult(miller_loop(&mut Adder { terms, index: 0 }))
}

#[cfg(test)]
#[path = "plugin_prepared_tests.rs"]
mod tests;
