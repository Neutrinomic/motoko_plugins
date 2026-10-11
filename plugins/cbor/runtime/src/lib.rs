//! RFC 8949 deterministic CBOR for compiler-specialized Motoko visitors.
//! Definite lengths make typed arrays a single-pass operation. Borrowed input
//! slices and temporary buffers live only during a synchronous, GC-free call.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(alloc_error_handler))]
extern crate alloc;
use alloc::{boxed::Box, collections::BTreeSet, string::String, vec, vec::Vec};
use core::fmt::Write;

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
        let message = b"CBOR plugin: runtime allocation or invariant failure";
        unsafe { compute_plugin_trap(message.as_ptr(), message.len()) }
    }
}
const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_ITEMS: usize = 1_000_000;
const MAX_DEPTH: usize = 128;
const MAX_INTEGER_BYTES: usize = 4096;
const MAX_LEB_BYTES: usize = (MAX_INTEGER_BYTES * 8).div_ceil(7) + 1;
struct Error {
    kind: &'static str,
    message: &'static str,
    offset: usize,
    path: String,
}
enum PathSegment {
    // Input keys and compiler-emitted field labels remain valid throughout
    // this GC-free call. No segment borrows a growing output/scratch buffer.
    Key(&'static [u8]),
    Index(usize),
}
struct ObjectFrame {
    left: usize,
    // Ordinary records avoid a tree allocation for every decoded object.
    // Keys borrow validated input bytes; even the overflow tree copies none.
    keys: [Option<&'static [u8]>; 8],
    overflow: Option<BTreeSet<&'static [u8]>>,
}
impl ObjectFrame {
    fn insert_key(&mut self, key: &'static [u8]) -> bool {
        for slot in &mut self.keys {
            match slot {
                Some(existing) if *existing == key => return false,
                None => {
                    *slot = Some(key);
                    return true;
                }
                _ => {}
            }
        }
        self.overflow.get_or_insert_with(BTreeSet::new).insert(key)
    }
}
pub struct Context {
    input: &'static [u8],
    at: usize,
    output: Vec<u8>,
    scalar: Vec<u8>,
    borrowed: Option<&'static [u8]>,
    key: &'static [u8],
    objects: Vec<ObjectFrame>,
    path: Vec<PathSegment>,
    error: Option<Error>,
    depth: usize,
    items: usize,
}
impl Context {
    fn new(input: &'static [u8]) -> Self {
        Self {
            input,
            at: 0,
            output: Vec::new(),
            scalar: Vec::new(),
            borrowed: None,
            key: &[],
            objects: Vec::new(),
            path: Vec::new(),
            error: (input.len() > MAX_BYTES).then(|| Error {
                kind: "limit",
                message: "CBOR byte limit exceeded",
                offset: 0,
                path: String::new(),
            }),
            depth: 0,
            items: 0,
        }
    }
    fn fail(&mut self, kind: &'static str, message: &'static str) {
        if self.error.is_none() {
            self.error = Some(Error {
                kind,
                message,
                offset: self.at,
                path: self.render_path(),
            });
        }
    }
    fn enter(&mut self) -> bool {
        if self.error.is_some() {
            return false;
        }
        self.depth += 1;
        self.items += 1;
        if self.depth > MAX_DEPTH || self.items > MAX_ITEMS {
            self.fail("limit", "CBOR nesting or item limit exceeded");
            self.depth -= 1;
            false
        } else {
            true
        }
    }
    fn collection(&mut self, n: usize) -> bool {
        if self.error.is_some() {
            return false;
        }
        if n > MAX_ITEMS.saturating_sub(self.items) {
            self.fail("limit", "CBOR nesting or item limit exceeded");
            false
        } else {
            true
        }
    }
    fn append(&mut self, data: &[u8]) {
        if self.error.is_some() {
            return;
        }
        if data.len() > MAX_BYTES.saturating_sub(self.output.len()) {
            self.fail("limit", "CBOR byte limit exceeded");
            return;
        }
        self.output.extend_from_slice(data);
    }
    fn check_bytes(&mut self, len: usize) -> bool {
        if self.error.is_some() {
            return false;
        }
        if !len
            .checked_add(head_size(len as u64))
            .is_some_and(|n| n <= MAX_BYTES.saturating_sub(self.output.len()))
        {
            self.fail("limit", "CBOR byte limit exceeded");
            false
        } else {
            true
        }
    }
    fn write_head(&mut self, major: u8, n: u64) {
        let mut data = [0u8; 9];
        let size = head_size(n);
        data[0] = major << 5
            | match size {
                1 => n as u8,
                2 => 24,
                3 => 25,
                5 => 26,
                _ => 27,
            };
        if size > 1 {
            data[1..size].copy_from_slice(&n.to_be_bytes()[9 - size..]);
        }
        self.append(&data[..size]);
    }
    fn write_bytes(&mut self, major: u8, data: &[u8]) {
        if self.check_bytes(data.len()) {
            self.write_head(major, data.len() as u64);
            self.append(data);
        }
    }
    fn take(&mut self, len: usize) -> &'static [u8] {
        if self.error.is_some() {
            return &[];
        }
        if len > self.input.len().saturating_sub(self.at) {
            self.fail("syntax", "Unexpected end of CBOR input");
            return &[];
        }
        let data = &self.input[self.at..self.at + len];
        self.at += len;
        data
    }
    fn head(&mut self) -> Option<(u8, u8, u64)> {
        if self.error.is_some() {
            return None;
        }
        let data = self.take(1);
        let &byte = data.first()?;
        let major = byte >> 5;
        let additional = byte & 31;
        let n = match additional {
            0..=23 => additional as u64,
            24..=27 => {
                let size = 1usize << (additional - 24);
                let data = self.take(size);
                if self.error.is_some() {
                    return None;
                }
                data.iter().fold(0, |n, b| n << 8 | u64::from(*b))
            }
            31 => {
                self.fail("unsupported", "Indefinite-length CBOR is unsupported");
                return None;
            }
            _ => {
                self.fail("syntax", "Reserved CBOR additional information");
                return None;
            }
        };
        if major == 7 && additional == 24 && n < 32 {
            self.fail("syntax", "Invalid CBOR simple value");
            return None;
        }
        Some((major, additional, n))
    }
    fn typed_head(&mut self, expected: u8, message: &'static str) -> Option<u64> {
        let (major, _, n) = self.head()?;
        if major != expected {
            self.fail("type", message);
            None
        } else {
            Some(n)
        }
    }
    fn read_bytes(&mut self, major: u8) -> &'static [u8] {
        let Some(n) = self.typed_head(
            major,
            if major == 3 {
                "Expected CBOR text"
            } else {
                "Expected CBOR byte string"
            },
        ) else {
            return &[];
        };
        if n > MAX_BYTES as u64 {
            self.fail("limit", "CBOR byte limit exceeded");
            return &[];
        }
        let data = self.take(n as usize);
        if major == 3 && core::str::from_utf8(data).is_err() {
            self.fail("utf8", "Invalid UTF-8 in CBOR text");
            return &[];
        }
        data
    }
    fn array_start(&mut self) -> usize {
        let Some(n) = self.typed_head(4, "Expected CBOR array") else {
            return 0;
        };
        if n > MAX_ITEMS as u64 || !self.collection(n as usize) {
            self.fail("limit", "CBOR nesting or item limit exceeded");
            return 0;
        }
        if n > (self.input.len() - self.at) as u64 {
            self.fail("syntax", "Unexpected end of CBOR input");
            return 0;
        }
        n as usize
    }
    fn object_start(&mut self) {
        let Some(n) = self.typed_head(5, "Expected CBOR map") else {
            return;
        };
        if n > MAX_ITEMS as u64 || !self.collection(n as usize) {
            self.fail("limit", "CBOR nesting or item limit exceeded");
            return;
        }
        if n > ((self.input.len() - self.at) / 2) as u64 {
            self.fail("syntax", "Unexpected end of CBOR input");
            return;
        }
        self.objects.push(ObjectFrame {
            left: n as usize,
            keys: [None; 8],
            overflow: None,
        });
    }
    fn object_next(&mut self) -> bool {
        if self.error.is_some() {
            return false;
        }
        let Some(frame) = self.objects.last_mut() else {
            self.fail("syntax", "Invalid CBOR map state");
            return false;
        };
        if frame.left == 0 {
            self.objects.pop();
            return false;
        }
        frame.left -= 1;
        let key = self.read_bytes(3);
        if self.error.is_some() {
            return false;
        }
        let frame = self.objects.last_mut().expect("map frame");
        if !frame.insert_key(key) {
            self.fail("duplicate", "Duplicate CBOR map key");
            return false;
        }
        self.key = key;
        true
    }
    fn push_key(&mut self) {
        self.path.push(PathSegment::Key(self.key));
    }
    fn push_index(&mut self, index: usize) {
        self.path.push(PathSegment::Index(index));
    }
    fn pop_path(&mut self) {
        self.path.pop();
    }
    fn render_path(&self) -> String {
        let mut path = String::new();
        for segment in &self.path {
            path.push('/');
            match segment {
                PathSegment::Key(key) => {
                    path.reserve(key.len());
                    for ch in core::str::from_utf8(key).expect("validated key").chars() {
                        match ch {
                            '~' => path.push_str("~0"),
                            '/' => path.push_str("~1"),
                            _ => path.push(ch),
                        }
                    }
                }
                PathSegment::Index(index) => {
                    write!(&mut path, "{index}").expect("writing to String");
                }
            }
        }
        path
    }
    fn read_integer(&mut self) -> Option<(bool, Integer)> {
        let (major, _, n) = self.head()?;
        match major {
            0 | 1 => Some((major == 1, Integer::Word(n))),
            6 if n == 2 || n == 3 => {
                let data = self.read_bytes(2);
                if data.len() > MAX_INTEGER_BYTES {
                    self.fail("limit", "CBOR integer byte limit exceeded");
                    return None;
                }
                if self.error.is_some() {
                    None
                } else {
                    Some((n == 3, Integer::Bytes(data)))
                }
            }
            _ => {
                self.fail("type", "Expected CBOR integer");
                None
            }
        }
    }
    fn read_word(&mut self, signed: bool, bits: usize) -> u64 {
        let Some((negative, integer)) = self.read_integer() else {
            return 0;
        };
        let n = match integer {
            Integer::Word(n) => n,
            Integer::Bytes(data) => {
                let data = trim_zero(data);
                if data.len() > 8 {
                    self.fail("range", "Integer is outside the requested type's range");
                    return 0;
                }
                data.iter().fold(0u64, |n, b| n << 8 | u64::from(*b))
            }
        };
        let max = if signed {
            (1u64 << (bits - 1)) - 1
        } else if bits == 64 {
            u64::MAX
        } else {
            (1u64 << bits) - 1
        };
        if n > max || (negative && !signed) {
            self.fail("range", "Integer is outside the requested type's range");
            return 0;
        }
        if negative { !n } else { n }
    }
    fn skip(&mut self) {
        if !self.enter() {
            return;
        }
        match self.input.get(self.at).map(|b| b >> 5) {
            Some(0 | 1) => {
                self.head();
            }
            Some(2 | 3) => {
                let major = self.input[self.at] >> 5;
                self.read_bytes(major);
            }
            Some(4) => {
                let n = self.array_start();
                for i in 0..n {
                    if self.error.is_some() {
                        break;
                    }
                    self.push_index(i);
                    self.skip();
                    self.pop_path();
                }
            }
            Some(5) => {
                self.object_start();
                while self.object_next() {
                    self.push_key();
                    self.skip();
                    self.pop_path();
                }
            }
            Some(6) => {
                self.read_integer();
            }
            Some(7) => {
                if let Some((_, additional, n)) = self.head() {
                    if !matches!(additional, 25..=27) && !matches!(n, 20..=22) {
                        self.fail("unsupported", "Unsupported CBOR simple value");
                    }
                }
            }
            _ => {
                self.fail("syntax", "Unexpected end of CBOR input");
            }
        }
        self.depth = self.depth.saturating_sub(1);
    }
    fn write_float(&mut self, value: f64) {
        if value.is_nan() {
            self.append(&[0xf9, 0x7e, 0]);
            return;
        }
        let small = value as f32;
        if (small as f64).to_bits() == value.to_bits() {
            if let Some(half) = exact_half(small) {
                let data = half.to_be_bytes();
                self.append(&[0xf9, data[0], data[1]]);
            } else {
                self.append(&[0xfa]);
                self.append(&small.to_bits().to_be_bytes());
            }
        } else {
            self.append(&[0xfb]);
            self.append(&value.to_bits().to_be_bytes());
        }
    }
    fn read_float(&mut self, bits: usize) -> f64 {
        let Some((major, additional, n)) = self.head() else {
            return 0.0;
        };
        if major != 7 {
            self.fail("type", "Expected CBOR float");
            return 0.0;
        }
        let value = match additional {
            25 => half_to_f64(n as u16),
            26 => f32::from_bits(n as u32) as f64,
            27 => f64::from_bits(n),
            _ => {
                self.fail("type", "Expected CBOR float");
                return 0.0;
            }
        };
        if bits == 32 && value.is_finite() && !(value as f32).is_finite() {
            self.fail("range", "Float is outside the finite range");
            return 0.0;
        }
        value
    }
}
enum Integer {
    Word(u64),
    Bytes(&'static [u8]),
}
fn head_size(n: u64) -> usize {
    if n < 24 {
        1
    } else if n <= 0xff {
        2
    } else if n <= 0xffff {
        3
    } else if n <= 0xffff_ffff {
        5
    } else {
        9
    }
}
fn trim_zero(data: &[u8]) -> &[u8] {
    &data[data.iter().position(|b| *b != 0).unwrap_or(data.len())..]
}
fn half_to_f64(bits: u16) -> f64 {
    let sign = ((bits & 0x8000) as u64) << 48;
    let exp = (bits >> 10) & 31;
    let fraction = bits & 1023;
    let raw = match exp {
        0 if fraction == 0 => sign,
        0 => {
            let shift = fraction.leading_zeros() - 5;
            let exp = 1023u64 - 14 - u64::from(shift);
            sign | exp << 52 | ((u64::from(fraction) << shift) & 1023) << 42
        }
        31 => sign | 0x7ff0_0000_0000_0000 | (u64::from(fraction) << 42),
        _ => sign | (u64::from(exp) + 1008) << 52 | u64::from(fraction) << 42,
    };
    f64::from_bits(raw)
}
fn exact_half(value: f32) -> Option<u16> {
    let raw = value.to_bits();
    let sign = ((raw >> 16) & 0x8000) as u16;
    let exp = ((raw >> 23) & 255) as i32;
    let frac = raw & 0x7f_ffff;
    if exp == 255 {
        return if frac == 0 { Some(sign | 0x7c00) } else { None };
    }
    if exp == 0 {
        return if frac == 0 { Some(sign) } else { None };
    }
    let half_exp = exp - 112;
    let result = if (1..31).contains(&half_exp) {
        if frac & 8191 != 0 {
            return None;
        }
        sign | (half_exp as u16) << 10 | (frac >> 13) as u16
    } else if (-9..=0).contains(&half_exp) {
        let shift = (14 - half_exp) as u32;
        let mantissa = frac | 0x80_0000;
        if mantissa & ((1u32 << shift) - 1) != 0 {
            return None;
        }
        sign | (mantissa >> shift) as u16
    } else {
        return None;
    };
    Some(result)
}
fn leb_to_magnitude(leb: &[u8], signed: bool) -> (bool, Vec<u8>) {
    let negative = signed && leb.last().is_some_and(|b| b & 64 != 0);
    let mut little = Vec::with_capacity((leb.len() * 7).div_ceil(8));
    let mut pending = 0u32;
    let mut bits = 0;
    for &byte in leb {
        let value = if negative { (!byte) & 127 } else { byte & 127 };
        pending |= u32::from(value) << bits;
        bits += 7;
        if bits >= 8 {
            little.push(pending as u8);
            pending >>= 8;
            bits -= 8;
        }
    }
    if bits != 0 {
        little.push(pending as u8);
    }
    while little.last() == Some(&0) {
        little.pop();
    }
    little.reverse();
    (negative, little)
}
fn magnitude_to_leb(data: &[u8], negative: bool, signed: bool, out: &mut Vec<u8>) {
    let data = trim_zero(data);
    out.clear();
    let capacity = (data.len() * 8).div_ceil(7) + 1;
    if out.capacity() < capacity {
        *out = Vec::with_capacity(capacity);
    }
    // Set continuation and sign-complement bits as each group is produced.
    // Only the final group's continuation bit then needs clearing.
    let mask = if negative { 255 } else { 128 };
    let mut pending = 0u32;
    let mut bits = 0;
    for &byte in data.iter().rev() {
        pending |= u32::from(byte) << bits;
        bits += 8;
        while bits >= 7 {
            out.push((pending & 127) as u8 ^ mask);
            pending >>= 7;
            bits -= 7;
        }
    }
    if pending != 0 || out.is_empty() {
        out.push(pending as u8 ^ mask);
    }
    while out.len() > 1 && out.last() == Some(&mask) {
        out.pop();
    }
    if signed && out.last().is_some_and(|b| (b ^ mask) & 64 != 0) {
        out.push(mask);
    }
    *out.last_mut().expect("nonempty LEB") &= 127;
}
unsafe fn ctx<'a>(ptr: usize) -> &'a mut Context {
    unsafe { &mut *(ptr as *mut Context) }
}
unsafe fn bytes<'a>(ptr: usize, len: usize) -> &'a [u8] {
    if len == 0 {
        &[]
    } else {
        unsafe { core::slice::from_raw_parts(ptr as *const u8, len) }
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_new(ptr: usize, len: usize) -> usize {
    Box::into_raw(Box::new(Context::new(unsafe { bytes(ptr, len) }))) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_done(c: usize) {
    unsafe {
        drop(Box::from_raw(c as *mut Context));
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_ok(c: usize) -> usize {
    unsafe { ctx(c) }.error.is_none() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_enter(c: usize) -> usize {
    unsafe { ctx(c) }.enter() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_leave(c: usize) {
    let c = unsafe { ctx(c) };
    c.depth = c.depth.saturating_sub(1);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_collection(c: usize, n: usize) -> usize {
    unsafe { ctx(c) }.collection(n) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_check_string(c: usize, n: usize) -> usize {
    unsafe { ctx(c) }.check_bytes(n) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_check_bigint(c: usize, n: usize) -> usize {
    let c = unsafe { ctx(c) };
    if n > MAX_LEB_BYTES {
        c.fail("limit", "CBOR integer byte limit exceeded");
    }
    c.error.is_none() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_finish(c: usize) {
    let c = unsafe { ctx(c) };
    if c.at != c.input.len() {
        c.fail("syntax", "Trailing CBOR input");
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_error_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) };
    let Some(e) = &c.error else {
        return 0;
    };
    match part {
        0 => e.kind.as_ptr() as usize,
        1 => e.kind.len(),
        2 => e.message.as_ptr() as usize,
        3 => e.message.len(),
        4 => e.path.as_ptr() as usize,
        5 => e.path.len(),
        _ => e.offset,
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_fail(c: usize, code: usize) {
    let c = unsafe { ctx(c) };
    match code {
        1 => c.fail("missing", "Missing required CBOR field"),
        2 => c.fail("type", "Unexpected CBOR variant case"),
        3 => c.fail("type", "Expected exactly one map field"),
        4 => c.fail("type", "Unexpected CBOR tuple length"),
        _ => c.fail("type", "Unexpected CBOR value"),
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_peek(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    c.input.get(c.at).copied().unwrap_or(0) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_read_null(c: usize) {
    let c = unsafe { ctx(c) };
    if let Some((major, additional, n)) = c.head() {
        if major != 7 || additional >= 24 || n != 22 {
            c.fail("type", "Expected CBOR null");
        }
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_read_bool(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    if let Some((major, additional, n)) = c.head() {
        if major == 7 && additional < 24 && (n == 20 || n == 21) {
            return (n == 21) as usize;
        }
        c.fail("type", "Expected CBOR bool");
    }
    0
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_read_string(c: usize) {
    let c = unsafe { ctx(c) };
    c.borrowed = Some(c.read_bytes(3));
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_scalar_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) };
    let data = c.borrowed.unwrap_or(&c.scalar);
    if part == 0 {
        data.as_ptr() as usize
    } else {
        data.len()
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_output_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) };
    if part == 0 {
        c.output.as_ptr() as usize
    } else {
        c.output.len()
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_object_start(c: usize) {
    unsafe { ctx(c) }.object_start();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_object_next(c: usize) -> usize {
    unsafe { ctx(c) }.object_next() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_key_eq(c: usize, ptr: usize, len: usize) -> usize {
    (unsafe { ctx(c) }.key == unsafe { bytes(ptr, len) }) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_path_key(c: usize) {
    unsafe { ctx(c) }.push_key();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_path_field(c: usize, ptr: usize, len: usize) {
    let c = unsafe { ctx(c) };
    c.key = unsafe { bytes(ptr, len) };
    c.push_key();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_path_index(c: usize, index: usize) {
    unsafe { ctx(c) }.push_index(index);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_path_pop(c: usize) {
    unsafe { ctx(c) }.pop_path();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_array_start(c: usize) -> usize {
    unsafe { ctx(c) }.array_start()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_skip(c: usize) {
    unsafe { ctx(c) }.skip();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_write_head(c: usize, major: usize, n: u64) {
    unsafe { ctx(c) }.write_head(major as u8, n);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_write_byte(c: usize, value: usize) {
    unsafe { ctx(c) }.append(&[value as u8]);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_write_string(c: usize, ptr: usize, len: usize) {
    let c = unsafe { ctx(c) };
    if c.check_bytes(len) {
        c.write_bytes(3, unsafe { bytes(ptr, len) });
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_read_word(c: usize, signed: usize, bits: usize) -> u64 {
    unsafe { ctx(c) }.read_word(signed != 0, bits)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_write_word(c: usize, value: u64, signed: usize) {
    let c = unsafe { ctx(c) };
    if signed != 0 && (value as i64) < 0 {
        c.write_head(1, !value);
    } else {
        c.write_head(0, value);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_read_char(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    let data = c.read_bytes(3);
    if c.error.is_some() {
        return 0;
    }
    let mut chars = core::str::from_utf8(data).expect("validated text").chars();
    if let Some(ch) = chars.next() {
        if chars.next().is_none() {
            return ch as usize;
        }
    }
    c.fail("type", "Expected exactly one Unicode scalar");
    0
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_write_char(c: usize, ch: usize) {
    let c = unsafe { ctx(c) };
    if let Some(ch) = char::from_u32(ch as u32) {
        let mut data = [0u8; 4];
        c.write_bytes(3, ch.encode_utf8(&mut data).as_bytes());
    } else {
        c.fail("type", "Expected exactly one Unicode scalar");
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_read_binary(c: usize, principal: usize) {
    let c = unsafe { ctx(c) };
    let data = c.read_bytes(2);
    if principal != 0 && data.len() > 29 {
        c.fail("principal", "Invalid principal bytes");
        c.borrowed = Some(&[]);
    } else {
        c.borrowed = Some(data);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_write_binary(c: usize, ptr: usize, len: usize, principal: usize) {
    let c = unsafe { ctx(c) };
    if principal != 0 && len > 29 {
        c.fail("principal", "Invalid principal bytes");
    } else if c.check_bytes(len) {
        c.write_bytes(2, unsafe { bytes(ptr, len) });
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_read_float(c: usize, bits: usize) -> f64 {
    unsafe { ctx(c) }.read_float(bits)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_write_float(c: usize, value: f64) {
    unsafe { ctx(c) }.write_float(value);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_read_bigint(c: usize, signed: usize) {
    let c = unsafe { ctx(c) };
    // The generated visitor consumes this LEB into a managed Motoko number
    // before any later read can reuse the scratch buffer.
    c.borrowed = None;
    match c.read_integer() {
        Some((negative, _)) if negative && signed == 0 => {
            c.fail("range", "Integer is outside the requested type's range");
            c.scalar = vec![0];
        }
        Some((negative, Integer::Word(n))) => {
            magnitude_to_leb(&n.to_be_bytes(), negative, signed != 0, &mut c.scalar)
        }
        Some((negative, Integer::Bytes(data))) => {
            magnitude_to_leb(data, negative, signed != 0, &mut c.scalar)
        }
        None => {
            c.scalar = vec![0];
        }
    };
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cbor_write_bigint(c: usize, ptr: usize, len: usize, signed: usize) {
    let c = unsafe { ctx(c) };
    if c.error.is_some() {
        return;
    }
    if len > MAX_LEB_BYTES {
        c.fail("limit", "CBOR integer byte limit exceeded");
        return;
    }
    let (negative, data) = leb_to_magnitude(unsafe { bytes(ptr, len) }, signed != 0);
    if data.len() > MAX_INTEGER_BYTES {
        c.fail("limit", "CBOR integer byte limit exceeded");
        return;
    }
    if data.len() <= 8 {
        c.write_head(
            if negative { 1 } else { 0 },
            data.iter().fold(0u64, |n, b| n << 8 | u64::from(*b)),
        );
    } else {
        c.write_head(6, if negative { 3 } else { 2 });
        c.write_bytes(2, &data);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn c(input: &[u8]) -> Context {
        Context::new(Box::leak(input.to_vec().into_boxed_slice()))
    }
    fn pointer(c: &mut Context) -> usize {
        c as *mut Context as usize
    }
    fn error(c: &Context) -> (&str, &str, usize, &str) {
        let e = c.error.as_ref().expect("error");
        (e.kind, e.message, e.offset, &e.path)
    }
    #[test]
    fn preferred_integer_and_length_heads() {
        for (n, expected) in [
            (0, vec![0]),
            (23, vec![23]),
            (24, vec![24, 24]),
            (255, vec![24, 255]),
            (256, vec![25, 1, 0]),
            (65535, vec![25, 255, 255]),
            (65536, vec![26, 0, 1, 0, 0]),
            (u64::MAX, vec![27, 255, 255, 255, 255, 255, 255, 255, 255]),
        ] {
            let mut w = c(&[]);
            w.write_head(0, n);
            assert_eq!(w.output, expected);
            let mut r = c(&w.output);
            assert_eq!(r.head().unwrap().2, n);
            assert_eq!(r.at, w.output.len());
        }
    }
    #[test]
    fn every_binary16_value_is_encoded_in_its_shortest_exact_width() {
        for bits in 0..=u16::MAX {
            let value = half_to_f64(bits);
            let mut w = c(&[]);
            w.write_float(value);
            if value.is_nan() {
                assert_eq!(w.output, [0xf9, 0x7e, 0]);
            } else {
                assert_eq!(w.output, [0xf9, (bits >> 8) as u8, bits as u8], "{bits:x}");
            }
            let mut r = c(&w.output);
            let decoded = r.read_float(64);
            assert!(r.error.is_none());
            assert!(
                value.is_nan() && decoded.is_nan() || value.to_bits() == decoded.to_bits(),
                "{bits:x}"
            );
        }
        for (value, len) in [
            (100000.0, 5),
            (1.1, 9),
            (f32::MIN_POSITIVE as f64, 5),
            (f64::MIN_POSITIVE, 9),
        ] {
            let mut w = c(&[]);
            w.write_float(value);
            assert_eq!(w.output.len(), len);
            assert_eq!(c(&w.output).read_float(64).to_bits(), value.to_bits());
        }
    }
    #[test]
    fn signed_and_unsigned_scalar_bridge_roundtrip() {
        for n in -20_000i64..20_000 {
            let negative = n < 0;
            let magnitude = if negative { !(n as u64) } else { n as u64 };
            let mut leb = Vec::new();
            magnitude_to_leb(&magnitude.to_be_bytes(), negative, true, &mut leb);
            let (got_negative, bytes) = leb_to_magnitude(&leb, true);
            assert_eq!(got_negative, negative);
            assert_eq!(trim_zero(&magnitude.to_be_bytes()), bytes);
            let mut w = c(&[]);
            unsafe {
                cbor_write_bigint(pointer(&mut w), leb.as_ptr() as usize, leb.len(), 1);
            }
            let mut r = c(&w.output);
            assert_eq!(r.read_word(true, 64) as i64, n);
            assert!(r.error.is_none());
        }
        for count in [9, 16, 127, 256, 4096] {
            for negative in [false, true] {
                let data: Vec<_> = (0..count).map(|i| (i * 31 + 128) as u8).collect();
                let mut leb = Vec::new();
                magnitude_to_leb(&data, negative, true, &mut leb);
                assert_eq!(leb_to_magnitude(&leb, true), (negative, data.clone()));
                let mut w = c(&[]);
                unsafe {
                    cbor_write_bigint(pointer(&mut w), leb.as_ptr() as usize, leb.len(), 1);
                }
                assert!(w.error.is_none());
                assert_eq!(w.output[0], if negative { 0xc3 } else { 0xc2 });
                let mut r = c(&w.output);
                unsafe {
                    cbor_read_bigint(pointer(&mut r), 1);
                }
                assert!(r.error.is_none());
                assert_eq!(r.scalar, leb);
            }
        }
    }
    #[test]
    fn scalar_scratch_is_reused_and_reset_between_borrowed_values_and_errors() {
        // 2^64, text, -1, 0, malformed input. Reading a borrowed string must
        // not leave scalar_part pointing at that string for the next integer.
        let mut r = c(&[
            0xc2, 0x49, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0x61, b'x', 0x20, 0, 0xff,
        ]);
        unsafe { cbor_read_bigint(pointer(&mut r), 0) };
        assert_eq!(r.scalar, [128, 128, 128, 128, 128, 128, 128, 128, 128, 2]);
        let capacity = r.scalar.capacity();
        let allocation = r.scalar.as_ptr();
        unsafe { cbor_read_string(pointer(&mut r)) };
        assert_eq!(r.borrowed, Some(&b"x"[..]));
        for (signed, expected) in [(1, 127), (0, 0)] {
            unsafe { cbor_read_bigint(pointer(&mut r), signed) };
            assert_eq!(r.scalar, [expected]);
            assert_eq!(r.scalar.capacity(), capacity);
            assert_eq!(r.scalar.as_ptr(), allocation);
            assert!(r.borrowed.is_none());
        }
        unsafe { cbor_read_bigint(pointer(&mut r), 0) };
        assert_eq!(r.scalar, [0]);
        assert_eq!(error(&r).0, "unsupported");
        let mut r = c(&[0x20]);
        unsafe { cbor_read_bigint(pointer(&mut r), 0) };
        assert_eq!(r.scalar, [0]);
        assert_eq!(
            error(&r),
            (
                "range",
                "Integer is outside the requested type's range",
                1,
                ""
            )
        );
    }
    #[test]
    fn numeric_range_and_type_errors() {
        for (input, signed, bits) in [
            (vec![0x18, 0xff], true, 8),
            (vec![0x38, 0x80], true, 8),
            (vec![0x20], false, 64),
            (vec![0x19, 1, 0], false, 8),
            (vec![0xc2, 0x49, 1, 0, 0, 0, 0, 0, 0, 0, 0], false, 64),
        ] {
            let mut r = c(&input);
            assert_eq!(r.read_word(signed, bits), 0);
            assert_eq!(error(&r).0, "range");
        }
        let mut r = c(&[0x38, 127]);
        assert_eq!(r.read_word(true, 8) as i64, -128);
        assert!(r.error.is_none());
        let mut r = c(&[0xfb, 0x7f, 0xef, 255, 255, 255, 255, 255, 255]);
        r.read_float(32);
        assert_eq!(error(&r).0, "range");
        for input in [&[0xf9, 0, 22][..], &[0xf9, 0, 20][..]] {
            let mut r = c(input);
            unsafe {
                cbor_read_null(pointer(&mut r));
            }
            assert_eq!(error(&r).0, "type");
        }
    }
    #[test]
    fn malformed_and_unsupported_input_is_recoverable() {
        for (input, kind) in [
            (vec![], "syntax"),
            (vec![0x1a, 0], "syntax"),
            (vec![0x7f], "unsupported"),
            (vec![0x1c], "syntax"),
            (vec![0x81], "syntax"),
            (vec![0xa1], "syntax"),
            (vec![0x61, 0xff], "utf8"),
            (vec![0xc0, 0], "type"),
            (vec![0xf7], "unsupported"),
            (vec![0xf8, 0x16], "syntax"),
        ] {
            let mut r = c(&input);
            r.skip();
            assert_eq!(error(&r).0, kind, "{input:?}");
        }
    }
    #[test]
    fn duplicate_keys_and_paths_in_skipped_maps_are_checked() {
        let mut r = c(&[0xa1, 0x61, b'x', 0xa2, 0x61, b'a', 0, 0x61, b'a', 1]);
        r.skip();
        assert_eq!(error(&r), ("duplicate", "Duplicate CBOR map key", 9, "/x"));
        let mut r = c(&[0xa1, 0x64, b'~', b'/', 0xc3, 0xa9, 0x81, 0x61, 0xff]);
        r.skip();
        assert_eq!(
            error(&r),
            ("utf8", "Invalid UTF-8 in CBOR text", 9, "/~0~1é/0")
        );
        let mut r = c(&[0xa1, 0, 1]);
        r.skip();
        assert_eq!(error(&r).0, "type");
    }
    #[test]
    fn duplicate_detection_covers_large_maps() {
        for count in [8, 9, 16, 100] {
            for duplicate in [0, count - 1] {
                let mut w = c(&[]);
                w.write_head(5, count + 1);
                for key in (0..count).chain(core::iter::once(duplicate)) {
                    w.write_bytes(3, alloc::format!("field-{key}").as_bytes());
                    w.write_head(0, key);
                }
                let mut r = c(&w.output);
                r.skip();
                assert_eq!(error(&r).0, "duplicate");
            }
            let mut w = c(&[]);
            w.write_head(5, count);
            for key in 0..count {
                w.write_bytes(3, alloc::format!("field-{key}").as_bytes());
                w.write_head(0, key);
            }
            let mut r = c(&w.output);
            r.skip();
            assert!(r.error.is_none());
            assert_eq!(r.at, w.output.len());
        }
    }
    #[test]
    fn malformed_byte_fuzz_always_terminates_within_input() {
        let mut seed = 0x8f3ab931u32;
        for size in 0..64 {
            for _ in 0..200 {
                let data: Vec<_> = (0..size)
                    .map(|_| {
                        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                        (seed >> 24) as u8
                    })
                    .collect();
                let mut r = c(&data);
                r.skip();
                assert!(r.at <= data.len());
            }
        }
    }
    #[test]
    fn excessive_lengths_stop_before_allocation_or_pointer_access() {
        let mut r = c(&[0x9b, 255, 255, 255, 255, 255, 255, 255, 255]);
        assert_eq!(r.array_start(), 0);
        assert_eq!(error(&r).0, "limit");
        let mut r = c(&[0x5b, 255, 255, 255, 255, 255, 255, 255, 255]);
        assert!(r.read_bytes(2).is_empty());
        assert_eq!(error(&r).0, "limit");
        let mut w = c(&[]);
        unsafe {
            cbor_write_binary(pointer(&mut w), 0, usize::MAX, 0);
        }
        assert_eq!(error(&w).0, "limit");
        assert_eq!(w.output.capacity(), 0);
        let mut w = c(&[]);
        unsafe {
            cbor_write_bigint(pointer(&mut w), 0, usize::MAX, 0);
        }
        assert_eq!(error(&w).0, "limit");
        let mut r = c(&vec![0x81; MAX_DEPTH + 1]);
        r.skip();
        assert!(r.error.is_some());
        let mut r = c(&[vec![0x81; MAX_DEPTH], vec![0]].concat());
        r.skip();
        assert_eq!(error(&r).0, "limit");
    }
    #[test]
    fn strings_and_blobs_borrow_input_until_managed_copy() {
        let data = [0x43, 0, 128, 255];
        let mut r = c(&data);
        unsafe {
            cbor_read_binary(pointer(&mut r), 0);
        }
        assert_eq!(r.borrowed, Some(&data[1..]));
        assert_eq!(r.scalar.capacity(), 0);
        let mut r = c(&[0x64, 0xf0, 0x9f, 0x98, 0x80]);
        assert_eq!(unsafe { cbor_read_char(pointer(&mut r)) }, '😀' as usize);
        let mut r = c(&[
            0x58, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0,
        ]);
        unsafe {
            cbor_read_binary(pointer(&mut r), 1);
        }
        assert_eq!(error(&r).0, "principal");
        assert_eq!(r.borrowed, Some(&[][..]));
    }
}
