//! Bounded, canonical typed ICWire byte operations for specialized Motoko visitors.
//! The compiler owns schema traversal. Input slices are borrowed for one GC-free
//! call; records use boundary frames rather than reparsing or allocating keys.
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
    fn allocation_failed(_: Layout) -> ! { fail() }
    #[panic_handler]
    fn panic(_: &core::panic::PanicInfo<'_>) -> ! { fail() }
    fn fail() -> ! {
        let message = b"ICWire plugin: runtime allocation or invariant failure";
        unsafe { compute_plugin_trap(message.as_ptr(), message.len()) }
    }
}

const HEADER: &[u8; 4] = b"ICW1";
const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_ITEMS: usize = 1_000_000;
const MAX_DEPTH: usize = 128;
const MAX_LEB_BYTES: usize = 4096;

#[derive(Debug)]
struct Error { kind: &'static str, offset: usize }
struct Record {
    end: usize,
    parent_limit: usize,
    last_tag: Option<u32>,
    field_end: Option<usize>,
}
pub struct Context {
    input: &'static [u8],
    at: usize,
    limit: usize,
    output: Vec<u8>,
    scalar: &'static [u8],
    records: Vec<Record>,
    error: Option<Error>,
    depth: usize,
    items: usize,
    writing: bool,
}
impl Context {
    fn new(input: &'static [u8]) -> Self {
        Self {
            input, at: 0, limit: input.len(), output: Vec::new(), scalar: &[],
            records: Vec::new(), depth: 0, items: 0, writing: false,
            error: (input.len() > MAX_BYTES).then_some(Error { kind: "limit", offset: 0 }),
        }
    }
    #[inline]
    fn fail_at(&mut self, kind: &'static str, offset: usize) {
        if self.error.is_none() { self.error = Some(Error { kind, offset }); }
    }
    #[inline]
    fn fail(&mut self, kind: &'static str) {
        self.fail_at(kind, if self.writing { self.output.len() } else { self.at });
    }
    #[inline]
    fn charge(&mut self) -> bool {
        if self.error.is_some() { return false; }
        if self.items == MAX_ITEMS { self.fail("limit"); return false; }
        self.items += 1;
        true
    }
    fn enter(&mut self) -> bool {
        if self.error.is_some() { return false; }
        if self.depth == MAX_DEPTH { self.fail("limit"); return false; }
        if !self.charge() { return false; }
        self.depth += 1;
        true
    }
    fn collection(&mut self, n: usize) -> bool {
        if self.error.is_some() { return false; }
        if n > MAX_ITEMS - self.items { self.fail("limit"); return false; }
        true
    }
    #[inline]
    fn room(&mut self, n: usize) -> bool {
        if self.error.is_some() { return false; }
        if n > MAX_BYTES - self.output.len() { self.fail("limit"); return false; }
        true
    }
    #[inline]
    fn append(&mut self, bytes: &[u8]) {
        if self.room(bytes.len()) { self.output.extend_from_slice(bytes); }
    }
    #[inline]
    fn take(&mut self, len: usize) -> &'static [u8] {
        if self.error.is_some() { return &[]; }
        if len > self.limit - self.at { self.fail("truncated"); return &[]; }
        let start = self.at;
        self.at += len;
        &self.input[start..self.at]
    }
    fn read_word(&mut self, signed: bool, bits: usize) -> u64 {
        let n = match bits { 8 => 1, 16 => 2, 32 => 4, 64 => 8, _ => { self.fail("type"); return 0; } };
        let data = self.take(n);
        if data.len() != n { return 0; }
        let mut word = [0u8; 8];
        word[..n].copy_from_slice(data);
        let value = u64::from_le_bytes(word);
        if signed && bits < 64 { ((value << (64 - bits)) as i64 >> (64 - bits)) as u64 } else { value }
    }
    fn write_word(&mut self, value: u64, bits: usize) {
        let n = match bits { 8 => 1, 16 => 2, 32 => 4, 64 => 8, _ => { self.fail("type"); return; } };
        self.append(&value.to_le_bytes()[..n]);
    }
    fn check_bytes(&mut self, len: usize, kind: usize) -> bool {
        if self.error.is_some() { return false; }
        if kind > 2 { self.fail("type"); return false; }
        if kind == 2 && len > 29 { self.fail("principal"); return false; }
        if len > MAX_BYTES - 4 { self.fail("limit"); return false; }
        self.room(len + 4)
    }
    fn read_bytes(&mut self, kind: usize) {
        self.scalar = &[];
        let start = self.at;
        let n = self.read_word(false, 32) as usize;
        if self.error.is_some() { return; }
        if kind > 2 { self.fail_at("type", start); return; }
        if kind == 2 && n > 29 { self.fail_at("principal", start); return; }
        let data = self.take(n);
        if self.error.is_some() { return; }
        if kind == 1 && core::str::from_utf8(data).is_err() {
            self.fail_at("utf8", start); return;
        }
        self.scalar = data;
    }
    fn write_bytes(&mut self, data: &[u8], kind: usize) {
        if !self.check_bytes(data.len(), kind) { return; }
        if kind == 1 && core::str::from_utf8(data).is_err() { self.fail("utf8"); return; }
        self.output.extend_from_slice(&(data.len() as u32).to_le_bytes());
        self.output.extend_from_slice(data);
    }
    fn read_bigint(&mut self, signed: bool) {
        self.scalar = &[];
        if self.error.is_some() { return; }
        let start = self.at;
        let stop = self.limit.min(start + MAX_LEB_BYTES);
        while self.at < stop {
            let b = self.input[self.at];
            self.at += 1;
            if b & 128 == 0 {
                let data = &self.input[start..self.at];
                if !minimal_leb(data, signed) { self.fail_at("canonical", start); }
                else { self.scalar = data; }
                return;
            }
        }
        self.fail_at(if self.at - start == MAX_LEB_BYTES { "limit" } else { "truncated" }, start);
    }
    fn write_bigint(&mut self, data: &[u8], signed: bool) {
        if self.error.is_some() { return; }
        if data.len() > MAX_LEB_BYTES { self.fail("limit"); return; }
        if data.is_empty() || data.last().unwrap() & 128 != 0
            || data[..data.len() - 1].iter().any(|b| b & 128 == 0)
            || !minimal_leb(data, signed)
        { self.fail("canonical"); return; }
        self.append(data);
    }
    fn write_start(&mut self) -> usize {
        let mark = self.output.len();
        self.append(&[0; 4]);
        mark
    }
    fn write_end(&mut self, mark: usize) {
        if self.error.is_some() { return; }
        if mark > self.output.len() || self.output.len() - mark < 4 { self.fail("length"); return; }
        let len = (self.output.len() - mark - 4) as u32;
        self.output[mark..mark + 4].copy_from_slice(&len.to_le_bytes());
    }
    fn record_start(&mut self) {
        let n = self.read_word(false, 32) as usize;
        if self.error.is_some() { return; }
        if n > self.limit - self.at { self.fail("truncated"); return; }
        if self.records.len() == MAX_DEPTH { self.fail("limit"); return; }
        let end = self.at + n;
        self.records.push(Record { end, parent_limit: self.limit, last_tag: None, field_end: None });
        self.limit = end;
    }
    fn record_next(&mut self) -> bool {
        if self.error.is_some() { return false; }
        let Some(record) = self.records.last() else { self.fail("type"); return false; };
        if record.field_end.is_some() { self.fail("length"); return false; }
        if self.at == record.end {
            self.limit = self.records.pop().unwrap().parent_limit;
            return false;
        }
        let last_tag = record.last_tag;
        let start = self.at;
        let tag = self.read_word(false, 32) as u32;
        let n = self.read_word(false, 32) as usize;
        if self.error.is_some() { return false; }
        if last_tag.is_some_and(|last| tag <= last) { self.fail_at("canonical", start); return false; }
        if n > self.limit - self.at { self.fail("truncated"); return false; }
        if !self.charge() { return false; }
        self.limit = self.at + n;
        let record = self.records.last_mut().unwrap();
        record.last_tag = Some(tag);
        record.field_end = Some(self.limit);
        true
    }
    fn field_end(&mut self, skip: bool) {
        if self.error.is_some() { return; }
        let Some(record) = self.records.last() else { self.fail("type"); return; };
        let Some(end) = record.field_end else { self.fail("type"); return; };
        if !skip && self.at != end { self.fail("length"); return; }
        self.at = end;
        self.limit = record.end;
        self.records.last_mut().unwrap().field_end = None;
    }
}
#[inline]
fn minimal_leb(data: &[u8], signed: bool) -> bool {
    if data.len() < 2 { return !data.is_empty(); }
    let last = data[data.len() - 1];
    if signed {
        let previous = data[data.len() - 2];
        !(last == 0 && previous & 64 == 0 || last == 127 && previous & 64 != 0)
    } else { last != 0 }
}
unsafe fn ctx<'a>(ptr: usize) -> &'a mut Context { unsafe { &mut *(ptr as *mut Context) } }
unsafe fn bytes<'a>(ptr: usize, len: usize) -> &'a [u8] {
    if len == 0 { &[] } else { unsafe { core::slice::from_raw_parts(ptr as *const u8, len) } }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_new(ptr: usize, len: usize) -> usize {
    Box::into_raw(Box::new(Context::new(unsafe { bytes(ptr, len) }))) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_done(c: usize) { unsafe { drop(Box::from_raw(c as *mut Context)); } }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_ok(c: usize) -> usize { unsafe { ctx(c) }.error.is_none() as usize }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_enter(c: usize) -> usize { unsafe { ctx(c) }.enter() as usize }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_leave(c: usize) { let c = unsafe { ctx(c) }; c.depth = c.depth.saturating_sub(1); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_collection(c: usize, n: usize) -> usize { unsafe { ctx(c) }.collection(n) as usize }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_check_bytes(c: usize, len: usize, kind: usize) -> usize { unsafe { ctx(c) }.check_bytes(len, kind) as usize }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_check_bigint(c: usize, len: usize) -> usize {
    let c = unsafe { ctx(c) };
    if len > MAX_LEB_BYTES { c.fail("limit"); }
    c.error.is_none() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_finish(c: usize) {
    let c = unsafe { ctx(c) };
    if c.at != c.input.len() { c.fail("trailing"); }
    else if !c.records.is_empty() { c.fail("length"); }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_error_part(c: usize, part: usize) -> usize {
    let Some(e) = &unsafe { ctx(c) }.error else { return 0; };
    match part { 0 => e.kind.as_ptr() as usize, 1 => e.kind.len(), _ => e.offset }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_fail(c: usize, code: usize) {
    unsafe { ctx(c) }.fail(match code { 1 => "missing", 2 => "variant", 3 => "canonical", _ => "type" });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_header(c: usize) {
    let c = unsafe { ctx(c) };
    let start = c.at;
    if c.take(4) != HEADER { c.fail_at("header", start); }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_header(c: usize) { let c = unsafe { ctx(c) }; c.writing = true; c.append(HEADER); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_output_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) }; if part == 0 { c.output.as_ptr() as usize } else { c.output.len() }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_scalar_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) }; if part == 0 { c.scalar.as_ptr() as usize } else { c.scalar.len() }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_bool(c: usize) -> usize {
    let c = unsafe { ctx(c) }; let start = c.at;
    let data = c.take(1); let Some(&value) = data.first() else { return 0; };
    if value > 1 { c.fail_at("bool", start); return 0; } value as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_bool(c: usize, value: usize) {
    let c = unsafe { ctx(c) }; if value > 1 { c.fail("bool"); } else { c.append(&[value as u8]); }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_word(c: usize, signed: usize, bits: usize) -> u64 { unsafe { ctx(c) }.read_word(signed != 0, bits) }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_word(c: usize, value: u64, bits: usize) { unsafe { ctx(c) }.write_word(value, bits); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_char(c: usize) -> usize {
    let c = unsafe { ctx(c) }; let start = c.at; let value = c.read_word(false, 32) as u32;
    if char::from_u32(value).is_none() { c.fail_at("char", start); return 0; } value as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_char(c: usize, value: usize) {
    let c = unsafe { ctx(c) }; if value > u32::MAX as usize || char::from_u32(value as u32).is_none() { c.fail("char"); }
    else { c.write_word(value as u64, 32); }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_float(c: usize, bits: usize) -> f64 {
    let c = unsafe { ctx(c) }; let start = c.at;
    let value = match bits { 32 => f32::from_bits(c.read_word(false, 32) as u32) as f64, 64 => f64::from_bits(c.read_word(false, 64)), _ => { c.fail("type"); return 0.; } };
    if !value.is_finite() { c.fail_at("float", start); return 0.; } value
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_float(c: usize, value: f64, bits: usize) {
    let c = unsafe { ctx(c) };
    if !value.is_finite() { c.fail("float"); return; }
    match bits {
        32 => { let value = value as f32; if !value.is_finite() { c.fail("float"); } else { c.write_word(value.to_bits() as u64, 32); } },
        64 => c.write_word(value.to_bits(), 64), _ => c.fail("type"),
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_bytes(c: usize, kind: usize) { unsafe { ctx(c) }.read_bytes(kind); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_bytes(c: usize, ptr: usize, len: usize, kind: usize) {
    let c = unsafe { ctx(c) }; if c.check_bytes(len, kind) { c.write_bytes(unsafe { bytes(ptr, len) }, kind); }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_bigint(c: usize, signed: usize) { unsafe { ctx(c) }.read_bigint(signed != 0); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_bigint(c: usize, ptr: usize, len: usize, signed: usize) {
    let c = unsafe { ctx(c) }; if len > MAX_LEB_BYTES { c.fail("limit"); } else if c.error.is_none() { c.write_bigint(unsafe { bytes(ptr, len) }, signed != 0); }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_array(c: usize) -> usize {
    let c = unsafe { ctx(c) }; let n = c.read_word(false, 32) as usize;
    if c.collection(n) { n } else { 0 }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_array(c: usize, n: usize) { let c = unsafe { ctx(c) }; if c.collection(n) { c.write_word(n as u64, 32); } }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_start(c: usize) -> usize { unsafe { ctx(c) }.write_start() }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_field(c: usize, tag: usize) -> usize {
    let c = unsafe { ctx(c) }; if !c.charge() { return 0; } c.write_word(tag as u64, 32); c.write_start()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_end(c: usize, mark: usize) { unsafe { ctx(c) }.write_end(mark); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_record_start(c: usize) { unsafe { ctx(c) }.record_start(); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_record_next(c: usize) -> usize { unsafe { ctx(c) }.record_next() as usize }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_field_tag(c: usize) -> usize { unsafe { ctx(c) }.records.last().and_then(|r| r.last_tag).unwrap_or(0) as usize }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_field_end(c: usize) { unsafe { ctx(c) }.field_end(false); }
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_field_skip(c: usize) { unsafe { ctx(c) }.field_end(true); }
