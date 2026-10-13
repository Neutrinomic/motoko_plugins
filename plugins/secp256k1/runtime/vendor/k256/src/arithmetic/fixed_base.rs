//! Immutable fixed-generator multiplication, with no runtime table setup.
//!
//! This is the upstream radix-16 `MulByGenerator` schedule, using affine
//! constants and the existing complete mixed-add formula. Every scalar uses
//! the same 65 eight-entry table scans, 65 additions and four doublings.
//! Table row indices depend only on the public loop counter. Signed scalar
//! digits are selected with `subtle`, never used as memory indices.
use super::{AffinePoint, ProjectivePoint, Scalar};
use super::mul::Radix16Decomposition;
use super::fixed_base_table::GENERATOR;
use elliptic_curve::subtle::{Choice, ConditionallySelectable, ConstantTimeEq};

fn select(table: &[AffinePoint; 8], digit: i8) -> AffinePoint {
    debug_assert!((-8..=8).contains(&digit));
    // Same signed absolute-value recoding and full scan as upstream LookupTable.
    let mask = digit >> 7;
    let magnitude = (digit + mask) ^ mask;
    let mut point = AffinePoint::IDENTITY;
    for j in 1..9 {
        point.conditional_assign(&table[j - 1], (magnitude as u8).ct_eq(&(j as u8)));
    }
    point.conditional_assign(&-point, Choice::from((mask & 1) as u8));
    point
}

pub(super) fn mul_by_generator(scalar: &Scalar) -> ProjectivePoint {
    let digits = Radix16Decomposition::<65>::new(scalar).0;
    let mut even = ProjectivePoint::from(select(&GENERATOR[32], digits[64]));
    let mut odd = ProjectivePoint::IDENTITY;
    for i in (0..32).rev() {
        odd += select(&GENERATOR[i], digits[i * 2 + 1]);
        even += select(&GENERATOR[i], digits[i * 2]);
    }
    for _ in 0..4 { odd = odd.double(); }
    even + odd
}
