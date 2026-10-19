//! Bounded, canonical typed ICWire byte operations for specialized Motoko visitors.
//! The compiler owns positional schema traversal. Input slices are borrowed for
//! one GC-free call; no schema tags, record frames, or root headers are stored.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(alloc_error_handler))]
extern crate alloc;
use alloc::{boxed::Box, vec::Vec};

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
        let message = b"ICWire plugin: runtime allocation or invariant failure";
        unsafe { compute_plugin_trap(message.as_ptr(), message.len()) }
    }
}

const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_ITEMS: usize = 1_000_000;
const MAX_DEPTH: usize = 128;
const MAX_LEB_BYTES: usize = 4096;
// Nine-byte ULEB is <2^63 and nine-byte SLEB is in [-2^62,2^62),
// leaving this bit pattern available for the borrowed-bigint fallback.
const BIG_INTEGER: u64 = 1 << 63;

#[derive(Debug)]
struct Error {
    kind: &'static str,
    offset: usize,
}
pub struct Context {
    input: &'static [u8],
    at: usize,
    output: Vec<u8>,
    scalar: &'static [u8],
    small_integer: Option<u64>,
    error: Option<Error>,
    depth: usize,
    items: usize,
    writing: bool,
}
impl Context {
    fn new(input: &'static [u8]) -> Self {
        Self {
            input,
            at: 0,
            output: Vec::new(),
            scalar: &[],
            small_integer: None,
            depth: 0,
            items: 0,
            writing: false,
            error: (input.len() > MAX_BYTES).then_some(Error {
                kind: "limit",
                offset: 0,
            }),
        }
    }
    #[inline]
    fn fail_at(&mut self, kind: &'static str, offset: usize) {
        if self.error.is_none() {
            self.error = Some(Error { kind, offset });
        }
    }
    #[inline]
    fn fail(&mut self, kind: &'static str) {
        self.fail_at(
            kind,
            if self.writing {
                self.output.len()
            } else {
                self.at
            },
        );
    }
    #[inline]
    fn charge(&mut self) -> bool {
        if self.error.is_some() {
            return false;
        }
        if self.items == MAX_ITEMS {
            self.fail("limit");
            return false;
        }
        self.items += 1;
        true
    }
    fn enter(&mut self) -> bool {
        if !self.leaf() {
            return false;
        }
        self.depth += 1;
        true
    }
    // A primitive has no descendants, so its depth need only be checked, never
    // written. This fuses enter/read/leave without changing admission ordering.
    #[inline]
    fn leaf(&mut self) -> bool {
        if self.error.is_some() {
            return false;
        }
        if self.depth == MAX_DEPTH {
            self.fail("limit");
            return false;
        }
        self.charge()
    }
    fn collection(&mut self, n: usize) -> bool {
        if self.error.is_some() {
            return false;
        }
        if n > MAX_ITEMS - self.items {
            self.fail("limit");
            return false;
        }
        true
    }
    #[inline]
    fn room(&mut self, n: usize) -> bool {
        if self.error.is_some() {
            return false;
        }
        if n > MAX_BYTES - self.output.len() {
            self.fail("limit");
            return false;
        }
        true
    }
    #[inline]
    fn append(&mut self, bytes: &[u8]) {
        self.writing = true;
        if self.room(bytes.len()) {
            self.output.extend_from_slice(bytes);
        }
    }
    #[inline]
    fn take(&mut self, len: usize) -> &'static [u8] {
        if self.error.is_some() {
            return &[];
        }
        if len > self.input.len() - self.at {
            self.fail("truncated");
            return &[];
        }
        let start = self.at;
        self.at += len;
        &self.input[start..self.at]
    }
    fn read_word(&mut self, signed: bool, bits: usize) -> u64 {
        let value = match bits {
            8 => self.take(1).first().copied().unwrap_or(0) as u64,
            16 => u16::from_le_bytes(self.take(2).try_into().unwrap_or([0; 2])) as u64,
            32 => u32::from_le_bytes(self.take(4).try_into().unwrap_or([0; 4])) as u64,
            64 => u64::from_le_bytes(self.take(8).try_into().unwrap_or([0; 8])),
            _ => {
                self.fail("type");
                return 0;
            }
        };
        if signed && bits < 64 {
            ((value << (64 - bits)) as i64 >> (64 - bits)) as u64
        } else {
            value
        }
    }
    fn read_length(&mut self) -> usize {
        let start = self.at;
        let Some(&first) = self.take(1).first() else {
            return 0;
        };
        if first < 128 {
            return first as usize;
        }
        let mut value = (first & 127) as usize;
        for shift in [7, 14, 21, 28] {
            let Some(&byte) = self.take(1).first() else {
                return 0;
            };
            if shift == 28 && byte > 15 {
                self.fail_at("canonical", start);
                return 0;
            }
            value |= ((byte & 127) as usize) << shift;
            if byte < 128 {
                if byte == 0 {
                    self.fail_at("canonical", start);
                    return 0;
                }
                return value;
            }
        }
        unreachable!("fifth length byte is terminal or rejected")
    }
    fn write_length(&mut self, value: usize) {
        self.writing = true;
        if value > u32::MAX as usize {
            self.fail("limit");
            return;
        }
        self.write_small(value as u64, false);
    }
    fn read_bool(&mut self) -> usize {
        let start = self.at;
        let data = self.take(1);
        let Some(&value) = data.first() else {
            return 0;
        };
        if value > 1 {
            self.fail_at("bool", start);
            return 0;
        }
        value as usize
    }
    fn read_char(&mut self) -> usize {
        let start = self.at;
        let value = self.read_word(false, 32) as u32;
        if char::from_u32(value).is_none() {
            self.fail_at("char", start);
            return 0;
        }
        value as usize
    }
    fn read_float(&mut self, bits: usize) -> f64 {
        let start = self.at;
        let value = match bits {
            32 => f32::from_bits(self.read_word(false, 32) as u32) as f64,
            64 => f64::from_bits(self.read_word(false, 64)),
            _ => {
                self.fail("type");
                return 0.;
            }
        };
        if !value.is_finite() {
            self.fail_at("float", start);
            return 0.;
        }
        value
    }
    fn read_words(&mut self, bits: usize) -> usize {
        self.scalar = &[];
        self.small_integer = None;
        let n = self.read_length();
        if !self.collection(n) {
            return 0;
        }
        let width = match bits {
            8 => 1,
            16 => 2,
            32 => 4,
            64 => 8,
            _ => {
                self.fail("type");
                return 0;
            }
        };
        if n != 0 && self.depth == MAX_DEPTH {
            self.fail("limit");
            return 0;
        }
        // n has already passed the <=1,000,000 item preflight, so the product
        // cannot overflow on either host or wasm64.
        let length = n * width;
        let available = self.input.len() - self.at;
        if length > available {
            self.fail_at("truncated", self.at + (available / width) * width);
            return 0;
        }
        self.scalar = self.take(length);
        self.items += n;
        n
    }
    fn write_word(&mut self, value: u64, bits: usize) {
        self.writing = true;
        match bits {
            8 => self.append(&[value as u8]),
            16 => self.append(&(value as u16).to_le_bytes()),
            32 => self.append(&(value as u32).to_le_bytes()),
            64 => self.append(&value.to_le_bytes()),
            _ => self.fail("type"),
        }
    }
    fn check_bytes(&mut self, len: usize, kind: usize) -> bool {
        self.writing = true;
        if self.error.is_some() {
            return false;
        }
        if kind > 2 {
            self.fail("type");
            return false;
        }
        if kind == 2 && len > 29 {
            self.fail("principal");
            return false;
        }
        if len > MAX_BYTES {
            self.fail("limit");
            return false;
        }
        self.room(len + length_size(len))
    }
    fn read_bytes(&mut self, kind: usize) {
        self.scalar = &[];
        let start = self.at;
        let n = self.read_length();
        if self.error.is_some() {
            return;
        }
        if kind > 2 {
            self.fail_at("type", start);
            return;
        }
        if n > MAX_BYTES {
            self.fail_at("limit", start);
            return;
        }
        if kind == 2 && n > 29 {
            self.fail_at("principal", start);
            return;
        }
        let data = self.take(n);
        if self.error.is_some() {
            return;
        }
        if kind == 1 && core::str::from_utf8(data).is_err() {
            self.fail_at("utf8", start);
            return;
        }
        self.scalar = data;
    }
    fn leaf_text(&mut self) -> usize {
        if !self.leaf() {
            return 0;
        }
        self.scalar = &[];
        let start = self.at;
        let Some(&first) = self.input.get(start) else {
            self.fail("truncated");
            return 0;
        };
        if first >= 128 {
            self.read_bytes(1);
            return if self.error.is_none() {
                self.scalar.as_ptr() as usize
            } else {
                0
            };
        }
        // One byte proves canonical ULEB32 and the byte-size cap. Since leaf()
        // established a clean context, this path needs no intermediate sticky-
        // error checks or dynamic byte-kind branches.
        self.at += 1;
        let length = first as usize;
        if length > self.input.len() - self.at {
            self.fail("truncated");
            return 0;
        }
        let end = self.at + length;
        let data = &self.input[self.at..end];
        self.at = end;
        if core::str::from_utf8(data).is_err() {
            self.fail_at("utf8", start);
            return 0;
        }
        self.scalar = data;
        data.as_ptr() as usize
    }
    fn write_bytes(&mut self, data: &[u8], kind: usize) {
        if !self.check_bytes(data.len(), kind) {
            return;
        }
        if kind == 1 && core::str::from_utf8(data).is_err() {
            self.fail("utf8");
            return;
        }
        self.write_length(data.len());
        self.output.extend_from_slice(data);
    }
    fn read_bigint(&mut self, signed: bool) {
        self.scalar = &[];
        self.small_integer = None;
        if self.error.is_some() {
            return;
        }
        let start = self.at;
        let stop = self.input.len().min(start + MAX_LEB_BYTES);
        let mut word = 0u64;
        let mut shift = 0;
        while self.at < stop {
            let b = self.input[self.at];
            self.at += 1;
            if shift < 63 {
                word |= u64::from(b & 127) << shift;
                shift += 7;
            }
            if b & 128 == 0 {
                let data = &self.input[start..self.at];
                if !minimal_leb(data, signed) {
                    self.fail_at("canonical", start);
                } else {
                    self.scalar = data;
                    if data.len() <= 9 {
                        self.small_integer = Some(if signed {
                            ((word << (64 - shift)) as i64 >> (64 - shift)) as u64
                        } else {
                            word
                        });
                    }
                }
                return;
            }
        }
        if self.at - start == MAX_LEB_BYTES {
            self.fail_at("limit", start);
        } else {
            self.fail("truncated");
        }
    }
    fn write_small(&mut self, mut value: u64, signed: bool) {
        self.writing = true;
        if self.error.is_some() {
            return;
        }
        let mut data = [0u8; 10];
        let mut n = 0;
        loop {
            let b = (value & 127) as u8;
            value = if signed {
                ((value as i64) >> 7) as u64
            } else {
                value >> 7
            };
            let done = if signed {
                value == 0 && b & 64 == 0 || value == u64::MAX && b & 64 != 0
            } else {
                value == 0
            };
            data[n] = b | if done { 0 } else { 128 };
            n += 1;
            if done {
                self.append(&data[..n]);
                return;
            }
        }
    }
    fn integer_chunk(&mut self, index: usize, signed: bool) -> u64 {
        if self.error.is_some() {
            return 0;
        }
        let start = index.saturating_mul(9);
        if index >= 3 || self.scalar.len() > 27 || start >= self.scalar.len() {
            self.fail("type");
            return 0;
        }
        // The scalar was already validated by read_bigint. One chunk holds at
        // most 63 payload bits; assembling it needs no managed number or Blob.
        let end = (start + 9).min(self.scalar.len());
        let mut word = 0u64;
        for (i, byte) in self.scalar[start..end].iter().enumerate() {
            word |= u64::from(byte & 127) << (i * 7);
        }
        if signed && end == self.scalar.len() {
            let bits = (end - start) * 7;
            ((word << (64 - bits)) as i64 >> (64 - bits)) as u64
        } else {
            word
        }
    }
    fn write_bigint(&mut self, data: &[u8], signed: bool) {
        self.writing = true;
        if self.error.is_some() {
            return;
        }
        if data.len() > MAX_LEB_BYTES {
            self.fail("limit");
            return;
        }
        if data.is_empty()
            || data.last().unwrap() & 128 != 0
            || data[..data.len() - 1].iter().any(|b| b & 128 == 0)
            || !minimal_leb(data, signed)
        {
            self.fail("canonical");
            return;
        }
        self.append(data);
    }
}
#[inline]
fn length_size(value: usize) -> usize {
    ((usize::BITS - value.leading_zeros()).max(1) as usize).div_ceil(7)
}
#[inline]
fn minimal_leb(data: &[u8], signed: bool) -> bool {
    if data.len() < 2 {
        return !data.is_empty();
    }
    let last = data[data.len() - 1];
    if signed {
        let previous = data[data.len() - 2];
        !(last == 0 && previous & 64 == 0 || last == 127 && previous & 64 != 0)
    } else {
        last != 0
    }
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
pub unsafe extern "C" fn icwire_new(ptr: usize, len: usize) -> usize {
    Box::into_raw(Box::new(Context::new(unsafe { bytes(ptr, len) }))) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_done(c: usize) {
    unsafe {
        drop(Box::from_raw(c as *mut Context));
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_ok(c: usize) -> usize {
    unsafe { ctx(c) }.error.is_none() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_enter(c: usize) -> usize {
    unsafe { ctx(c) }.enter() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leave(c: usize) {
    let c = unsafe { ctx(c) };
    c.depth = c.depth.saturating_sub(1);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_collection(c: usize, n: usize) -> usize {
    unsafe { ctx(c) }.collection(n) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_check_bytes(c: usize, len: usize, kind: usize) -> usize {
    unsafe { ctx(c) }.check_bytes(len, kind) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_check_bigint(c: usize, len: usize) -> usize {
    let c = unsafe { ctx(c) };
    c.writing = true;
    if len > MAX_LEB_BYTES {
        c.fail("limit");
    }
    c.error.is_none() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_finish(c: usize) {
    let c = unsafe { ctx(c) };
    if c.at != c.input.len() {
        c.fail("trailing");
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_error_part(c: usize, part: usize) -> usize {
    let Some(e) = &unsafe { ctx(c) }.error else {
        return 0;
    };
    match part {
        0 => e.kind.as_ptr() as usize,
        1 => e.kind.len(),
        _ => e.offset,
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_fail(c: usize, code: usize) {
    unsafe { ctx(c) }.fail(match code {
        2 => "variant",
        3 => "canonical",
        _ => "type",
    });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_output_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) };
    if part == 0 {
        c.output.as_ptr() as usize
    } else {
        c.output.len()
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_scalar_ptr(c: usize) -> usize {
    unsafe { ctx(c) }.scalar.as_ptr() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_scalar_len(c: usize) -> usize {
    unsafe { ctx(c) }.scalar.len()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_bool(c: usize) -> usize {
    unsafe { ctx(c) }.read_bool()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_bool(c: usize, value: usize) {
    let c = unsafe { ctx(c) };
    c.writing = true;
    if value > 1 {
        c.fail("bool");
    } else {
        c.append(&[value as u8]);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_word(c: usize, signed: usize, bits: usize) -> u64 {
    unsafe { ctx(c) }.read_word(signed != 0, bits)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_length(c: usize) -> usize {
    unsafe { ctx(c) }.read_length()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_length(c: usize, value: usize) {
    unsafe { ctx(c) }.write_length(value);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_word(c: usize, value: u64, bits: usize) {
    unsafe { ctx(c) }.write_word(value, bits);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_char(c: usize) -> usize {
    unsafe { ctx(c) }.read_char()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_char(c: usize, value: usize) {
    let c = unsafe { ctx(c) };
    c.writing = true;
    if value > u32::MAX as usize || char::from_u32(value as u32).is_none() {
        c.fail("char");
    } else {
        c.write_word(value as u64, 32);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_float(c: usize, bits: usize) -> f64 {
    unsafe { ctx(c) }.read_float(bits)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_float(c: usize, value: f64, bits: usize) {
    let c = unsafe { ctx(c) };
    c.writing = true;
    if !value.is_finite() {
        c.fail("float");
        return;
    }
    match bits {
        32 => {
            let value = value as f32;
            if !value.is_finite() {
                c.fail("float");
            } else {
                c.write_word(value.to_bits() as u64, 32);
            }
        }
        64 => c.write_word(value.to_bits(), 64),
        _ => c.fail("type"),
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_bytes(c: usize, kind: usize) {
    unsafe { ctx(c) }.read_bytes(kind);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_utf8_valid(ptr: usize, len: usize) -> usize {
    core::str::from_utf8(unsafe { bytes(ptr, len) }).is_ok() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_bytes(c: usize, ptr: usize, len: usize, kind: usize) {
    let c = unsafe { ctx(c) };
    if c.check_bytes(len, kind) {
        c.write_bytes(unsafe { bytes(ptr, len) }, kind);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_bigint(c: usize, signed: usize) {
    unsafe { ctx(c) }.read_bigint(signed != 0);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_integer_chunk(c: usize, index: usize, signed: usize) -> u64 {
    unsafe { ctx(c) }.integer_chunk(index, signed != 0)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_bigint(c: usize, ptr: usize, len: usize, signed: usize) {
    let c = unsafe { ctx(c) };
    if len > MAX_LEB_BYTES {
        c.fail("limit");
    } else if c.error.is_none() {
        c.write_bigint(unsafe { bytes(ptr, len) }, signed != 0);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_small(c: usize, value: u64, signed: usize) {
    unsafe { ctx(c) }.write_small(value, signed != 0);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_array(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    let n = c.read_length();
    if c.collection(n) { n } else { 0 }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_array(c: usize, n: usize) {
    let c = unsafe { ctx(c) };
    if c.collection(n) {
        c.write_length(n);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_words(c: usize, bits: usize) -> usize {
    unsafe { ctx(c) }.read_words(bits)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leaf_null(c: usize) {
    unsafe { ctx(c) }.leaf();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leaf_bool(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    if c.leaf() { c.read_bool() } else { 0 }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leaf_word(c: usize, signed: usize, bits: usize) -> u64 {
    let c = unsafe { ctx(c) };
    if c.leaf() {
        c.read_word(signed != 0, bits)
    } else {
        0
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leaf_char(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    if c.leaf() { c.read_char() } else { 0 }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leaf_float(c: usize, bits: usize) -> f64 {
    let c = unsafe { ctx(c) };
    if c.leaf() { c.read_float(bits) } else { 0. }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leaf_bytes(c: usize, kind: usize) -> usize {
    let c = unsafe { ctx(c) };
    if !c.leaf() {
        return 0;
    }
    c.read_bytes(kind);
    if c.error.is_none() {
        c.scalar.as_ptr() as usize
    } else {
        0
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leaf_text(c: usize) -> usize {
    unsafe { ctx(c) }.leaf_text()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leaf_bigint(c: usize, signed: usize) -> u64 {
    let c = unsafe { ctx(c) };
    if !c.leaf() {
        return BIG_INTEGER;
    }
    c.read_bigint(signed != 0);
    c.small_integer.unwrap_or(BIG_INTEGER)
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloc::vec;

    fn c(input: &[u8]) -> Context {
        Context::new(Box::leak(input.to_vec().into_boxed_slice()))
    }
    fn ptr(c: &mut Context) -> usize {
        c as *mut Context as usize
    }
    fn kind(c: &Context) -> &str {
        c.error.as_ref().expect("error").kind
    }
    fn offset(c: &Context) -> usize {
        c.error.as_ref().expect("error").offset
    }
    fn clean(c: &Context) {
        assert!(c.error.is_none(), "{:?}", c.error);
    }
    fn leb_unsigned(mut value: u64) -> Vec<u8> {
        let mut out = Vec::new();
        loop {
            let b = (value & 127) as u8;
            value >>= 7;
            out.push(b | if value == 0 { 0 } else { 128 });
            if value == 0 {
                return out;
            }
        }
    }
    fn leb_signed(mut value: i64) -> Vec<u8> {
        let mut out = Vec::new();
        loop {
            let b = (value & 127) as u8;
            value >>= 7;
            let done = value == 0 && b & 64 == 0 || value == -1 && b & 64 != 0;
            out.push(b | if done { 0 } else { 128 });
            if done {
                return out;
            }
        }
    }
    #[test]
    fn all_fixed_width_words_and_sign_extension() {
        for bits in [8, 16, 32, 64] {
            for value in [
                0,
                1,
                127,
                128,
                255,
                256,
                32767,
                32768,
                65535,
                1 << 31,
                1 << 32,
                1 << 63,
                u64::MAX,
            ] {
                let mut w = c(&[]);
                w.write_word(value, bits);
                let expected = if bits == 64 {
                    value
                } else {
                    value & ((1 << bits) - 1)
                };
                assert_eq!(w.output.len(), bits / 8);
                assert_eq!(c(&w.output).read_word(false, bits), expected);
                let signed = if bits == 64 {
                    expected
                } else {
                    ((expected << (64 - bits)) as i64 >> (64 - bits)) as u64
                };
                assert_eq!(c(&w.output).read_word(true, bits), signed);
                for n in 0..w.output.len() {
                    let mut r = c(&w.output[..n]);
                    assert_eq!(r.read_word(false, bits), 0);
                    assert_eq!(kind(&r), "truncated");
                    assert_eq!(r.at, 0);
                }
            }
        }
        for value in 0..=u16::MAX {
            let data = value.to_le_bytes();
            assert_eq!(c(&data).read_word(true, 16) as i64, value as i16 as i64);
        }
    }
    #[test]
    fn every_boolean_and_option_tag() {
        for byte in 0..=u8::MAX {
            let mut r = c(&[byte]);
            let value = unsafe { icwire_read_bool(ptr(&mut r)) };
            let mut w = c(&[]);
            unsafe {
                icwire_write_bool(ptr(&mut w), byte as usize);
            }
            if byte <= 1 {
                clean(&r);
                clean(&w);
                assert_eq!(value, byte as usize);
                assert_eq!(w.output, [byte]);
            } else {
                assert_eq!(kind(&r), "bool");
                assert_eq!(kind(&w), "bool");
                assert_eq!(offset(&r), 0);
            }
        }
    }
    #[test]
    fn chars_validate_scalar_boundaries() {
        for ch in [0, 0x7f, 0x80, 0x10ff, 0xd7ff, 0xe000, 0xffff, 0x10ffff] {
            let mut w = c(&[]);
            unsafe {
                icwire_write_char(ptr(&mut w), ch);
            }
            let mut r = c(&w.output);
            assert_eq!(unsafe { icwire_read_char(ptr(&mut r)) }, ch);
            clean(&r);
        }
        for ch in [0xd800u32, 0xdbff, 0xdfff, 0x110000, u32::MAX] {
            let mut r = c(&ch.to_le_bytes());
            unsafe {
                icwire_read_char(ptr(&mut r));
            }
            let mut w = c(&[]);
            unsafe {
                icwire_write_char(ptr(&mut w), ch as usize);
            }
            assert_eq!(kind(&r), "char");
            assert_eq!(kind(&w), "char");
        }
        let mut w = c(&[]);
        unsafe {
            icwire_write_char(ptr(&mut w), usize::MAX);
        }
        assert_eq!(kind(&w), "char");
    }
    #[test]
    fn floats_preserve_signed_zero_and_exact_bits() {
        for value in [
            0.,
            -0.,
            1.,
            -1.,
            f64::MIN,
            f64::MAX,
            f64::MIN_POSITIVE,
            f64::from_bits(1),
        ] {
            let mut w = c(&[]);
            unsafe {
                icwire_write_float(ptr(&mut w), value, 64);
            }
            let mut r = c(&w.output);
            let actual = unsafe { icwire_read_float(ptr(&mut r), 64) };
            clean(&w);
            clean(&r);
            assert_eq!(actual.to_bits(), value.to_bits());
        }
        for value in [
            0f32,
            -0.,
            1.,
            -1.,
            f32::MIN,
            f32::MAX,
            f32::MIN_POSITIVE,
            f32::from_bits(1),
        ] {
            let mut w = c(&[]);
            unsafe {
                icwire_write_float(ptr(&mut w), value as f64, 32);
            }
            let mut r = c(&w.output);
            let actual = unsafe { icwire_read_float(ptr(&mut r), 32) } as f32;
            clean(&w);
            clean(&r);
            assert_eq!(actual.to_bits(), value.to_bits());
        }
        for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            let mut w = c(&[]);
            unsafe {
                icwire_write_float(ptr(&mut w), value, 64);
            }
            assert_eq!(kind(&w), "float");
            let mut r = c(&value.to_le_bytes());
            unsafe {
                icwire_read_float(ptr(&mut r), 64);
            }
            assert_eq!(kind(&r), "float");
        }
        for value in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            let mut r = c(&value.to_le_bytes());
            unsafe {
                icwire_read_float(ptr(&mut r), 32);
            }
            assert_eq!(kind(&r), "float");
        }
        let mut w = c(&[]);
        unsafe {
            icwire_write_float(ptr(&mut w), f64::MAX, 32);
        }
        assert_eq!(kind(&w), "float");
    }
    #[test]
    fn byte_strings_are_borrowed_and_length_checked() {
        for kind_ in 0..=2 {
            for data in [&[][..], b"abc", "λ🌍".as_bytes()] {
                let mut w = c(&[]);
                w.write_bytes(data, kind_);
                let mut r = c(&w.output);
                r.read_bytes(kind_);
                clean(&r);
                assert_eq!(r.scalar, data);
                assert_eq!(r.scalar.as_ptr(), unsafe { r.input.as_ptr().add(1) });
                for n in 0..w.output.len() {
                    let mut r = c(&w.output[..n]);
                    r.read_bytes(kind_);
                    assert_eq!(kind(&r), "truncated");
                }
            }
        }
        let mut r = c(&leb_unsigned(u32::MAX as u64));
        r.read_bytes(0);
        assert_eq!(kind(&r), "limit");
        assert_eq!(offset(&r), 0);
        let mut w = c(&[]);
        w.write_bytes(&[0; 29], 2);
        clean(&w);
        let mut w = c(&[]);
        w.write_bytes(&[0; 30], 2);
        assert_eq!(kind(&w), "principal");
        let mut r = c(&[30]);
        r.read_bytes(2);
        assert_eq!(kind(&r), "principal");
    }
    #[test]
    fn utf8_rejects_overlong_surrogates_invalid_continuations() {
        for data in [
            &[0x80][..],
            &[0xc0, 0x80],
            &[0xe0, 0x80, 0x80],
            &[0xed, 0xa0, 0x80],
            &[0xf4, 0x90, 0x80, 0x80],
            &[0xf0, 0x9f],
        ] {
            assert_eq!(
                unsafe { icwire_utf8_valid(data.as_ptr() as usize, data.len()) },
                0
            );
            let mut w = c(&[]);
            w.write_bytes(data, 1);
            assert_eq!(kind(&w), "utf8");
            let mut w = c(&[]);
            w.write_bytes(data, 0);
            let mut r = c(&w.output);
            r.read_bytes(1);
            assert_eq!(kind(&r), "utf8");
            assert_eq!(offset(&r), 0);
        }
        for data in [b"".as_slice(), b"ASCII", "λ🌍".as_bytes()] {
            assert_eq!(
                unsafe { icwire_utf8_valid(data.as_ptr() as usize, data.len()) },
                1
            );
        }
    }
    #[test]
    fn leb_integer_property_roundtrip_and_borrowing() {
        let mut seed = 0x2545f4914f6cdd1du64;
        for i in 0..20000 {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            let word = if i < 1024 { i } else { seed };
            for signed in [false, true] {
                let data = if signed {
                    leb_signed(word as i64)
                } else {
                    leb_unsigned(word)
                };
                let mut w = c(&[]);
                w.write_bigint(&data, signed);
                clean(&w);
                assert_eq!(w.output, data);
                let mut w = c(&[]);
                w.write_small(word, signed);
                clean(&w);
                assert_eq!(w.output, data);
                let mut r = c(&data);
                r.read_bigint(signed);
                clean(&r);
                assert_eq!(r.scalar, data);
                assert_eq!(r.scalar.as_ptr(), r.input.as_ptr());
                assert_eq!(r.small_integer, (data.len() <= 9).then_some(word));
                let mut leaf = c(&data);
                assert_eq!(
                    unsafe { icwire_leaf_bigint(ptr(&mut leaf), signed as usize) },
                    if data.len() <= 9 { word } else { BIG_INTEGER }
                );
                clean(&leaf);
                assert_eq!(leaf.scalar, data);
                for n in 0..data.len() {
                    let mut r = c(&data[..n]);
                    r.read_bigint(signed);
                    assert_eq!(kind(&r), "truncated");
                }
            }
        }
    }
    #[test]
    fn exhaustive_two_byte_leb_canonicality() {
        for first in 128u8..=255 {
            for last in 0u8..128 {
                for signed in [false, true] {
                    let canonical = if signed {
                        !(last == 0 && first & 64 == 0 || last == 127 && first & 64 != 0)
                    } else {
                        last != 0
                    };
                    let mut r = c(&[first, last]);
                    r.read_bigint(signed);
                    let mut w = c(&[]);
                    w.write_bigint(&[first, last], signed);
                    assert_eq!(r.error.is_none(), canonical);
                    assert_eq!(w.error.is_none(), canonical);
                    if !canonical {
                        assert_eq!(kind(&r), "canonical");
                        assert_eq!(offset(&r), 0);
                    }
                }
            }
        }
    }
    #[test]
    fn leb_lengths_and_invalid_encodings() {
        for data in [&[][..], &[0x80], &[0, 0], &[0x80, 0], &[0xff, 0]] {
            let mut w = c(&[]);
            w.write_bigint(data, false);
            assert_eq!(kind(&w), "canonical");
        }
        for signed in [false, true] {
            let mut data = vec![0x81; MAX_LEB_BYTES];
            *data.last_mut().unwrap() = 1;
            let mut w = c(&[]);
            w.write_bigint(&data, signed);
            clean(&w);
            let mut r = c(&data);
            r.read_bigint(signed);
            clean(&r);
            assert_eq!(r.scalar.len(), MAX_LEB_BYTES);
            data.insert(0, 0x81);
            let mut w = c(&[]);
            w.write_bigint(&data, signed);
            assert_eq!(kind(&w), "limit");
            let mut r = c(&data);
            r.read_bigint(signed);
            assert_eq!(kind(&r), "limit");
        }
    }
    #[test]
    fn small_integer_boundaries_and_borrowed_parts() {
        for word in [
            0,
            1,
            63,
            64,
            127,
            128,
            255,
            1 << 55,
            (1 << 62) - 1,
            1 << 62,
            (1 << 63) - 1,
            1 << 63,
            u64::MAX,
            (-64i64) as u64,
            (-65i64) as u64,
            (-(1i64 << 62)) as u64,
        ] {
            for signed in [false, true] {
                let mut w = c(&[]);
                unsafe {
                    icwire_write_small(ptr(&mut w), word, signed as usize);
                }
                let expected = if signed {
                    leb_signed(word as i64)
                } else {
                    leb_unsigned(word)
                };
                assert_eq!(w.output, expected);
                clean(&w);
                let mut r = c(&expected);
                r.read_bigint(signed);
                clean(&r);
                let p = ptr(&mut r);
                assert_eq!(r.small_integer, (expected.len() <= 9).then_some(word));
                assert_eq!(unsafe { icwire_scalar_len(p) }, expected.len());
                assert_eq!(unsafe { icwire_scalar_ptr(p) }, r.scalar.as_ptr() as usize);
            }
        }
        let mut r = c(&[1, 0x80]);
        r.read_bigint(false);
        assert_eq!(r.small_integer, Some(1));
        r.read_bigint(false);
        assert_eq!(kind(&r), "truncated");
        assert_eq!(offset(&r), 2);
        assert_eq!(r.small_integer, None);
        let mut r = c(&[0x80, 0x80]);
        r.read_bigint(false);
        assert_eq!(kind(&r), "truncated");
        assert_eq!(offset(&r), 2);
    }
    #[test]
    fn direct_leaf_bigint_sentinel_never_conflicts_with_small_value() {
        for signed in [false, true] {
            for word in [
                0,
                (1u64 << 62) - 1,
                1 << 62,
                (1u64 << 63) - 1,
                1 << 63,
                u64::MAX,
                (-(1i64 << 62)) as u64,
            ] {
                let data = if signed {
                    leb_signed(word as i64)
                } else {
                    leb_unsigned(word)
                };
                let mut r = c(&data);
                let result = unsafe { icwire_leaf_bigint(ptr(&mut r), signed as usize) };
                clean(&r);
                assert_eq!(r.scalar, data);
                assert_eq!(r.items, 1);
                assert_eq!(r.depth, 0);
                if data.len() <= 9 {
                    assert_eq!(result, word);
                    assert_ne!(result, BIG_INTEGER);
                } else {
                    assert_eq!(result, BIG_INTEGER);
                    assert_eq!(r.small_integer, None);
                }
            }
        }
        let mut r = c(&[7]);
        r.small_integer = Some(123);
        r.items = MAX_ITEMS;
        assert_eq!(unsafe { icwire_leaf_bigint(ptr(&mut r), 0) }, BIG_INTEGER);
        assert_eq!(kind(&r), "limit");
        assert_eq!(r.at, 0);
        let mut r = c(&[0x80]);
        assert_eq!(unsafe { icwire_leaf_bigint(ptr(&mut r), 0) }, BIG_INTEGER);
        assert_eq!(kind(&r), "truncated");
        assert_eq!(offset(&r), 1);
    }
    #[test]
    fn exact_byte_limit_and_sticky_errors() {
        let data = vec![0; MAX_BYTES];
        let mut r = c(&data);
        clean(&r);
        r.at = data.len();
        unsafe {
            icwire_finish(ptr(&mut r));
        }
        clean(&r);
        let mut data = data;
        data.push(0);
        let r = c(&data);
        assert_eq!(kind(&r), "limit");
        assert_eq!(offset(&r), 0);
        let mut w = c(&[]);
        w.append(&data[..MAX_BYTES]);
        clean(&w);
        w.append(&[1]);
        assert_eq!(kind(&w), "limit");
        assert_eq!(w.output.len(), MAX_BYTES);
        let mut r = c(&[2]);
        unsafe {
            icwire_read_bool(ptr(&mut r));
        }
        r.fail("type");
        r.read_bigint(false);
        assert_eq!(kind(&r), "bool");
        assert_eq!(offset(&r), 0);
        assert!(r.scalar.is_empty());
    }
    #[test]
    fn bulk_words_borrow_payload_and_match_scalar_truncation_offsets() {
        for bits in [8, 16, 32, 64] {
            for n in 0..17 {
                let mut w = c(&[]);
                w.write_length(n);
                for value in 0..n {
                    w.write_word((value as u64).wrapping_mul(0xffff000000000001), bits);
                }
                let mut r = c(&w.output);
                assert_eq!(r.read_words(bits), n);
                clean(&r);
                assert_eq!(r.items, n);
                assert_eq!(r.scalar, &w.output[1..]);
                assert_eq!(r.scalar.as_ptr(), unsafe { r.input.as_ptr().add(1) });
                assert_eq!(r.at, w.output.len());
                for end in 0..w.output.len() {
                    let mut scalar = c(&w.output[..end]);
                    let count = unsafe { icwire_read_array(ptr(&mut scalar)) };
                    for _ in 0..count {
                        if scalar.enter() {
                            scalar.read_word(false, bits);
                            unsafe {
                                icwire_leave(ptr(&mut scalar));
                            }
                        }
                    }
                    let mut bulk = c(&w.output[..end]);
                    assert_eq!(bulk.read_words(bits), 0);
                    assert_eq!(kind(&bulk), kind(&scalar));
                    assert_eq!(offset(&bulk), offset(&scalar));
                }
            }
        }
    }
    #[test]
    fn fused_leaf_reads_preserve_values_errors_and_admission_order() {
        let operation = |r: &mut Context, which, fused| -> u64 {
            if fused {
                unsafe {
                    match which {
                        0 => {
                            icwire_leaf_null(ptr(r));
                            0
                        }
                        1 => icwire_leaf_bool(ptr(r)) as u64,
                        2 => icwire_leaf_word(ptr(r), 1, 32),
                        3 => icwire_leaf_char(ptr(r)) as u64,
                        4 => icwire_leaf_float(ptr(r), 64).to_bits(),
                        5 => {
                            icwire_leaf_bytes(ptr(r), 1);
                            0
                        }
                        _ => {
                            icwire_leaf_bigint(ptr(r), 1);
                            0
                        }
                    }
                }
            } else {
                if !r.enter() {
                    return 0;
                }
                let result = match which {
                    0 => 0,
                    1 => r.read_bool() as u64,
                    2 => r.read_word(true, 32),
                    3 => r.read_char() as u64,
                    4 => r.read_float(64).to_bits(),
                    5 => {
                        r.read_bytes(1);
                        0
                    }
                    _ => {
                        r.read_bigint(true);
                        0
                    }
                };
                unsafe {
                    icwire_leave(ptr(r));
                }
                result
            }
        };
        let inputs: &[&[u8]] = &[
            &[],
            &[0],
            &[1],
            &[2],
            &[0x80],
            &[0xff],
            &[0x80, 0],
            &[0xff, 0x7f],
            &[0, 0xd8, 0, 0],
            &[1, 0, 0, 0, 0x80],
            &[1, 0, 0, 0, b'a'],
            &[0; 8],
            &[0xff; 8],
            &[0, 0, 0, 0, 0, 0, 0xf0, 0x7f],
        ];
        for input in inputs {
            for which in 0..7 {
                for depth in [0, MAX_DEPTH - 1, MAX_DEPTH] {
                    for items in [0, MAX_ITEMS - 1, MAX_ITEMS] {
                        let mut old = c(input);
                        old.depth = depth;
                        old.items = items;
                        let mut new = c(input);
                        new.depth = depth;
                        new.items = items;
                        assert_eq!(
                            operation(&mut new, which, true),
                            operation(&mut old, which, false)
                        );
                        assert_eq!(
                            new.error.as_ref().map(|e| (e.kind, e.offset)),
                            old.error.as_ref().map(|e| (e.kind, e.offset))
                        );
                        assert_eq!(new.items, old.items);
                        assert_eq!(new.at, old.at);
                        assert_eq!(new.depth, depth);
                        assert_eq!(new.scalar, old.scalar);
                        assert_eq!(new.small_integer, old.small_integer);
                    }
                }
            }
        }
    }
    #[test]
    fn canonical_u32_lengths_and_ordinals_roundtrip() {
        let mut random = 0x12345678u32;
        for iteration in 0..20000 {
            random ^= random << 13;
            random ^= random >> 17;
            random ^= random << 5;
            let value = if iteration < 1024 { iteration } else { random };
            let mut w = c(&[]);
            w.write_length(value as usize);
            assert_eq!(w.output, leb_unsigned(value as u64));
            assert_eq!(w.output.len(), length_size(value as usize));
            let mut r = c(&w.output);
            assert_eq!(r.read_length(), value as usize);
            clean(&r);
            for end in 0..w.output.len() {
                let mut r = c(&w.output[..end]);
                r.read_length();
                assert_eq!(kind(&r), "truncated");
                assert_eq!(offset(&r), end);
            }
        }
        for value in [
            0,
            127,
            128,
            16383,
            16384,
            1 << 21,
            1 << 28,
            u32::MAX as usize,
        ] {
            let mut w = c(&[]);
            unsafe {
                icwire_write_length(ptr(&mut w), value);
            }
            let mut r = c(&w.output);
            assert_eq!(unsafe { icwire_read_length(ptr(&mut r)) }, value);
            clean(&r);
        }
    }
    #[test]
    fn length_overflow_and_nonminimal_encodings_are_rejected() {
        for first in 128..=255u8 {
            for last in 0..128u8 {
                let mut r = c(&[first, last]);
                let actual = r.read_length();
                if last == 0 {
                    assert_eq!(kind(&r), "canonical");
                    assert_eq!(offset(&r), 0);
                } else {
                    clean(&r);
                    assert_eq!(actual, (first & 127) as usize | ((last as usize) << 7));
                }
            }
        }
        for last in 16..=255u8 {
            let mut r = c(&[0x80, 0x80, 0x80, 0x80, last]);
            r.read_length();
            assert_eq!(kind(&r), "canonical");
            assert_eq!(offset(&r), 0);
        }
        for data in [
            &[0x80, 0][..],
            &[0x80, 0x80, 0],
            &[0xff, 0xff, 0xff, 0xff, 0],
        ] {
            let mut r = c(data);
            r.read_length();
            assert_eq!(kind(&r), "canonical");
            assert_eq!(offset(&r), 0);
        }
        let mut w = c(&[]);
        w.write_length(u32::MAX as usize + 1);
        assert_eq!(kind(&w), "limit");
        assert!(w.output.is_empty());
    }
    #[test]
    fn raw_zero_byte_values_and_positional_records() {
        let mut r = c(&[]);
        unsafe {
            icwire_leaf_null(ptr(&mut r));
            icwire_finish(ptr(&mut r));
        }
        clean(&r);
        assert_eq!(r.items, 1);
        // Compiled schema order: Bool, Nat16, ?Nat, Blob, variant(Nat).
        let mut w = c(&[]);
        unsafe {
            icwire_write_bool(ptr(&mut w), 1);
        }
        w.write_word(0x1234, 16);
        unsafe {
            icwire_write_bool(ptr(&mut w), 0);
        }
        w.write_bytes(&[8, 9], 0);
        w.write_length(2);
        w.write_small(300, false);
        assert_eq!(w.output, [1, 0x34, 0x12, 0, 2, 8, 9, 2, 0xac, 2]);
        let decode = |r: &mut Context| {
            if !r.enter() {
                return;
            }
            unsafe {
                icwire_leaf_bool(ptr(r));
                icwire_leaf_word(ptr(r), 0, 16);
            }
            if r.enter() {
                r.read_bool();
                unsafe {
                    icwire_leave(ptr(r));
                }
            }
            unsafe {
                icwire_leaf_bytes(ptr(r), 0);
            }
            if r.enter() {
                r.read_length();
                unsafe {
                    icwire_leaf_bigint(ptr(r), 0);
                    icwire_leave(ptr(r));
                }
            }
            unsafe {
                icwire_leave(ptr(r));
                icwire_finish(ptr(r));
            }
        };
        let mut r = c(&w.output);
        decode(&mut r);
        clean(&r);
        assert_eq!(r.items, 7);
        for end in 0..w.output.len() {
            let mut r = c(&w.output[..end]);
            decode(&mut r);
            assert_eq!(kind(&r), "truncated");
        }
        let mut extra = w.output;
        extra.push(0);
        let mut r = c(&extra);
        decode(&mut r);
        assert_eq!(kind(&r), "trailing");
        assert_eq!(offset(&r), 10);
    }
    #[test]
    fn raw_array_node_and_depth_limits_precede_allocation() {
        let mut r = c(&leb_unsigned(MAX_ITEMS as u64));
        assert!(r.enter());
        assert_eq!(unsafe { icwire_read_array(ptr(&mut r)) }, 0);
        assert_eq!(kind(&r), "limit");
        let mut r = c(&leb_unsigned((MAX_ITEMS - 1) as u64));
        assert!(r.enter());
        assert_eq!(unsafe { icwire_read_array(ptr(&mut r)) }, MAX_ITEMS - 1);
        clean(&r);
        let mut r = c(&[0]);
        r.depth = MAX_DEPTH;
        assert_eq!(r.read_words(64), 0);
        clean(&r);
        let mut r = c(&[1]);
        r.depth = MAX_DEPTH;
        r.read_words(64);
        assert_eq!(kind(&r), "limit");
        assert_eq!(offset(&r), 1);
        let mut r = c(&[1]);
        r.items = MAX_ITEMS;
        r.read_words(64);
        assert_eq!(kind(&r), "limit");
        assert_eq!(offset(&r), 1);
        let mut r = c(&[]);
        for _ in 0..MAX_DEPTH {
            assert!(r.enter());
        }
        assert!(!r.enter());
        assert_eq!(kind(&r), "limit");
        let mut w = c(&[]);
        w.items = MAX_ITEMS;
        unsafe {
            icwire_write_array(ptr(&mut w), 1);
        }
        assert_eq!(kind(&w), "limit");
        assert!(w.output.is_empty());
    }
    #[test]
    fn byte_lengths_admission_and_raw_payload_limit() {
        for (n, expected) in [(MAX_BYTES + 1, "limit"), (MAX_BYTES, "truncated")] {
            let mut r = c(&leb_unsigned(n as u64));
            r.read_bytes(0);
            assert_eq!(kind(&r), expected);
            if expected == "limit" {
                assert_eq!(offset(&r), 0);
            }
        }
        let mut w = c(&[]);
        assert!(w.check_bytes(MAX_BYTES - 4, 0));
        assert!(!w.check_bytes(MAX_BYTES - 3, 0));
        assert_eq!(kind(&w), "limit");
        let mut w = c(&[]);
        assert!(!w.check_bytes(usize::MAX, 0));
        assert_eq!(kind(&w), "limit");
        for n in [0, 1, 127, 128, 16383, 16384] {
            let data = vec![0x61; n];
            let mut w = c(&[]);
            w.write_bytes(&data, 1);
            assert_eq!(w.output.len(), n + length_size(n));
            let mut r = c(&w.output);
            r.read_bytes(1);
            clean(&r);
            assert_eq!(r.scalar, data);
        }
        let mut w = c(&[]);
        w.write_small(1, false);
        w.check_bytes(MAX_BYTES, 0);
        assert_eq!(kind(&w), "limit");
        assert_eq!(offset(&w), 1);
    }
    #[test]
    fn raw_malformed_input_sweep_never_panics() {
        let mut random = 0x123456789abcdefu64;
        for iteration in 0..10000 {
            let mut data = Vec::new();
            for _ in 0..iteration % 128 {
                random ^= random << 13;
                random ^= random >> 7;
                random ^= random << 17;
                data.push(random as u8);
            }
            for operation in 0..8 {
                let mut r = c(&data);
                match operation {
                    0 => r.read_bytes(1),
                    1 => r.read_bytes(2),
                    2 => r.read_bigint(false),
                    3 => r.read_bigint(true),
                    4 => {
                        r.read_length();
                    }
                    5 => {
                        r.read_float(64);
                    }
                    6 => {
                        r.read_char();
                    }
                    _ => {
                        r.read_words(64);
                    }
                }
                assert!(r.at <= data.len());
            }
        }
    }
    #[test]
    fn medium_integer_chunks_reconstruct_signed_and_unsigned_128bit_values() {
        let encode = |mut value: u128, signed: bool| {
            let mut data = Vec::new();
            loop {
                let byte = (value & 127) as u8;
                value = if signed {
                    ((value as i128) >> 7) as u128
                } else {
                    value >> 7
                };
                let done = if signed {
                    value == 0 && byte & 64 == 0 || value == u128::MAX && byte & 64 != 0
                } else {
                    value == 0
                };
                data.push(byte | if done { 0 } else { 128 });
                if done {
                    return data;
                }
            }
        };
        let mut random = 0x2545f4914f6cdd1du128;
        for iteration in 0..10000 {
            random ^= random << 23;
            random ^= random >> 17;
            random ^= random << 47;
            let value = match iteration {
                0 => 0,
                1 => u128::MAX,
                2 => 1 << 63,
                3 => 1 << 126,
                4 => 1 << 127,
                5 => (1u128 << 127) - 1,
                _ => random,
            };
            for signed in [false, true] {
                let data = encode(value, signed);
                let mut r = c(&data);
                r.read_bigint(signed);
                clean(&r);
                let top = (data.len() - 1) / 9;
                let high = unsafe { icwire_integer_chunk(ptr(&mut r), top, signed as usize) };
                let mut restored = if signed {
                    (high as i64 as i128) as u128
                } else {
                    high as u128
                };
                for index in (0..top).rev() {
                    restored =
                        restored.wrapping_shl(63).wrapping_add(unsafe {
                            icwire_integer_chunk(ptr(&mut r), index, signed as usize)
                        } as u128);
                }
                clean(&r);
                assert_eq!(restored, value);
                assert_eq!(r.scalar, data);
            }
        }
    }
    #[test]
    fn medium_integer_chunk_boundaries_and_large_fallback() {
        for length in 10usize..=27 {
            let top = (length - 1) / 9;
            let high_bit = ((length - 1) % 9) * 7;
            let mut positive = vec![0x80; length];
            *positive.last_mut().unwrap() = 1;
            for signed in [false, true] {
                let mut r = c(&positive);
                r.read_bigint(signed);
                clean(&r);
                for index in 0..=top {
                    assert_eq!(
                        r.integer_chunk(index, signed),
                        if index == top { 1 << high_bit } else { 0 }
                    );
                }
                clean(&r);
            }
            let mut negative = vec![0xff; length];
            *negative.last_mut().unwrap() = 0x7e;
            let mut r = c(&negative);
            r.read_bigint(true);
            clean(&r);
            for index in 0..=top {
                let expected = if index == top {
                    (-(1i64 << high_bit) - 1) as u64
                } else {
                    (1 << 63) - 1
                };
                assert_eq!(r.integer_chunk(index, true), expected);
            }
            clean(&r);
        }
        let mut data = vec![0x80; 28];
        *data.last_mut().unwrap() = 1;
        let mut r = c(&data);
        assert_eq!(unsafe { icwire_leaf_bigint(ptr(&mut r), 0) }, BIG_INTEGER);
        clean(&r);
        assert_eq!(r.scalar, data);
        assert_eq!(r.scalar.as_ptr(), r.input.as_ptr());
        r.integer_chunk(0, false);
        assert_eq!(kind(&r), "type");
        for index in [1, 3, usize::MAX] {
            let mut r = c(&[1]);
            r.read_bigint(false);
            r.integer_chunk(index, false);
            assert_eq!(kind(&r), "type");
        }
    }
    #[test]
    fn leaf_bytes_returns_borrowed_pointer_after_validation() {
        for kind_ in 0..=2 {
            for data in [b"".as_slice(), b"abc", "λ🌍".as_bytes()] {
                let mut w = c(&[]);
                w.write_bytes(data, kind_);
                let mut r = c(&w.output);
                let address = unsafe { icwire_leaf_bytes(ptr(&mut r), kind_) };
                clean(&r);
                assert_eq!(address, r.scalar.as_ptr() as usize);
                assert_ne!(address, 0);
                assert_eq!(r.scalar, data);
                assert_eq!(r.items, 1);
                assert_eq!(r.depth, 0);
            }
        }
        for (data, kind_) in [(&[][..], 0), (&[0x80, 0], 0), (&[1, 0x80], 1), (&[30], 2)] {
            let mut r = c(data);
            assert_eq!(unsafe { icwire_leaf_bytes(ptr(&mut r), kind_) }, 0);
            assert!(r.error.is_some());
        }
        let mut r = c(&[0]);
        r.items = MAX_ITEMS;
        assert_eq!(unsafe { icwire_leaf_bytes(ptr(&mut r), 0) }, 0);
        assert_eq!(kind(&r), "limit");
        assert_eq!(r.at, 0);
    }
    #[test]
    fn specialized_text_preserves_validation_offsets_and_node_budgets() {
        let mut inputs = vec![
            vec![],
            vec![0x80],
            vec![0x80, 0],
            vec![0xff, 0xff, 0xff, 0xff, 0x10],
            vec![1, 0x80],
            vec![3, 0xed, 0xa0, 0x80],
        ];
        for first in 0..=255u8 {
            inputs.push(vec![first]);
            let mut ascii = vec![first];
            ascii.extend_from_slice(&[b'x'; 127]);
            inputs.push(ascii);
        }
        for length in [0, 1, 127, 128, 255, 16384] {
            let mut w = c(&[]);
            w.write_bytes(&vec![b'a'; length], 1);
            inputs.push(w.output);
        }
        let mut unicode = c(&[]);
        unicode.write_bytes("λ🌍".as_bytes(), 1);
        inputs.push(unicode.output);
        for input in inputs {
            for depth in [0, MAX_DEPTH - 1, MAX_DEPTH] {
                for items in [0, MAX_ITEMS - 1, MAX_ITEMS] {
                    let mut old = c(&input);
                    old.depth = depth;
                    old.items = items;
                    let mut fast = c(&input);
                    fast.depth = depth;
                    fast.items = items;
                    let expected = unsafe { icwire_leaf_bytes(ptr(&mut old), 1) };
                    let actual = unsafe { icwire_leaf_text(ptr(&mut fast)) };
                    assert_eq!(actual == 0, expected == 0);
                    assert_eq!(
                        fast.error.as_ref().map(|e| (e.kind, e.offset)),
                        old.error.as_ref().map(|e| (e.kind, e.offset))
                    );
                    assert_eq!(
                        (fast.at, fast.items, fast.depth),
                        (old.at, old.items, old.depth)
                    );
                    assert_eq!(fast.scalar, old.scalar);
                    if fast.error.is_none() {
                        assert_eq!(actual, fast.scalar.as_ptr() as usize);
                        assert_ne!(actual, 0);
                    }
                }
            }
        }
    }
}
