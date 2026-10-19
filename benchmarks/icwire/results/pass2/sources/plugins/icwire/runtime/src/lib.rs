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

const HEADER: &[u8; 4] = b"ICW1";
const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_ITEMS: usize = 1_000_000;
const MAX_DEPTH: usize = 128;
const MAX_LEB_BYTES: usize = 4096;

#[derive(Debug)]
struct Error {
    kind: &'static str,
    offset: usize,
}
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
    small_integer: Option<u64>,
    records: Vec<Record>,
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
            limit: input.len(),
            output: Vec::new(),
            scalar: &[],
            small_integer: None,
            records: Vec::new(),
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
        if self.error.is_some() {
            return false;
        }
        if self.depth == MAX_DEPTH {
            self.fail("limit");
            return false;
        }
        if !self.charge() {
            return false;
        }
        self.depth += 1;
        true
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
        if self.room(bytes.len()) {
            self.output.extend_from_slice(bytes);
        }
    }
    #[inline]
    fn take(&mut self, len: usize) -> &'static [u8] {
        if self.error.is_some() {
            return &[];
        }
        if len > self.limit - self.at {
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
    fn write_word(&mut self, value: u64, bits: usize) {
        match bits {
            8 => self.append(&[value as u8]),
            16 => self.append(&(value as u16).to_le_bytes()),
            32 => self.append(&(value as u32).to_le_bytes()),
            64 => self.append(&value.to_le_bytes()),
            _ => self.fail("type"),
        }
    }
    fn check_bytes(&mut self, len: usize, kind: usize) -> bool {
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
        if len > MAX_BYTES - 4 {
            self.fail("limit");
            return false;
        }
        self.room(len + 4)
    }
    fn read_bytes(&mut self, kind: usize) {
        self.scalar = &[];
        let start = self.at;
        let n = self.read_word(false, 32) as usize;
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
    fn write_bytes(&mut self, data: &[u8], kind: usize) {
        if !self.check_bytes(data.len(), kind) {
            return;
        }
        if kind == 1 && core::str::from_utf8(data).is_err() {
            self.fail("utf8");
            return;
        }
        self.output
            .extend_from_slice(&(data.len() as u32).to_le_bytes());
        self.output.extend_from_slice(data);
    }
    fn read_bigint(&mut self, signed: bool) {
        self.scalar = &[];
        self.small_integer = None;
        if self.error.is_some() {
            return;
        }
        let start = self.at;
        let stop = self.limit.min(start + MAX_LEB_BYTES);
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
    fn write_bigint(&mut self, data: &[u8], signed: bool) {
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
    fn write_start(&mut self) -> usize {
        let mark = self.output.len();
        self.append(&[0; 4]);
        mark
    }
    fn write_end(&mut self, mark: usize) {
        if self.error.is_some() {
            return;
        }
        if mark > self.output.len() || self.output.len() - mark < 4 {
            self.fail("length");
            return;
        }
        let len = (self.output.len() - mark - 4) as u32;
        self.output[mark..mark + 4].copy_from_slice(&len.to_le_bytes());
    }
    fn record_start(&mut self) {
        let n = self.read_word(false, 32) as usize;
        if self.error.is_some() {
            return;
        }
        if n > self.limit - self.at {
            self.fail("truncated");
            return;
        }
        if self.records.len() == MAX_DEPTH {
            self.fail("limit");
            return;
        }
        let end = self.at + n;
        self.records.push(Record {
            end,
            parent_limit: self.limit,
            last_tag: None,
            field_end: None,
        });
        self.limit = end;
    }
    fn record_next(&mut self) -> bool {
        if self.error.is_some() {
            return false;
        }
        let Some(record) = self.records.last() else {
            self.fail("type");
            return false;
        };
        if record.field_end.is_some() {
            self.fail("length");
            return false;
        }
        if self.at == record.end {
            self.limit = self.records.pop().unwrap().parent_limit;
            return false;
        }
        let last_tag = record.last_tag;
        let start = self.at;
        let tag = self.read_word(false, 32) as u32;
        let n = self.read_word(false, 32) as usize;
        if self.error.is_some() {
            return false;
        }
        if last_tag.is_some_and(|last| tag <= last) {
            self.fail_at("canonical", start);
            return false;
        }
        if n > self.limit - self.at {
            self.fail("truncated");
            return false;
        }
        if !self.charge() {
            return false;
        }
        self.limit = self.at + n;
        let record = self.records.last_mut().unwrap();
        record.last_tag = Some(tag);
        record.field_end = Some(self.limit);
        true
    }
    fn field_end(&mut self, skip: bool) {
        if self.error.is_some() {
            return;
        }
        let Some(record) = self.records.last() else {
            self.fail("type");
            return;
        };
        let Some(end) = record.field_end else {
            self.fail("type");
            return;
        };
        if !skip && self.at != end {
            self.fail("length");
            return;
        }
        self.at = end;
        self.limit = record.end;
        self.records.last_mut().unwrap().field_end = None;
    }
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
    } else if !c.records.is_empty() {
        c.fail("length");
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
        1 => "missing",
        2 => "variant",
        3 => "canonical",
        _ => "type",
    });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_header(c: usize) {
    let c = unsafe { ctx(c) };
    let start = c.at;
    if c.take(4) != HEADER {
        c.fail_at("header", start);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_header(c: usize) {
    let c = unsafe { ctx(c) };
    c.writing = true;
    c.append(HEADER);
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
pub unsafe extern "C" fn icwire_scalar_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) };
    match part {
        0 => c.scalar.as_ptr() as usize,
        1 => c.scalar.len(),
        2 => c.small_integer.is_some() as usize,
        _ => c.small_integer.unwrap_or(0) as usize,
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_bool(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    let start = c.at;
    let data = c.take(1);
    let Some(&value) = data.first() else {
        return 0;
    };
    if value > 1 {
        c.fail_at("bool", start);
        return 0;
    }
    value as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_bool(c: usize, value: usize) {
    let c = unsafe { ctx(c) };
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
pub unsafe extern "C" fn icwire_write_word(c: usize, value: u64, bits: usize) {
    unsafe { ctx(c) }.write_word(value, bits);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_char(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    let start = c.at;
    let value = c.read_word(false, 32) as u32;
    if char::from_u32(value).is_none() {
        c.fail_at("char", start);
        return 0;
    }
    value as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_char(c: usize, value: usize) {
    let c = unsafe { ctx(c) };
    if value > u32::MAX as usize || char::from_u32(value as u32).is_none() {
        c.fail("char");
    } else {
        c.write_word(value as u64, 32);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_read_float(c: usize, bits: usize) -> f64 {
    let c = unsafe { ctx(c) };
    let start = c.at;
    let value = match bits {
        32 => f32::from_bits(c.read_word(false, 32) as u32) as f64,
        64 => f64::from_bits(c.read_word(false, 64)),
        _ => {
            c.fail("type");
            return 0.;
        }
    };
    if !value.is_finite() {
        c.fail_at("float", start);
        return 0.;
    }
    value
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_float(c: usize, value: f64, bits: usize) {
    let c = unsafe { ctx(c) };
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
    let n = c.read_word(false, 32) as usize;
    if c.collection(n) { n } else { 0 }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_array(c: usize, n: usize) {
    let c = unsafe { ctx(c) };
    if c.collection(n) {
        c.write_word(n as u64, 32);
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_start(c: usize) -> usize {
    unsafe { ctx(c) }.write_start()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_field(c: usize, tag: usize) -> usize {
    let c = unsafe { ctx(c) };
    if !c.charge() {
        return 0;
    }
    c.write_word(tag as u64, 32);
    c.write_start()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_write_end(c: usize, mark: usize) {
    unsafe { ctx(c) }.write_end(mark);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_record_start(c: usize) {
    unsafe { ctx(c) }.record_start();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_record_next(c: usize) -> usize {
    unsafe { ctx(c) }.record_next() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_field_tag(c: usize) -> usize {
    unsafe { ctx(c) }
        .records
        .last()
        .and_then(|r| r.last_tag)
        .unwrap_or(0) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_field_end(c: usize) {
    unsafe { ctx(c) }.field_end(false);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn icwire_field_skip(c: usize) {
    unsafe { ctx(c) }.field_end(true);
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
    fn record(fields: &[(u32, &[u8])]) -> Vec<u8> {
        let mut out = c(&[]);
        let mark = out.write_start();
        for &(tag, data) in fields {
            let field = unsafe { icwire_write_field(ptr(&mut out), tag as usize) };
            out.append(data);
            out.write_end(field);
        }
        out.write_end(mark);
        clean(&out);
        out.output
    }
    #[test]
    fn header_truncation_and_version_are_distinct() {
        for n in 0..4 {
            let mut r = c(&HEADER[..n]);
            unsafe {
                icwire_read_header(ptr(&mut r));
            }
            assert_eq!(kind(&r), "truncated");
            assert_eq!(offset(&r), 0);
        }
        let mut r = c(b"ICW2");
        unsafe {
            icwire_read_header(ptr(&mut r));
        }
        assert_eq!(kind(&r), "header");
        assert_eq!(offset(&r), 0);
        let mut w = c(&[]);
        unsafe {
            icwire_write_header(ptr(&mut w));
        }
        assert_eq!(w.output, HEADER);
        let mut r = c(&w.output);
        unsafe {
            icwire_read_header(ptr(&mut r));
            icwire_finish(ptr(&mut r));
        }
        clean(&r);
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
                assert_eq!(r.scalar.as_ptr(), unsafe { r.input.as_ptr().add(4) });
                for n in 0..w.output.len() {
                    let mut r = c(&w.output[..n]);
                    r.read_bytes(kind_);
                    assert_eq!(kind(&r), "truncated");
                }
            }
        }
        let mut r = c(&u32::MAX.to_le_bytes());
        r.read_bytes(0);
        assert_eq!(kind(&r), "limit");
        assert_eq!(offset(&r), 0);
        let mut w = c(&[]);
        w.write_bytes(&[0; 29], 2);
        clean(&w);
        let mut w = c(&[]);
        w.write_bytes(&[0; 30], 2);
        assert_eq!(kind(&w), "principal");
        let mut r = c(&30u32.to_le_bytes());
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
    fn small_integer_boundaries_and_ffi_parts() {
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
                assert_eq!(
                    unsafe { icwire_scalar_part(p, 2) },
                    (expected.len() <= 9) as usize
                );
                if expected.len() <= 9 {
                    assert_eq!(unsafe { icwire_scalar_part(p, 3) } as u64, word);
                }
                assert_eq!(unsafe { icwire_scalar_part(p, 1) }, expected.len());
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
    fn records_backpatch_and_skip_unknown_without_parsing() {
        let data = record(&[(0, &[1]), (1, &[0xff, 0x80, 0xff]), (u32::MAX, &[42, 0])]);
        let mut r = c(&data);
        r.record_start();
        assert!(r.record_next());
        assert_eq!(unsafe { icwire_field_tag(ptr(&mut r)) }, 0);
        assert_eq!(unsafe { icwire_read_bool(ptr(&mut r)) }, 1);
        r.field_end(false);
        assert!(r.record_next());
        assert_eq!(unsafe { icwire_field_tag(ptr(&mut r)) }, 1);
        r.field_end(true);
        assert!(r.record_next());
        assert_eq!(unsafe { icwire_field_tag(ptr(&mut r)) }, u32::MAX as usize);
        assert_eq!(r.read_word(false, 16), 42);
        r.field_end(false);
        assert!(!r.record_next());
        unsafe {
            icwire_finish(ptr(&mut r));
        }
        clean(&r);
        assert_eq!(r.items, 3);
    }
    #[test]
    fn records_reject_unsorted_duplicate_and_overlong_fields() {
        for fields in [
            [(1, &[][..]), (1, &[][..])],
            [(2, &[][..]), (1, &[][..])],
            [(u32::MAX, &[][..]), (0, &[][..])],
        ] {
            let data = record(&fields);
            let mut r = c(&data);
            r.record_start();
            assert!(r.record_next());
            r.field_end(true);
            assert!(!r.record_next());
            assert_eq!(kind(&r), "canonical");
            assert_eq!(offset(&r), 12);
        }
        let data = record(&[(0, &[1, 2])]);
        let mut r = c(&data);
        r.record_start();
        assert!(r.record_next());
        r.read_word(false, 8);
        r.field_end(false);
        assert_eq!(kind(&r), "length");
        let data = record(&[(0, &[1])]);
        let mut r = c(&data);
        r.record_start();
        assert!(r.record_next());
        r.read_word(false, 16);
        assert_eq!(kind(&r), "truncated");
        assert_eq!(r.at, 12);
    }
    #[test]
    fn nested_records_restore_each_parent_field_boundary() {
        let inner = record(&[(1, &[7]), (2, &[])]);
        let outer = record(&[(1, &inner), (2, &[9])]);
        let mut r = c(&outer);
        r.record_start();
        assert!(r.record_next());
        r.record_start();
        assert!(r.record_next());
        assert_eq!(r.read_word(false, 8), 7);
        r.field_end(false);
        assert!(r.record_next());
        r.field_end(false);
        assert!(!r.record_next());
        r.field_end(false);
        assert!(r.record_next());
        assert_eq!(r.read_word(false, 8), 9);
        r.field_end(false);
        assert!(!r.record_next());
        clean(&r);
        assert_eq!(r.at, outer.len());
        assert_eq!(r.limit, outer.len());
    }
    #[test]
    fn nested_record_cannot_consume_sibling_bytes() {
        let mut inner = record(&[(1, &[7])]);
        inner[0..4].copy_from_slice(&100u32.to_le_bytes());
        let outer = record(&[(1, &inner), (2, &[9; 100])]);
        let mut r = c(&outer);
        r.record_start();
        assert!(r.record_next());
        r.record_start();
        assert_eq!(kind(&r), "truncated");
    }
    #[test]
    fn every_record_truncation_is_rejected() {
        let data = record(&[(1, &[1]), (2, &[3; 47]), (3, &[])]);
        for n in 0..data.len() {
            let mut r = c(&data[..n]);
            r.record_start();
            while r.record_next() {
                r.field_end(true);
            }
            assert_eq!(kind(&r), "truncated");
        }
        for bytes in [&[1, 0, 0, 0, 0][..], &[7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]] {
            let mut r = c(bytes);
            r.record_start();
            r.record_next();
            assert_eq!(kind(&r), "truncated");
        }
        let mut data = record(&[(1, &[])]);
        data[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
        let mut r = c(&data);
        r.record_start();
        r.record_next();
        assert_eq!(kind(&r), "truncated");
    }
    #[test]
    fn limits_precede_allocation_and_charge_unknown_fields() {
        let mut r = c(&u32::MAX.to_le_bytes());
        assert_eq!(unsafe { icwire_read_array(ptr(&mut r)) }, 0);
        assert_eq!(kind(&r), "limit");
        let mut r = c(&[]);
        r.items = MAX_ITEMS - 1;
        assert!(r.collection(1));
        assert!(!r.collection(2));
        assert_eq!(kind(&r), "limit");
        let mut r = c(&[]);
        for _ in 0..MAX_DEPTH {
            assert!(r.enter());
        }
        assert!(!r.enter());
        assert_eq!(kind(&r), "limit");
        let mut r = c(&[]);
        for _ in 0..MAX_DEPTH {
            assert!(r.enter());
        }
        unsafe {
            icwire_leave(ptr(&mut r));
        }
        assert!(r.enter());
        clean(&r);
        let data = record(&[(0, &[])]);
        let mut r = c(&data);
        r.items = MAX_ITEMS;
        r.record_start();
        assert!(!r.record_next());
        assert_eq!(kind(&r), "limit");
        let mut w = c(&[]);
        w.items = MAX_ITEMS;
        unsafe {
            icwire_write_field(ptr(&mut w), 0);
        }
        assert_eq!(kind(&w), "limit");
        assert!(w.output.is_empty());
        let mut w = c(&[]);
        assert!(!w.check_bytes(usize::MAX, 0));
        assert_eq!(kind(&w), "limit");
        let mut w = c(&[]);
        assert!(!w.check_bytes(MAX_BYTES - 3, 0));
        assert_eq!(kind(&w), "limit");
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
        r.fail("missing");
        r.read_bigint(false);
        assert_eq!(kind(&r), "bool");
        assert_eq!(offset(&r), 0);
        assert!(r.scalar.is_empty());
    }
    #[test]
    fn trailing_bytes_and_generator_error_codes() {
        let mut r = c(b"ICW1x");
        unsafe {
            icwire_read_header(ptr(&mut r));
            icwire_finish(ptr(&mut r));
        }
        assert_eq!(kind(&r), "trailing");
        assert_eq!(offset(&r), 4);
        for (code, expected) in [
            (0, "type"),
            (1, "missing"),
            (2, "variant"),
            (3, "canonical"),
        ] {
            let mut r = c(&[]);
            unsafe {
                icwire_fail(ptr(&mut r), code);
            }
            assert_eq!(kind(&r), expected);
        }
    }
    #[test]
    fn deterministic_malformed_input_sweep_never_panics() {
        let mut seed = 0x123456789abcdefu64;
        for iteration in 0..10000 {
            let len = iteration % 128;
            let mut data = Vec::with_capacity(len);
            for _ in 0..len {
                seed ^= seed << 13;
                seed ^= seed >> 7;
                seed ^= seed << 17;
                data.push(seed as u8);
            }
            for operation in 0..8 {
                let mut r = c(&data);
                match operation {
                    0 => r.read_bytes(1),
                    1 => r.read_bytes(2),
                    2 => r.read_bigint(false),
                    3 => r.read_bigint(true),
                    4 => {
                        r.record_start();
                        while r.record_next() {
                            r.field_end(true);
                        }
                    }
                    5 => unsafe {
                        icwire_read_float(ptr(&mut r), 64);
                    },
                    6 => unsafe {
                        icwire_read_char(ptr(&mut r));
                    },
                    _ => unsafe {
                        icwire_read_array(ptr(&mut r));
                    },
                }
                assert!(r.at <= r.limit && r.limit <= data.len());
            }
        }
    }
}
