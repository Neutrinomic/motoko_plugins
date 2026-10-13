#![no_std]
#[unsafe(no_mangle)]
pub extern "C" fn adc_old(a:u64,b:u64,c:u64,out:&mut u64)->u64 {let r=a as u128+b as u128+c as u128; *out=r as u64;(r>>64) as u64}
#[unsafe(no_mangle)]
pub extern "C" fn adc_new(a:u64,b:u64,c:u64,out:&mut u64)->u64 {let (r,c0)=a.overflowing_add(b);let(r,c1)=r.overflowing_add(c);*out=r;c0 as u64+c1 as u64}
#[unsafe(no_mangle)]
pub extern "C" fn sbb_old(a:u64,b:u64,c:u64,out:&mut u64)->u64 {let r=(a as u128).wrapping_sub(b as u128+(c>>63) as u128);*out=r as u64;(r>>64) as u64}
#[unsafe(no_mangle)]
pub extern "C" fn sbb_new(a:u64,b:u64,c:u64,out:&mut u64)->u64 {let(r,c0)=a.overflowing_sub(b);let(r,c1)=r.overflowing_sub(c>>63);*out=r;0u64.wrapping_sub((c0|c1) as u64)}
#[unsafe(no_mangle)]
pub extern "C" fn sqr_old(a:u64,x:u64,carry:u64,out:&mut u64)->u64 {
 const MASK:u64=0xffff_ffff;
 let low=(x&MASK)*(x&MASK);
 let middle=(x>>32)*(x&MASK)+(low>>32);
 let cross=(x&MASK)*(x>>32)+(middle&MASK);
 let high=(x>>32)*(x>>32)+(middle>>32)+(cross>>32);
 let low=(cross<<32)|(low&MASK);
 let(low,c0)=low.overflowing_add(a); let(low,c1)=low.overflowing_add(carry);
 *out=low;high+c0 as u64+c1 as u64
}
#[unsafe(no_mangle)]
pub extern "C" fn sqr_new(a:u64,x:u64,carry:u64,out:&mut u64)->u64 {
 const MASK:u64=0xffff_ffff;
 let l=x&MASK;let h=x>>32;let ll=l*l;let lh=l*h;
 let mid=(ll>>32)+((lh&MASK)<<1);
 let low=(mid<<32)|(ll&MASK);
 let high=h*h+((lh>>32)<<1)+(mid>>32);
 let(low,c0)=low.overflowing_add(a);let(low,c1)=low.overflowing_add(carry);
 *out=low;high+c0 as u64+c1 as u64
}

#[unsafe(no_mangle)]
pub extern "C" fn mac_old(a:u64,b:u64,c:u64,carry:u64,out:&mut u64)->u64 {
 const MASK:u64=0xffff_ffff;
 let low=(b&MASK)*(c&MASK);
 let middle=(b>>32)*(c&MASK)+(low>>32);
 let cross=(b&MASK)*(c>>32)+(middle&MASK);
 let high=(b>>32)*(c>>32)+(middle>>32)+(cross>>32);
 let low=(cross<<32)|(low&MASK);
 let(low,c0)=low.overflowing_add(a); let(low,c1)=low.overflowing_add(carry);
 *out=low;high+c0 as u64+c1 as u64
}

#[unsafe(no_mangle)]
pub extern "C" fn mac_new(a:u64,b:u64,c:u64,carry:u64,out:&mut u64)->u64 {
 const MASK:u64=0xffff_ffff;
 let low=(b&MASK)*(c&MASK);
 let middle=(b>>32)*(c&MASK)+(low>>32);
 let cross=(b&MASK)*(c>>32)+(middle&MASK);
 let high=(b>>32)*(c>>32)+(middle>>32)+(cross>>32);
 let low=b.wrapping_mul(c);
 let(low,c0)=low.overflowing_add(a); let(low,c1)=low.overflowing_add(carry);
 *out=low;high+c0 as u64+c1 as u64
}
#[unsafe(no_mangle)]
pub extern "C" fn mac_comba(a:u64,b:u64,c:u64,carry:u64,out:&mut u64)->u64 {
 const M:u64=0xffff_ffff;
 let lo=(b&M)*(c&M)+(a&M)+(carry&M);
 let cross0=(b>>32)*(c&M)+(lo>>32)+(a>>32);
 let cross1=(b&M)*(c>>32)+(cross0&M)+(carry>>32);
 let hi=(b>>32)*(c>>32)+(cross0>>32)+(cross1>>32);
 *out=(cross1<<32)|(lo&M);hi
}
