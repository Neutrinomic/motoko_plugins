//! Streaming JSON reader/writer for compiler-specialized Motoko visitors.
//! Values never pass through Candid or a generic JSON value tree. All pointers
//! are borrowed only during one synchronous call, without GC safepoints.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(alloc_error_handler))]

extern crate alloc;

use alloc::{
    boxed::Box,
    collections::BTreeSet,
    format,
    string::{String, ToString},
    vec,
    vec::Vec,
};
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
        let message = b"JSON plugin: runtime allocation or invariant failure";
        unsafe { compute_plugin_trap(message.as_ptr(), message.len()) }
    }
}

const MAX_BYTES: usize = 16 * 1024 * 1024;
const MAX_ITEMS: usize = 1_000_000;
const MAX_DEPTH: usize = 128;
const MAX_INTEGER_DIGITS: usize = 4096;

struct Error {
    kind: &'static str,
    message: &'static str,
    offset: usize,
    path: String,
}
struct ObjectFrame {
    first: bool,
    keys: BTreeSet<Vec<u8>>,
}
pub struct Context {
    input: &'static [u8],
    at: usize,
    output: Vec<u8>,
    scalar: Vec<u8>,
    key: Vec<u8>,
    objects: Vec<ObjectFrame>,
    path: String,
    path_lengths: Vec<usize>,
    error: Option<Error>,
    depth: usize,
    items: usize,
}

impl Context {
    fn new(input: &'static [u8]) -> Self {
        let mut c = Self {
            input,
            at: 0,
            output: Vec::new(),
            scalar: Vec::new(),
            key: Vec::new(),
            objects: Vec::new(),
            path: String::new(),
            path_lengths: Vec::new(),
            error: None,
            depth: 0,
            items: 0,
        };
        if input.len() > MAX_BYTES {
            c.fail("limit", "JSON byte limit exceeded");
        }
        c
    }
    fn fail(&mut self, kind: &'static str, message: &'static str) {
        if self.error.is_none() {
            self.error = Some(Error {
                kind,
                message,
                offset: self.at,
                path: self.path.clone(),
            });
        }
    }
    fn ws(&mut self) {
        while matches!(self.input.get(self.at), Some(b' ' | b'\n' | b'\r' | b'\t')) {
            self.at += 1;
        }
    }
    fn peek(&mut self) -> u8 {
        self.ws();
        self.input.get(self.at).copied().unwrap_or(0)
    }
    fn expect(&mut self, byte: u8) -> bool {
        if self.error.is_some() {
            return false;
        }
        if self.peek() == byte {
            self.at += 1;
            true
        } else {
            self.fail("syntax", "Unexpected JSON token");
            false
        }
    }
    fn enter(&mut self) -> bool {
        if self.error.is_some() {
            return false;
        }
        self.depth += 1;
        self.items += 1;
        if self.depth > MAX_DEPTH || self.items > MAX_ITEMS {
            self.fail("limit", "JSON nesting or item limit exceeded");
            self.depth -= 1;
            false
        } else {
            true
        }
    }
    fn append(&mut self, bytes: &[u8]) {
        if self.error.is_some() {
            return;
        }
        if bytes.len() > MAX_BYTES.saturating_sub(self.output.len()) {
            self.fail("limit", "JSON byte limit exceeded");
            return;
        }
        self.output.extend_from_slice(bytes);
    }
    fn check_string(&mut self, len: usize) -> bool {
        if self.error.is_some() {
            return false;
        }
        if !len
            .checked_add(2)
            .is_some_and(|size| size <= MAX_BYTES.saturating_sub(self.output.len()))
        {
            self.fail("limit", "JSON byte limit exceeded");
            return false;
        }
        true
    }
    fn collection(&mut self, len: usize) -> bool {
        if self.error.is_some() {
            return false;
        }
        if len > MAX_ITEMS.saturating_sub(self.items) {
            self.fail("limit", "JSON nesting or item limit exceeded");
            return false;
        }
        true
    }
    fn string(&mut self) -> Vec<u8> {
        if self.error.is_some() {
            return Vec::new();
        }
        if self.peek() != b'"' {
            self.fail("type", "Expected a JSON string");
            return Vec::new();
        }
        self.at += 1;
        let mut start = self.at;
        let mut result = Vec::new();
        loop {
            let Some(&byte) = self.input.get(self.at) else {
                self.fail("syntax", "Unterminated JSON string");
                return Vec::new();
            };
            match byte {
                b'"' => {
                    result.extend_from_slice(&self.input[start..self.at]);
                    self.at += 1;
                    if core::str::from_utf8(&result).is_err() {
                        self.fail("syntax", "Invalid UTF-8 string");
                    }
                    return result;
                }
                b'\\' => {
                    result.extend_from_slice(&self.input[start..self.at]);
                    self.at += 1;
                    let Some(&escaped) = self.input.get(self.at) else {
                        self.fail("syntax", "Incomplete JSON escape");
                        return Vec::new();
                    };
                    self.at += 1;
                    match escaped {
                        b'"' | b'\\' | b'/' => result.push(escaped),
                        b'b' => result.push(8),
                        b'f' => result.push(12),
                        b'n' => result.push(10),
                        b'r' => result.push(13),
                        b't' => result.push(9),
                        b'u' => {
                            let high = self.hex4();
                            let cp = if (0xd800..=0xdbff).contains(&high) {
                                if self.input.get(self.at..self.at + 2) != Some(b"\\u") {
                                    self.fail("syntax", "Unpaired Unicode surrogate");
                                    return Vec::new();
                                }
                                self.at += 2;
                                let low = self.hex4();
                                if !(0xdc00..=0xdfff).contains(&low) {
                                    self.fail("syntax", "Unpaired Unicode surrogate");
                                    return Vec::new();
                                }
                                0x10000 + ((high - 0xd800) << 10) + low - 0xdc00
                            } else {
                                high
                            };
                            match char::from_u32(cp) {
                                Some(ch) => {
                                    result.extend_from_slice(ch.encode_utf8(&mut [0; 4]).as_bytes())
                                }
                                None => {
                                    self.fail("syntax", "Unpaired Unicode surrogate");
                                    return Vec::new();
                                }
                            }
                        }
                        _ => {
                            self.fail("syntax", "Invalid JSON escape");
                            return Vec::new();
                        }
                    }
                    if self.error.is_some() {
                        return Vec::new();
                    }
                    start = self.at;
                }
                0..=31 => {
                    self.fail("syntax", "Unescaped control character");
                    return Vec::new();
                }
                _ => self.at += 1,
            }
        }
    }
    // Array counting and ignored values validate strings without materializing
    // their decoded bytes. Wasm scratch allocations live until the next GC, so
    // copying a large scalar on every nested pre-scan would multiply memory use.
    fn skip_string(&mut self) {
        if self.error.is_some() {
            return;
        }
        if self.peek() != b'"' {
            self.fail("type", "Expected a JSON string");
            return;
        }
        self.at += 1;
        let mut start = self.at;
        let mut invalid_utf8 = false;
        loop {
            let Some(&byte) = self.input.get(self.at) else {
                self.fail("syntax", "Unterminated JSON string");
                return;
            };
            match byte {
                b'"' => {
                    invalid_utf8 |= core::str::from_utf8(&self.input[start..self.at]).is_err();
                    self.at += 1;
                    // Match string(): report UTF-8 errors after the closing
                    // quote, so a later malformed escape still takes priority.
                    if invalid_utf8 {
                        self.fail("syntax", "Invalid UTF-8 string");
                    }
                    return;
                }
                b'\\' => {
                    invalid_utf8 |= core::str::from_utf8(&self.input[start..self.at]).is_err();
                    self.at += 1;
                    let Some(&escaped) = self.input.get(self.at) else {
                        self.fail("syntax", "Incomplete JSON escape");
                        return;
                    };
                    self.at += 1;
                    match escaped {
                        b'"' | b'\\' | b'/' | b'b' | b'f' | b'n' | b'r' | b't' => {}
                        b'u' => {
                            let high = self.hex4();
                            let cp = if (0xd800..=0xdbff).contains(&high) {
                                if self.input.get(self.at..self.at + 2) != Some(b"\\u") {
                                    self.fail("syntax", "Unpaired Unicode surrogate");
                                    return;
                                }
                                self.at += 2;
                                let low = self.hex4();
                                if !(0xdc00..=0xdfff).contains(&low) {
                                    self.fail("syntax", "Unpaired Unicode surrogate");
                                    return;
                                }
                                0x10000 + ((high - 0xd800) << 10) + low - 0xdc00
                            } else {
                                high
                            };
                            if char::from_u32(cp).is_none() {
                                self.fail("syntax", "Unpaired Unicode surrogate");
                                return;
                            }
                        }
                        _ => {
                            self.fail("syntax", "Invalid JSON escape");
                            return;
                        }
                    }
                    if self.error.is_some() {
                        return;
                    }
                    start = self.at;
                }
                0..=31 => {
                    self.fail("syntax", "Unescaped control character");
                    return;
                }
                _ => self.at += 1,
            }
        }
    }
    fn hex4(&mut self) -> u32 {
        let mut n = 0;
        for _ in 0..4 {
            let digit = match self.input.get(self.at) {
                Some(b'0'..=b'9') => self.input[self.at] - b'0',
                Some(b'a'..=b'f') => self.input[self.at] - b'a' + 10,
                Some(b'A'..=b'F') => self.input[self.at] - b'A' + 10,
                _ => {
                    self.fail("syntax", "Invalid Unicode escape");
                    return 0;
                }
            };
            n = n * 16 + u32::from(digit);
            self.at += 1;
        }
        n
    }
    fn literal(&mut self, value: &[u8]) {
        if self.error.is_some() {
            return;
        }
        self.ws();
        if self.input.get(self.at..self.at + value.len()) == Some(value) {
            self.at += value.len();
        } else {
            self.fail("type", "Unexpected JSON literal");
        }
    }
    fn number(&mut self) -> Vec<u8> {
        if self.error.is_some() {
            return Vec::new();
        }
        self.ws();
        let start = self.at;
        if self.input.get(self.at) == Some(&b'-') {
            self.at += 1;
        }
        match self.input.get(self.at) {
            Some(b'0') => self.at += 1,
            Some(b'1'..=b'9') => {
                self.at += 1;
                while matches!(self.input.get(self.at), Some(b'0'..=b'9')) {
                    self.at += 1;
                }
            }
            _ => {
                self.fail("type", "Expected a JSON number");
                return Vec::new();
            }
        }
        if self.input.get(self.at) == Some(&b'.') {
            self.at += 1;
            let digits = self.at;
            while matches!(self.input.get(self.at), Some(b'0'..=b'9')) {
                self.at += 1;
            }
            if self.at == digits {
                self.fail("syntax", "Invalid JSON number");
            }
        }
        if matches!(self.input.get(self.at), Some(b'e' | b'E')) {
            self.at += 1;
            if matches!(self.input.get(self.at), Some(b'+' | b'-')) {
                self.at += 1;
            }
            let digits = self.at;
            while matches!(self.input.get(self.at), Some(b'0'..=b'9')) {
                self.at += 1;
            }
            if self.at == digits {
                self.fail("syntax", "Invalid JSON number");
            }
        }
        self.input[start..self.at].to_vec()
    }
    // The same lexical validation as number(), without copying the token.
    fn skip_number(&mut self) {
        if self.error.is_some() {
            return;
        }
        self.ws();
        if self.input.get(self.at) == Some(&b'-') {
            self.at += 1;
        }
        match self.input.get(self.at) {
            Some(b'0') => self.at += 1,
            Some(b'1'..=b'9') => {
                self.at += 1;
                while matches!(self.input.get(self.at), Some(b'0'..=b'9')) {
                    self.at += 1;
                }
            }
            _ => {
                self.fail("type", "Expected a JSON number");
                return;
            }
        }
        if self.input.get(self.at) == Some(&b'.') {
            self.at += 1;
            let digits = self.at;
            while matches!(self.input.get(self.at), Some(b'0'..=b'9')) {
                self.at += 1;
            }
            if self.at == digits {
                self.fail("syntax", "Invalid JSON number");
            }
        }
        if matches!(self.input.get(self.at), Some(b'e' | b'E')) {
            self.at += 1;
            if matches!(self.input.get(self.at), Some(b'+' | b'-')) {
                self.at += 1;
            }
            let digits = self.at;
            while matches!(self.input.get(self.at), Some(b'0'..=b'9')) {
                self.at += 1;
            }
            if self.at == digits {
                self.fail("syntax", "Invalid JSON number");
            }
        }
    }
    fn integer(&mut self, signed: bool, quoted: bool) -> Vec<u8> {
        let value = if quoted && self.peek() == b'"' {
            self.string()
        } else {
            self.number()
        };
        if self.error.is_some() {
            return Vec::new();
        }
        let digits = if value.first() == Some(&b'-') && signed {
            &value[1..]
        } else {
            &value[..]
        };
        if digits.is_empty()
            || !digits.iter().all(u8::is_ascii_digit)
            || (digits.len() > 1 && digits[0] == b'0')
        {
            self.fail("range", "Expected an exact decimal integer");
            return Vec::new();
        }
        if digits.len() > MAX_INTEGER_DIGITS {
            self.fail("limit", "JSON integer digit limit exceeded");
            return Vec::new();
        }
        value
    }
    fn object_start(&mut self) {
        if self.peek() != b'{' {
            self.fail("type", "Expected a JSON object");
            return;
        }
        self.at += 1;
        self.objects.push(ObjectFrame {
            first: true,
            keys: BTreeSet::new(),
        });
    }
    fn object_next(&mut self) -> bool {
        if self.error.is_some() {
            return false;
        }
        if self.peek() == b'}' {
            self.at += 1;
            self.objects.pop();
            return false;
        }
        let first = match self.objects.last() {
            Some(frame) => frame.first,
            None => return false,
        };
        if !first && !self.expect(b',') {
            return false;
        }
        let key = self.string();
        if self.error.is_some() {
            return false;
        }
        let frame = self.objects.last_mut().expect("object frame");
        frame.first = false;
        if !frame.keys.insert(key.clone()) {
            self.fail("duplicate", "Duplicate JSON object key");
            return false;
        }
        if !self.expect(b':') {
            return false;
        }
        self.key = key;
        true
    }
    fn skip(&mut self) {
        if !self.enter() {
            return;
        }
        match self.peek() {
            b'"' => {
                self.skip_string();
            }
            b'{' => {
                self.object_start();
                while self.object_next() {
                    self.push_key();
                    self.skip();
                    self.pop_path();
                }
            }
            b'[' => {
                self.at += 1;
                let mut index = 0;
                if self.peek() != b']' {
                    loop {
                        self.push_index(index);
                        self.skip();
                        self.pop_path();
                        if self.error.is_some() || self.peek() == b']' {
                            break;
                        }
                        if !self.expect(b',') {
                            break;
                        }
                        index += 1;
                    }
                }
                self.expect(b']');
            }
            b'n' => self.literal(b"null"),
            b't' => self.literal(b"true"),
            b'f' => self.literal(b"false"),
            _ => {
                self.skip_number();
            }
        }
        self.depth -= 1;
    }
    fn array_start(&mut self) -> usize {
        if self.error.is_some() {
            return 0;
        }
        if self.peek() != b'[' {
            self.fail("type", "Expected a JSON array");
            return 0;
        }
        self.at += 1;
        let start = self.at;
        // Count without a value tree or temporary Motoko element array. Restore
        // accounting after the pre-scan; the typed visitor charges each value.
        let items = self.items;
        let mut count = 0;
        if self.peek() != b']' {
            loop {
                self.push_index(count);
                self.skip();
                self.pop_path();
                count += 1;
                if self.error.is_some() || self.peek() == b']' {
                    break;
                }
                if !self.expect(b',') {
                    break;
                }
            }
        }
        if self.error.is_some() {
            return 0;
        }
        self.at = start;
        self.items = items;
        count
    }
    fn push_key(&mut self) {
        self.path_lengths.push(self.path.len());
        self.path.push('/');
        for ch in core::str::from_utf8(&self.key)
            .expect("validated key")
            .chars()
        {
            match ch {
                '~' => self.path.push_str("~0"),
                '/' => self.path.push_str("~1"),
                _ => self.path.push(ch),
            }
        }
    }
    fn push_index(&mut self, index: usize) {
        self.path_lengths.push(self.path.len());
        // Write into the reused path buffer: one temporary String per array
        // element otherwise becomes garbage in the ephemeral allocator.
        write!(&mut self.path, "/{index}").expect("writing to String");
    }
    fn pop_path(&mut self) {
        if let Some(len) = self.path_lengths.pop() {
            self.path.truncate(len);
        }
    }
    fn write_string(&mut self, bytes: &[u8]) {
        if !self.check_string(bytes.len()) {
            return;
        }
        self.append(b"\"");
        let mut start = 0;
        for (i, &byte) in bytes.iter().enumerate() {
            let escape: &[u8] = match byte {
                b'"' => b"\\\"",
                b'\\' => b"\\\\",
                b'\n' => b"\\n",
                b'\r' => b"\\r",
                b'\t' => b"\\t",
                _ if byte < 32 => b"",
                _ => continue,
            };
            self.append(&bytes[start..i]);
            if escape.is_empty() {
                const HEX: &[u8] = b"0123456789abcdef";
                self.append(&[
                    b'\\',
                    b'u',
                    b'0',
                    b'0',
                    HEX[(byte >> 4) as usize],
                    HEX[(byte & 15) as usize],
                ]);
            } else {
                self.append(escape);
            }
            if self.error.is_some() {
                return;
            }
            start = i + 1;
        }
        self.append(&bytes[start..]);
        self.append(b"\"");
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
pub unsafe extern "C" fn json_new(ptr: usize, len: usize) -> usize {
    Box::into_raw(Box::new(Context::new(unsafe { bytes(ptr, len) }))) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_done(c: usize) {
    unsafe {
        drop(Box::from_raw(c as *mut Context));
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_ok(c: usize) -> usize {
    unsafe { ctx(c) }.error.is_none() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_enter(c: usize) -> usize {
    unsafe { ctx(c) }.enter() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_collection(c: usize, len: usize) -> usize {
    unsafe { ctx(c) }.collection(len) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_check_string(c: usize, len: usize) -> usize {
    unsafe { ctx(c) }.check_string(len) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_check_bigint(c: usize, len: usize) -> usize {
    let c = unsafe { ctx(c) };
    if c.error.is_some() {
        return 0;
    }
    if len > MAX_INTEGER_DIGITS / 2 {
        c.fail("limit", "JSON integer digit limit exceeded");
        return 0;
    }
    1
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_leave(c: usize) {
    let c = unsafe { ctx(c) };
    c.depth = c.depth.saturating_sub(1);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_finish(c: usize) {
    let c = unsafe { ctx(c) };
    c.ws();
    if c.at != c.input.len() {
        c.fail("syntax", "Trailing JSON input");
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_error_part(c: usize, part: usize) -> usize {
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
pub unsafe extern "C" fn json_fail(c: usize, code: usize) {
    let c = unsafe { ctx(c) };
    match code {
        1 => c.fail("missing", "Missing required JSON field"),
        2 => c.fail("type", "Unexpected JSON variant case"),
        3 => c.fail("type", "Expected exactly one object field"),
        4 => c.fail("type", "Unexpected JSON tuple length"),
        _ => c.fail("type", "Unexpected JSON value"),
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_peek(c: usize) -> usize {
    unsafe { ctx(c) }.peek() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_expect(c: usize, byte: usize) {
    unsafe { ctx(c) }.expect(byte as u8);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_read_null(c: usize) {
    unsafe { ctx(c) }.literal(b"null");
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_read_bool(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    if c.peek() == b't' {
        c.literal(b"true");
        1
    } else {
        c.literal(b"false");
        0
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_read_string(c: usize) {
    let c = unsafe { ctx(c) };
    c.scalar = c.string();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_scalar_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) };
    if part == 0 {
        c.scalar.as_ptr() as usize
    } else {
        c.scalar.len()
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_output_part(c: usize, part: usize) -> usize {
    let c = unsafe { ctx(c) };
    if part == 0 {
        c.output.as_ptr() as usize
    } else {
        c.output.len()
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_object_start(c: usize) {
    unsafe { ctx(c) }.object_start();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_object_next(c: usize) -> usize {
    unsafe { ctx(c) }.object_next() as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_key_eq(c: usize, ptr: usize, len: usize) -> usize {
    (unsafe { ctx(c) }.key == unsafe { bytes(ptr, len) }) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_path_key(c: usize) {
    unsafe { ctx(c) }.push_key();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_path_field(c: usize, ptr: usize, len: usize) {
    let c = unsafe { ctx(c) };
    c.key.clear();
    c.key.extend_from_slice(unsafe { bytes(ptr, len) });
    c.push_key();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_path_index(c: usize, index: usize) {
    unsafe { ctx(c) }.push_index(index);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_path_pop(c: usize) {
    unsafe { ctx(c) }.pop_path();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_array_start(c: usize) -> usize {
    unsafe { ctx(c) }.array_start()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_skip(c: usize) {
    unsafe { ctx(c) }.skip();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_raw(c: usize, ptr: usize, len: usize) {
    unsafe { ctx(c) }.append(unsafe { bytes(ptr, len) });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_byte(c: usize, value: usize) {
    unsafe { ctx(c) }.append(&[value as u8]);
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_string(c: usize, ptr: usize, len: usize) {
    unsafe { ctx(c) }.write_string(unsafe { bytes(ptr, len) });
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_read_word(c: usize, signed: usize, bits: usize) -> u64 {
    let c = unsafe { ctx(c) };
    let text = c.integer(signed != 0, bits == 64);
    let Ok(text) = core::str::from_utf8(&text) else {
        return 0;
    };
    if c.error.is_some() {
        return 0;
    }
    if signed != 0 {
        if let Ok(n) = text.parse::<i64>() {
            if bits == 64 || (n >= -(1i64 << (bits - 1)) && n < 1i64 << (bits - 1)) {
                return n as u64;
            }
        }
    } else if let Ok(n) = text.parse::<u64>() {
        if bits == 64 || n < 1u64 << bits {
            return n;
        }
    }
    c.fail("range", "Integer is outside the requested type's range");
    0
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_word(c: usize, value: u64, signed: usize, quoted: usize) {
    let c = unsafe { ctx(c) };
    let text = if signed != 0 {
        (value as i64).to_string()
    } else {
        value.to_string()
    };
    if quoted != 0 {
        c.write_string(text.as_bytes());
    } else {
        c.append(text.as_bytes());
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_read_float(c: usize, bits: usize) -> f64 {
    let c = unsafe { ctx(c) };
    if c.peek() == b'"' {
        let value = c.string();
        return match &value[..] {
            b"NaN" => f64::NAN,
            b"Infinity" => f64::INFINITY,
            b"-Infinity" => f64::NEG_INFINITY,
            _ => {
                c.fail("type", "Expected a number or special float string");
                0.0
            }
        };
    }
    let value = c.number();
    let parsed = core::str::from_utf8(&value).ok().and_then(|s| {
        // Parsing as f64 then demoting can round twice near an f32 midpoint.
        if bits == 32 {
            s.parse::<f32>().ok().map(f64::from)
        } else {
            s.parse::<f64>().ok()
        }
    });
    match parsed {
        Some(n) if n.is_finite() => n,
        _ => {
            c.fail("range", "Float is outside the finite range");
            0.0
        }
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_float(c: usize, value: f64) {
    let c = unsafe { ctx(c) };
    if value.is_nan() {
        c.write_string(b"NaN");
    } else if value == f64::INFINITY {
        c.write_string(b"Infinity");
    } else if value == f64::NEG_INFINITY {
        c.write_string(b"-Infinity");
    } else {
        c.append(format!("{value:.16e}").as_bytes());
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_read_char(c: usize) -> usize {
    let c = unsafe { ctx(c) };
    let bytes = c.string();
    if let Ok(text) = core::str::from_utf8(&bytes) {
        let mut chars = text.chars();
        if let (Some(ch), None) = (chars.next(), chars.next()) {
            return ch as usize;
        }
    }
    c.fail("type", "Expected exactly one Unicode scalar");
    0
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_char(c: usize, value: usize) {
    let c = unsafe { ctx(c) };
    if let Some(ch) = char::from_u32(value as u32) {
        c.write_string(ch.encode_utf8(&mut [0; 4]).as_bytes());
    } else {
        c.fail("type", "Invalid Unicode scalar");
    }
}

// Scalar-only bridges for Motoko arbitrary precision integers. This is not a
// Candid envelope or a structural serialization: only the integer's bits cross.
fn decimal_to_leb(text: &[u8], signed: bool) -> Vec<u8> {
    let has_sign = text.first() == Some(&b'-');
    let digits = if has_sign { &text[1..] } else { text };
    let negative = has_sign && digits.iter().any(|b| *b != b'0');
    let mut words = vec![0u32];
    for &digit in digits {
        let mut carry = u64::from(digit - b'0');
        for word in &mut words {
            let n = u64::from(*word) * 10 + carry;
            *word = n as u32;
            carry = n >> 32;
        }
        if carry != 0 {
            words.push(carry as u32);
        }
    }
    let bits = (words.len() - 1) * 32 + (32 - words.last().unwrap().leading_zeros()) as usize;
    let count = bits.max(1).div_ceil(7);
    let mut groups = Vec::with_capacity(count + 1);
    for i in 0..count {
        let bit = i * 7;
        let word = bit / 32;
        let shift = bit % 32;
        let n = (u64::from(words[word])
            | (u64::from(words.get(word + 1).copied().unwrap_or(0)) << 32))
            >> shift;
        groups.push(n as u8 & 127);
    }
    if signed {
        if negative {
            let mut carry = 1u8;
            for group in &mut groups {
                let n = (127 - *group) + carry;
                *group = n & 127;
                carry = n >> 7;
            }
            if groups.last().unwrap() & 64 == 0 {
                groups.push(127);
            }
        } else if groups.last().unwrap() & 64 != 0 {
            groups.push(0);
        }
    }
    let last = groups.len() - 1;
    for group in &mut groups[..last] {
        *group |= 128;
    }
    groups
}
fn leb_to_decimal(leb: &[u8], signed: bool) -> Vec<u8> {
    let negative = signed && leb.last().is_some_and(|b| b & 64 != 0);
    let mut words = vec![0u32; (leb.len() * 7).div_ceil(32).max(1)];
    let mut carry = u8::from(negative);
    for (i, &group) in leb.iter().enumerate() {
        let group = if negative {
            let n = (127 - (group & 127)) + carry;
            carry = n >> 7;
            n & 127
        } else {
            group & 127
        };
        let bit = i * 7;
        let word = bit / 32;
        let shift = bit % 32;
        words[word] |= u32::from(group) << shift;
        if shift > 25 {
            words[word + 1] |= u32::from(group) >> (32 - shift);
        }
    }
    while words.len() > 1 && words.last() == Some(&0) {
        words.pop();
    }
    let mut chunks = Vec::new();
    while words.iter().any(|n| *n != 0) {
        let mut remainder = 0u64;
        for word in words.iter_mut().rev() {
            let n = (remainder << 32) | u64::from(*word);
            *word = (n / 1_000_000_000) as u32;
            remainder = n % 1_000_000_000;
        }
        chunks.push(remainder as u32);
        while words.len() > 1 && words.last() == Some(&0) {
            words.pop();
        }
    }
    let mut result = String::new();
    if negative {
        result.push('-');
    }
    result.push_str(&chunks.pop().unwrap_or(0).to_string());
    for chunk in chunks.iter().rev() {
        result.push_str(&format!("{chunk:09}"));
    }
    result.into_bytes()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_read_bigint(c: usize, signed: usize) {
    let c = unsafe { ctx(c) };
    let text = c.integer(signed != 0, true);
    c.scalar = if c.error.is_some() {
        vec![0]
    } else {
        decimal_to_leb(&text, signed != 0)
    };
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_bigint(c: usize, ptr: usize, len: usize, signed: usize) {
    let c = unsafe { ctx(c) };
    if c.error.is_some() {
        return;
    }
    if len > MAX_INTEGER_DIGITS / 2 {
        c.fail("limit", "JSON integer digit limit exceeded");
        return;
    }
    let text = leb_to_decimal(unsafe { bytes(ptr, len) }, signed != 0);
    if text.len() > MAX_INTEGER_DIGITS + usize::from(text.first() == Some(&b'-')) {
        c.fail("limit", "JSON integer digit limit exceeded");
    } else {
        c.write_string(&text);
    }
}

const B64: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const B64_INVERSE: [u8; 256] = {
    let mut table = [255; 256];
    let mut i = 0;
    while i < B64.len() {
        table[B64[i] as usize] = i as u8;
        i += 1;
    }
    table
};
fn base64_digit(byte: u8) -> Option<u8> {
    let digit = B64_INVERSE[byte as usize];
    if digit == 255 { None } else { Some(digit) }
}
fn base64_chunk(chunk: &[u8]) -> [u8; 4] {
    let n = (u32::from(chunk[0]) << 16)
        | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
        | u32::from(*chunk.get(2).unwrap_or(&0));
    [
        B64[(n >> 18) as usize],
        B64[((n >> 12) & 63) as usize],
        if chunk.len() > 1 {
            B64[((n >> 6) & 63) as usize]
        } else {
            b'='
        },
        if chunk.len() > 2 {
            B64[(n & 63) as usize]
        } else {
            b'='
        },
    ]
}
#[cfg(test)]
fn base64(bytes: &[u8]) -> Vec<u8> {
    bytes.chunks(3).flat_map(base64_chunk).collect()
}
fn unbase64(bytes: &[u8]) -> Option<Vec<u8>> {
    if bytes.len() % 4 != 0 {
        return None;
    }
    let mut out = Vec::with_capacity(bytes.len() / 4 * 3);
    for (i, chunk) in bytes.chunks_exact(4).enumerate() {
        let a = base64_digit(chunk[0])?;
        let b = base64_digit(chunk[1])?;
        let last = i + 1 == bytes.len() / 4;
        out.push((a << 2) | (b >> 4));
        if chunk[2] == b'=' {
            if !last || chunk[3] != b'=' || b & 15 != 0 {
                return None;
            }
        } else {
            let c = base64_digit(chunk[2])?;
            out.push((b << 4) | (c >> 2));
            if chunk[3] == b'=' {
                if !last || c & 3 != 0 {
                    return None;
                }
            } else {
                let d = base64_digit(chunk[3])?;
                out.push((c << 6) | d);
            }
        }
    }
    Some(out)
}
fn crc32(bytes: &[u8]) -> u32 {
    let mut crc = !0u32;
    for &byte in bytes {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            crc = (crc >> 1) ^ (0xedb88320 & (0u32.wrapping_sub(crc & 1)));
        }
    }
    !crc
}
const B32: &[u8] = b"abcdefghijklmnopqrstuvwxyz234567";
fn principal_text(bytes: &[u8]) -> Vec<u8> {
    let mut all = crc32(bytes).to_be_bytes().to_vec();
    all.extend_from_slice(bytes);
    let mut bits = 0u32;
    let mut count = 0;
    let mut out = Vec::new();
    let mut chars = 0;
    for byte in all {
        bits = (bits << 8) | u32::from(byte);
        count += 8;
        while count >= 5 {
            count -= 5;
            if chars > 0 && chars % 5 == 0 {
                out.push(b'-');
            }
            out.push(B32[((bits >> count) & 31) as usize]);
            chars += 1;
        }
    }
    if count > 0 {
        if chars > 0 && chars % 5 == 0 {
            out.push(b'-');
        }
        out.push(B32[((bits << (5 - count)) & 31) as usize]);
    }
    out
}
fn principal_bytes(text: &[u8]) -> Option<Vec<u8>> {
    if text.len() > 63 {
        return None;
    }
    let mut out = Vec::new();
    let mut bits = 0u32;
    let mut count = 0;
    for &byte in text {
        if byte == b'-' {
            continue;
        }
        let n = B32.iter().position(|b| *b == byte)? as u32;
        bits = (bits << 5) | n;
        count += 5;
        if count >= 8 {
            count -= 8;
            out.push((bits >> count) as u8);
        }
    }
    if out.len() < 4 || out.len() > 33 || (bits & ((1 << count) - 1)) != 0 {
        return None;
    }
    let raw = &out[4..];
    if out[..4] != crc32(raw).to_be_bytes() || principal_text(raw) != text {
        return None;
    }
    Some(raw.to_vec())
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_read_binary(c: usize, principal: usize) {
    let c = unsafe { ctx(c) };
    let text = c.string();
    let value = if principal != 0 {
        principal_bytes(&text)
    } else {
        unbase64(&text)
    };
    match value {
        Some(value) => c.scalar = value,
        None => {
            c.fail(
                if principal != 0 {
                    "principal"
                } else {
                    "base64"
                },
                if principal != 0 {
                    "Invalid principal text"
                } else {
                    "Invalid padded base64 string"
                },
            );
            c.scalar.clear();
        }
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_binary(c: usize, ptr: usize, len: usize, principal: usize) {
    let c = unsafe { ctx(c) };
    if c.error.is_some() {
        return;
    }
    let encoded_len = if principal != 0 {
        if len > 29 {
            c.fail("principal", "Invalid principal bytes");
            return;
        }
        // A principal has at most 63 text bytes.
        63
    } else {
        match len.checked_add(2).and_then(|n| (n / 3).checked_mul(4)) {
            Some(len) => len,
            None => {
                c.fail("limit", "JSON byte limit exceeded");
                return;
            }
        }
    };
    if principal == 0 && !c.check_string(encoded_len) {
        return;
    }
    let bytes = unsafe { bytes(ptr, len) };
    if principal != 0 {
        c.write_string(&principal_text(bytes));
        return;
    }
    // Base64 needs no JSON escaping. Reserve once and fill the final output
    // directly, avoiding a second vector and repeated per-chunk growth checks.
    let start = c.output.len();
    c.output.resize(start + encoded_len + 2, 0);
    c.output[start] = b'"';
    for (chunk, destination) in bytes
        .chunks(3)
        .zip(c.output[start + 1..start + 1 + encoded_len].chunks_exact_mut(4))
    {
        destination.copy_from_slice(&base64_chunk(chunk));
    }
    c.output[start + 1 + encoded_len] = b'"';
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::alloc::{GlobalAlloc, Layout, System};
    use std::cell::Cell;

    std::thread_local! {
        static ALLOCATED: Cell<Option<usize>> = const { Cell::new(None) };
    }
    struct CountAllocations;
    fn charge_allocation(size: usize) {
        let _ = ALLOCATED.try_with(|counter| {
            if let Some(total) = counter.get() {
                counter.set(Some(total.saturating_add(size)));
            }
        });
    }
    unsafe impl GlobalAlloc for CountAllocations {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            charge_allocation(layout.size());
            unsafe { System.alloc(layout) }
        }
        unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
            charge_allocation(layout.size());
            unsafe { System.alloc_zeroed(layout) }
        }
        unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, size: usize) -> *mut u8 {
            charge_allocation(size);
            unsafe { System.realloc(ptr, layout, size) }
        }
        unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
            unsafe { System.dealloc(ptr, layout) }
        }
    }
    #[global_allocator]
    static TEST_ALLOCATOR: CountAllocations = CountAllocations;

    fn allocated_by(action: impl FnOnce()) -> usize {
        ALLOCATED.set(Some(0));
        action();
        ALLOCATED.replace(None).unwrap()
    }

    fn context(input: &'static str) -> Context {
        Context::new(input.as_bytes())
    }
    fn assert_same_scalar_scan(input: &'static [u8], is_string: bool) {
        let mut materialized = Context::new(input);
        let mut skipped = Context::new(input);
        if is_string {
            materialized.string();
            skipped.skip_string();
        } else {
            materialized.number();
            skipped.skip_number();
        }
        assert_eq!(materialized.at, skipped.at, "{input:?}");
        let diagnostic = |c: Context| c.error.map(|e| (e.kind, e.message, e.offset, e.path));
        assert_eq!(diagnostic(materialized), diagnostic(skipped), "{input:?}");
    }
    #[test]
    fn skipped_scalars_preserve_exact_validation() {
        for input in [
            b"\"\"".as_slice(),
            b"\"plain text\"",
            "\"café😀\"".as_bytes(),
            br#""\uD83D\uDE00\n\u0061""#,
            br#""\uD800""#,
            br#""\uDC00""#,
            br#""\uD800\u1234""#,
            br#""\u123X""#,
            br#""\q""#,
            b"\"unterminated",
            b"\"incomplete\\",
            b" true",
            b"\"\xff\\uD800\"",
            b"\"\xff\\n\"",
            b"\"\xc2\\n\x80\"",
        ] {
            assert_same_scalar_scan(input, true);
        }
        for byte in 0..=255u8 {
            assert_same_scalar_scan(Box::leak(Box::new([b'"', byte, b'"'])), true);
            assert_same_scalar_scan(Box::leak(Box::new([b'"', b'\\', byte, b'"'])), true);
        }
        for input in [
            "",
            " ",
            "0",
            "-0",
            "-1",
            "01",
            "1.2",
            "1.",
            "1.e2",
            "1e",
            "1e+",
            "1e-2",
            "1E+123",
            "1e999999999999999999999",
            "-",
            "+1",
            " 123 ",
            "true",
            "1,2",
            "1e+2x",
            "--1",
            "0.0e-00000",
        ] {
            assert_same_scalar_scan(input.as_bytes(), false);
        }
    }
    #[test]
    fn nested_prescans_do_not_copy_large_scalar_values() {
        const DEPTH: usize = 64;
        let input = Box::leak(
            format!(
                "{}\"{}\"{}",
                "[".repeat(DEPTH),
                "x".repeat(1024 * 1024),
                "]".repeat(DEPTH)
            )
            .into_boxed_str(),
        );
        let mut c = context(input);
        let allocated = allocated_by(|| {
            // Follow the same repeated count-then-decode descent as generated
            // array visitors. The old skip path copied at least 64 MiB here.
            for _ in 0..DEPTH {
                assert!(c.enter());
                assert_eq!(c.array_start(), 1);
            }
            c.skip();
            assert!(c.error.is_none());
        });
        assert!(
            allocated < 64 * 1024,
            "pre-scans allocated {allocated} bytes"
        );
        assert_eq!(c.scalar.capacity(), 0);
        assert_eq!(c.output.capacity(), 0);

        let input = Box::leak("9".repeat(1024 * 1024).into_boxed_str());
        let mut c = context(input);
        assert_eq!(allocated_by(|| c.skip_number()), 0);
        assert_eq!(c.at, input.len());
        assert!(c.error.is_none());
    }
    #[test]
    fn escapes_and_unicode() {
        let mut c = context(r#""hello\n\uD83D\uDE00é""#);
        assert_eq!(c.string(), "hello\n😀é".as_bytes());
        assert!(c.error.is_none());
        for input in [r#""\uD800""#, r#""\uDC00""#, r#""\uD800\u1234""#, r#""\q""#] {
            let mut c = context(input);
            c.string();
            assert!(c.error.is_some());
        }
    }
    #[test]
    fn strict_structure_and_duplicate_keys() {
        for input in [
            r#"{"a":1,"a":2}"#,
            r#"{"a":1,"\u0061":2}"#,
            "[1,]",
            "[01]",
            "[1e]",
            "{\"x\":true,}",
        ] {
            let mut c = context(input);
            c.skip();
            assert!(c.error.is_some(), "{input}");
        }
        let mut c = context(r#"{"unknown":{"x":[null,true,{},[]]}}"#);
        c.skip();
        assert!(c.error.is_none());
    }
    #[test]
    fn decimal_leb_roundtrips() {
        assert_eq!(decimal_to_leb(b"-0", true), [0]);
        for text in [
            "0",
            "1",
            "63",
            "64",
            "127",
            "128",
            "255",
            "256",
            "18446744073709551616",
            "999999999999999999999999999999999999999999999999999999999999999999999",
        ] {
            for signed in [false, true] {
                assert_eq!(
                    leb_to_decimal(&decimal_to_leb(text.as_bytes(), signed), signed),
                    text.as_bytes()
                );
            }
            if text != "0" {
                let text = format!("-{text}");
                assert_eq!(
                    leb_to_decimal(&decimal_to_leb(text.as_bytes(), true), true),
                    text.as_bytes()
                );
            }
        }
        for n in -20000..20000 {
            let text = n.to_string();
            assert_eq!(
                leb_to_decimal(&decimal_to_leb(text.as_bytes(), true), true),
                text.as_bytes()
            );
        }
    }
    #[test]
    fn binary_strings_are_strict() {
        for input in [b"".as_slice(), b"a", b"ab", b"abc", b"\x00\xff\x80\x00"] {
            assert_eq!(unbase64(&base64(input)).unwrap(), input);
        }
        for input in [b"A===".as_slice(), b"Zh==", b"Zm9=", b" Zg=", b"Zg==AAAA"] {
            assert!(unbase64(input).is_none());
        }
        assert_eq!(principal_text(&[]), b"aaaaa-aa");
        assert_eq!(principal_text(&[4]), b"2vxsx-fae");
        for input in [b"".as_slice(), b"\x04", &[255; 29]] {
            assert_eq!(principal_bytes(&principal_text(input)).unwrap(), input);
        }
        assert!(principal_bytes(b"aaaaa-ab").is_none());
    }
    #[test]
    fn counting_restores_cursor_and_items() {
        let mut c = context(r#"[{"x":[1,2]},"hello",null]"#);
        assert_eq!(c.array_start(), 3);
        assert_eq!(c.at, 1);
        assert_eq!(c.items, 0);
    }
    #[test]
    fn deeply_nested_input_returns_error() {
        let input: &'static str =
            Box::leak(format!("{}0{}", "[".repeat(200), "]".repeat(200)).into_boxed_str());
        let mut c = context(input);
        c.skip();
        assert_eq!(c.error.unwrap().kind, "limit");
    }
    #[test]
    fn unicode_json_pointer_paths_and_float32_overflow() {
        let mut c = context("");
        c.key = "café/☃~".as_bytes().to_vec();
        c.push_key();
        assert_eq!(c.path, "/café~1☃~0");
        c.pop_path();
        assert_eq!(c.path, "");
        for (input, valid) in [("1e39", false), ("1e38", true), ("\"Infinity\"", true)] {
            let mut c = context(input);
            unsafe { json_read_float(&mut c as *mut Context as usize, 32) };
            assert_eq!(c.error.is_none(), valid);
        }
        let mut c = context("1.0000000596046448");
        let n = unsafe { json_read_float(&mut c as *mut Context as usize, 32) };
        assert_eq!(n as f32, f32::from_bits(1.0f32.to_bits() + 1));
    }
    #[test]
    fn quotas_reject_before_large_temporary_allocation() {
        let mut c = context("");
        // The pointer is deliberately unusable: over-limit input must be
        // rejected from its length before either reading or copying it.
        unsafe { json_write_binary(&mut c as *mut Context as usize, 0, usize::MAX, 0) };
        assert_eq!(c.error.unwrap().kind, "limit");
        assert_eq!(c.output.capacity(), 0);
        let mut c = context("");
        assert!(!c.check_string(MAX_BYTES));
        assert_eq!(c.output.capacity(), 0);
        let mut c = context("");
        c.items = 1;
        assert!(!c.collection(MAX_ITEMS));
        assert_eq!(c.error.unwrap().kind, "limit");
    }
    #[test]
    fn prescan_error_paths_include_array_indices() {
        let mut c = context(r#"[{"café/~":[0,"\uD800"]}]"#);
        c.array_start();
        assert_eq!(c.error.unwrap().path, "/0/café~1~0/1");
    }
    #[test]
    fn binary_writer_streams_padded_base64() {
        for (input, expected) in [
            ("", "\"\""),
            ("f", "\"Zg==\""),
            ("fo", "\"Zm8=\""),
            ("foo", "\"Zm9v\""),
        ] {
            let mut c = context("");
            unsafe {
                json_write_binary(
                    &mut c as *mut Context as usize,
                    input.as_ptr() as usize,
                    input.len(),
                    0,
                )
            };
            assert_eq!(c.output, expected.as_bytes());
            assert!(c.error.is_none());
        }
    }
    #[test]
    fn base64_alphabet_and_block_boundaries() {
        for byte in 0..=255u8 {
            if !B64.contains(&byte) {
                assert!(unbase64(&[byte, b'A', b'A', b'A']).is_none());
            }
        }
        for len in [0, 1, 2, 3, 63, 255, 256, 257, 65536] {
            let input: Vec<u8> = (0..len).map(|i| (i * 17 + 11) as u8).collect();
            let encoded = base64(&input);
            assert_eq!(unbase64(&encoded).unwrap(), input);
            let mut c = context("");
            unsafe {
                json_write_binary(
                    &mut c as *mut Context as usize,
                    input.as_ptr() as usize,
                    input.len(),
                    0,
                )
            };
            assert_eq!(&c.output[1..c.output.len() - 1], encoded);
            assert!(c.error.is_none());
        }
    }
}
