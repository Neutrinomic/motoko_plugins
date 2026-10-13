#![no_std]
/// Compute a + b + carry, returning the result and the new carry over.
#[inline(always)]
pub const fn adc(a: u64, b: u64, carry: u64) -> (u64, u64) {
    let ret = (a as u128) + (b as u128) + (carry as u128);
    (ret as u64, (ret >> 64) as u64)
}

/// Compute a - (b + borrow), returning the result and the new borrow.
#[inline(always)]
pub const fn sbb(a: u64, b: u64, borrow: u64) -> (u64, u64) {
    let ret = (a as u128).wrapping_sub((b as u128) + ((borrow >> 63) as u128));
    (ret as u64, (ret >> 64) as u64)
}

/// Compute a + (b * c) + carry, returning the result and the new carry over.
#[inline(always)]
pub const fn mac(a: u64, b: u64, c: u64, carry: u64) -> (u64, u64) {
    // WebAssembly has no widening multiply. Keep the four 32-bit products
    // inline instead of calling the compiler's generic u128 multiply helper.
    const MASK: u64 = 0xffff_ffff;
    let low = (b & MASK) * (c & MASK);
    let middle = (b >> 32) * (c & MASK) + (low >> 32);
    let cross = (b & MASK) * (c >> 32) + (middle & MASK);
    let high = (b >> 32) * (c >> 32) + (middle >> 32) + (cross >> 32);
    let low = (cross << 32) | (low & MASK);
    let (low, carry_a) = low.overflowing_add(a);
    let (low, carry_b) = low.overflowing_add(carry);
    (low, high + (carry_a as u64) + (carry_b as u64))
}


#[repr(C)]
pub struct Fp([u64;6]);
const MODULUS: [u64; 6] = [
    0xb9fe_ffff_ffff_aaab,
    0x1eab_fffe_b153_ffff,
    0x6730_d2a0_f6b0_f624,
    0x6477_4b84_f385_12bf,
    0x4b1b_a7b6_434b_acd7,
    0x1a01_11ea_397f_e69a,
];
impl Fp {
    pub const fn sub(&self, rhs: &Fp) -> Fp {
        // Reduced inputs imply -p < self - rhs < p. Add p exactly when the
        // six-limb subtraction borrowed; the result is already reduced.
        let (d0, borrow) = sbb(self.0[0], rhs.0[0], 0);
        let (d1, borrow) = sbb(self.0[1], rhs.0[1], borrow);
        let (d2, borrow) = sbb(self.0[2], rhs.0[2], borrow);
        let (d3, borrow) = sbb(self.0[3], rhs.0[3], borrow);
        let (d4, borrow) = sbb(self.0[4], rhs.0[4], borrow);
        let (d5, borrow) = sbb(self.0[5], rhs.0[5], borrow);
        let (d0, carry) = adc(d0, MODULUS[0] & borrow, 0);
        let (d1, carry) = adc(d1, MODULUS[1] & borrow, carry);
        let (d2, carry) = adc(d2, MODULUS[2] & borrow, carry);
        let (d3, carry) = adc(d3, MODULUS[3] & borrow, carry);
        let (d4, carry) = adc(d4, MODULUS[4] & borrow, carry);
        let (d5, _) = adc(d5, MODULUS[5] & borrow, carry);
        Fp([d0, d1, d2, d3, d4, d5])
    }
}
#[repr(C)]
pub struct Pair(u64,u64);
#[unsafe(no_mangle)]
pub extern "C" fn audit_mac(a:u64,b:u64,c:u64,carry:u64)->Pair { let (lo,hi)=mac(a,b,c,carry); Pair(lo,hi) }
#[unsafe(no_mangle)]
pub extern "C" fn audit_sub(a0:u64,a1:u64,a2:u64,a3:u64,a4:u64,a5:u64,b0:u64,b1:u64,b2:u64,b3:u64,b4:u64,b5:u64)->Fp { Fp([a0,a1,a2,a3,a4,a5]).sub(&Fp([b0,b1,b2,b3,b4,b5])) }
#[panic_handler]
fn panic(_: &core::panic::PanicInfo)->! { loop {} }
