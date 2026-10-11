//! Streaming JSON reader/writer for compiler-specialized Motoko visitors.
//! Values never pass through Candid or a generic JSON value tree. All pointers
//! are borrowed only during one synchronous call, without GC safepoints.
#![cfg_attr(not(test), no_std)]
#![cfg_attr(not(test), feature(alloc_error_handler))]

extern crate alloc;

use alloc::{
    borrow::Cow,
    boxed::Box,
    collections::BTreeSet,
    format,
    string::{String, ToString},
    vec,
    vec::Vec,
};
use core::cmp::Ordering;

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

// Scan eight bytes at a time until JSON escaping or a closing quote matters.
// The byte tests work for UTF-8 too; Unicode validity is checked separately.
#[inline]
fn string_special(bytes: &[u8], mut at: usize) -> usize {
    #[inline]
    fn zero_byte(word: u64) -> bool {
        word.wrapping_sub(0x0101_0101_0101_0101) & !word & 0x8080_8080_8080_8080 != 0
    }
    while bytes.len() - at >= 8 {
        let word = u64::from_le_bytes(bytes[at..at + 8].try_into().expect("eight bytes"));
        if zero_byte(word ^ 0x2222_2222_2222_2222)
            || zero_byte(word ^ 0x5c5c_5c5c_5c5c_5c5c)
            || zero_byte(word & 0xe0e0_e0e0_e0e0_e0e0)
        {
            break;
        }
        at += 8;
    }
    while at < bytes.len() {
        let byte = bytes[at];
        if byte == b'"' || byte == b'\\' || byte < 32 {
            break;
        }
        at += 1;
    }
    at
}

struct Error {
    kind: &'static str,
    message: &'static str,
    offset: usize,
    path: String,
}
// Object keys retain validated source ranges, including their escapes. This
// makes repeated array pre-scans independent of key length in scratch space.
// Comparing decoded characters also catches differently escaped duplicates.
#[derive(Clone, Copy)]
struct Key {
    text: &'static str,
    escaped: bool,
}
impl Key {
    fn literal(text: &'static str) -> Self {
        Self {
            text,
            escaped: false,
        }
    }
    fn chars(self) -> KeyChars<'static> {
        KeyChars {
            chars: self.text.chars(),
            escaped: self.escaped,
        }
    }
    fn matches(self, bytes: &[u8]) -> bool {
        if !self.escaped {
            self.text.as_bytes() == bytes
        } else {
            core::str::from_utf8(bytes).is_ok_and(|text| self.chars().eq(text.chars()))
        }
    }
}
struct KeyChars<'a> {
    chars: core::str::Chars<'a>,
    escaped: bool,
}
impl KeyChars<'_> {
    fn hex4(&mut self) -> u32 {
        (0..4).fold(0, |n, _| {
            n * 16
                + self
                    .chars
                    .next()
                    .and_then(|c| c.to_digit(16))
                    .expect("validated key escape")
        })
    }
}
impl Iterator for KeyChars<'_> {
    type Item = char;
    fn next(&mut self) -> Option<char> {
        let ch = self.chars.next()?;
        if ch != '\\' || !self.escaped {
            return Some(ch);
        }
        Some(match self.chars.next().expect("validated key escape") {
            '"' => '"',
            '\\' => '\\',
            '/' => '/',
            'b' => '\u{8}',
            'f' => '\u{c}',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'u' => {
                let high = self.hex4();
                let cp = if (0xd800..=0xdbff).contains(&high) {
                    self.chars.next(); // validated backslash
                    self.chars.next(); // validated 'u'
                    0x10000 + ((high - 0xd800) << 10) + self.hex4() - 0xdc00
                } else {
                    high
                };
                char::from_u32(cp).expect("validated key scalar")
            }
            _ => unreachable!("validated key escape"),
        })
    }
}
impl PartialEq for Key {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}
impl Eq for Key {}
impl PartialOrd for Key {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for Key {
    fn cmp(&self, other: &Self) -> Ordering {
        if !self.escaped && !other.escaped {
            self.text.as_bytes().cmp(other.text.as_bytes())
        } else {
            self.chars().cmp(other.chars())
        }
    }
}
struct ObjectFrame {
    first: bool,
    key_start: usize,
    // Small records reuse a shared key stack; large objects switch to a tree
    // after eight keys so duplicate validation remains bounded O(n log n).
    wide: Option<BTreeSet<Key>>,
}
// Borrow input keys or compiler literals until the first error needs a pointer.
// Successful visits only push/pop components; they never format path text.
enum PathComponent {
    Key(Key),
    Index(usize),
}
pub struct Context {
    input: &'static [u8],
    at: usize,
    output: Vec<u8>,
    scalar: Cow<'static, [u8]>,
    key: Key,
    objects: Vec<ObjectFrame>,
    keys: Vec<Key>,
    path: Vec<PathComponent>,
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
            scalar: Cow::Borrowed(&[]),
            key: Key::literal(""),
            objects: Vec::new(),
            keys: Vec::new(),
            path: Vec::new(),
            error: (input.len() > MAX_BYTES).then(|| Error {
                kind: "limit",
                message: "JSON byte limit exceeded",
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
                path: self.error_path(),
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
    fn string(&mut self) -> Cow<'static, [u8]> {
        if self.error.is_some() {
            return Cow::Borrowed(&[]);
        }
        if self.peek() != b'"' {
            self.fail("type", "Expected a JSON string");
            return Cow::Borrowed(&[]);
        }
        self.at += 1;
        let beginning = self.at;
        let mut start = beginning;
        let mut result = Vec::new();
        loop {
            self.at = string_special(self.input, self.at);
            let Some(&byte) = self.input.get(self.at) else {
                self.fail("syntax", "Unterminated JSON string");
                return Cow::Borrowed(&[]);
            };
            match byte {
                b'"' => {
                    // The input is rooted for the whole synchronous visitor.
                    // Unescaped text and keys can borrow it until the caller
                    // creates the final managed Motoko value.
                    let result = if start == beginning {
                        Cow::Borrowed(&self.input[start..self.at])
                    } else {
                        result.extend_from_slice(&self.input[start..self.at]);
                        Cow::Owned(result)
                    };
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
                        return Cow::Borrowed(&[]);
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
                                    return Cow::Borrowed(&[]);
                                }
                                self.at += 2;
                                let low = self.hex4();
                                if !(0xdc00..=0xdfff).contains(&low) {
                                    self.fail("syntax", "Unpaired Unicode surrogate");
                                    return Cow::Borrowed(&[]);
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
                                    return Cow::Borrowed(&[]);
                                }
                            }
                        }
                        _ => {
                            self.fail("syntax", "Invalid JSON escape");
                            return Cow::Borrowed(&[]);
                        }
                    }
                    if self.error.is_some() {
                        return Cow::Borrowed(&[]);
                    }
                    start = self.at;
                }
                0..=31 => {
                    self.fail("syntax", "Unescaped control character");
                    return Cow::Borrowed(&[]);
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
            self.at = string_special(self.input, self.at);
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
    fn number(&mut self) -> Cow<'static, [u8]> {
        if self.error.is_some() {
            return Cow::Borrowed(&[]);
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
                return Cow::Borrowed(&[]);
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
        Cow::Borrowed(&self.input[start..self.at])
    }
    fn skip_number(&mut self) {
        self.number();
    }
    fn integer(&mut self, signed: bool, quoted: bool) -> Cow<'static, [u8]> {
        let value = if quoted && self.peek() == b'"' {
            self.string()
        } else {
            self.number()
        };
        if self.error.is_some() {
            return Cow::Borrowed(&[]);
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
            return Cow::Borrowed(&[]);
        }
        if digits.len() > MAX_INTEGER_DIGITS {
            self.fail("limit", "JSON integer digit limit exceeded");
            return Cow::Borrowed(&[]);
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
            key_start: self.keys.len(),
            wide: None,
        });
    }
    fn object_next(&mut self) -> bool {
        if self.error.is_some() {
            return false;
        }
        if self.peek() == b'}' {
            self.at += 1;
            if let Some(frame) = self.objects.pop() {
                self.keys.truncate(frame.key_start);
            }
            return false;
        }
        let first = match self.objects.last() {
            Some(frame) => frame.first,
            None => return false,
        };
        if !first && !self.expect(b',') {
            return false;
        }
        self.ws();
        let start = self.at;
        self.skip_string();
        if self.error.is_some() {
            return false;
        }
        let text =
            core::str::from_utf8(&self.input[start + 1..self.at - 1]).expect("validated key");
        let key = Key {
            text,
            escaped: text.as_bytes().contains(&b'\\'),
        };
        let frame = self.objects.last_mut().expect("object frame");
        frame.first = false;
        let inserted = if let Some(keys) = &mut frame.wide {
            keys.insert(key)
        } else {
            let keys = &self.keys[frame.key_start..];
            if keys.contains(&key) {
                false
            } else if keys.len() < 8 {
                self.keys.push(key);
                true
            } else {
                let mut wide: BTreeSet<Key> = keys.iter().copied().collect();
                wide.insert(key);
                frame.wide = Some(wide);
                true
            }
        };
        if !inserted {
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
    fn error_path(&self) -> String {
        let mut path = String::new();
        for component in &self.path {
            path.push('/');
            match component {
                PathComponent::Key(key) => {
                    path.reserve(key.text.len());
                    for ch in key.chars() {
                        match ch {
                            '~' => path.push_str("~0"),
                            '/' => path.push_str("~1"),
                            _ => path.push(ch),
                        }
                    }
                }
                PathComponent::Index(index) => {
                    let mut storage = [0; 20];
                    let digits = decimal_word(*index as u64, &mut storage);
                    path.push_str(core::str::from_utf8(digits).expect("decimal digits"));
                }
            }
        }
        path
    }
    fn push_key(&mut self) {
        self.path.push(PathComponent::Key(self.key));
    }
    fn push_index(&mut self, index: usize) {
        self.path.push(PathComponent::Index(index));
    }
    fn pop_path(&mut self) {
        self.path.pop();
    }
    fn write_string(&mut self, bytes: &[u8]) {
        if !self.check_string(bytes.len()) {
            return;
        }
        self.append(b"\"");
        let mut start = 0;
        loop {
            let end = string_special(bytes, start);
            self.append(&bytes[start..end]);
            if end == bytes.len() {
                break;
            }
            let byte = bytes[end];
            let escape: &[u8] = match byte {
                b'"' => b"\\\"",
                b'\\' => b"\\\\",
                b'\n' => b"\\n",
                b'\r' => b"\\r",
                b'\t' => b"\\t",
                _ => b"",
            };
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
            start = end + 1;
        }
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
    unsafe { ctx(c) }.key.matches(unsafe { bytes(ptr, len) }) as usize
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_path_key(c: usize) {
    unsafe { ctx(c) }.push_key();
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_path_field(c: usize, ptr: usize, len: usize) {
    let c = unsafe { ctx(c) };
    c.key = Key::literal(
        core::str::from_utf8(unsafe { bytes(ptr, len) }).expect("compiler field name"),
    );
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
// At most 20 decimal digits represent every u64. Callers add any sign or
// quotes directly, without creating short-lived formatting strings.
fn decimal_word(mut value: u64, storage: &mut [u8; 20]) -> &[u8] {
    let mut start = storage.len();
    loop {
        start -= 1;
        storage[start] = b'0' + (value % 10) as u8;
        value /= 10;
        if value == 0 {
            return &storage[start..];
        }
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn json_write_word(c: usize, value: u64, signed: usize, quoted: usize) {
    let c = unsafe { ctx(c) };
    if c.error.is_some() {
        return;
    }
    let negative = signed != 0 && (value as i64) < 0;
    let mut storage = [0; 20];
    let digits = decimal_word(
        if negative {
            value.wrapping_neg()
        } else {
            value
        },
        &mut storage,
    );
    if quoted != 0 {
        c.append(b"\"");
    }
    if negative {
        c.append(b"-");
    }
    c.append(digits);
    if quoted != 0 {
        c.append(b"\"");
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
        Cow::Borrowed(&[0])
    } else {
        Cow::Owned(decimal_to_leb(&text, signed != 0))
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
    if bytes.is_empty() {
        return Some(Vec::new());
    }
    let mut out = vec![0; bytes.len() / 4 * 3];
    let last = bytes.len() - 4;
    // All but the last group have four ordinary alphabet bytes. Fill the
    // output at its final size instead of checking Vec capacity per byte.
    for (src, dst) in bytes[..last].chunks_exact(4).zip(out.chunks_exact_mut(3)) {
        let a = B64_INVERSE[src[0] as usize];
        let b = B64_INVERSE[src[1] as usize];
        let c = B64_INVERSE[src[2] as usize];
        let d = B64_INVERSE[src[3] as usize];
        if a | b | c | d == 255 {
            return None;
        }
        dst[0] = (a << 2) | (b >> 4);
        dst[1] = (b << 4) | (c >> 2);
        dst[2] = (c << 6) | d;
    }
    let src = &bytes[last..];
    let a = base64_digit(src[0])?;
    let b = base64_digit(src[1])?;
    let start = out.len() - 3;
    out[start] = (a << 2) | (b >> 4);
    if src[2] == b'=' {
        if src[3] != b'=' || b & 15 != 0 {
            return None;
        }
        out.truncate(start + 1);
    } else {
        let c = base64_digit(src[2])?;
        out[start + 1] = (b << 4) | (c >> 2);
        if src[3] == b'=' {
            if c & 3 != 0 {
                return None;
            }
            out.truncate(start + 2);
        } else {
            out[start + 2] = (c << 6) | base64_digit(src[3])?;
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
        Some(value) => c.scalar = Cow::Owned(value),
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
            c.scalar = Cow::Borrowed(&[]);
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
        assert!(matches!(c.scalar, Cow::Borrowed(_)));
        assert_eq!(c.output.capacity(), 0);

        let input = Box::leak("9".repeat(1024 * 1024).into_boxed_str());
        let mut c = context(input);
        assert_eq!(allocated_by(|| c.skip_number()), 0);
        assert_eq!(c.at, input.len());
        assert!(c.error.is_none());
    }
    #[test]
    fn bulk_string_scan_matches_byte_validation() {
        for prefix in 0..24 {
            for byte in 0..=255u8 {
                for suffix in 0..16 {
                    let mut input = vec![b'x'; prefix];
                    input.push(byte);
                    input.extend(core::iter::repeat_n(b'y', suffix));
                    let expected = input
                        .iter()
                        .position(|b| *b == b'"' || *b == b'\\' || *b < 32)
                        .unwrap_or(input.len());
                    assert_eq!(string_special(&input, 0), expected);
                }
            }
        }
        for padding in 0..24 {
            let text = format!(
                "{}\"\\\n\r\t\0\u{1f}café☃😀{}",
                "x".repeat(padding),
                "y".repeat(padding)
            );
            let mut writer = context("");
            writer.write_string(text.as_bytes());
            let input = Box::leak(writer.output.into_boxed_slice());
            let mut reader = Context::new(input);
            assert_eq!(reader.string().as_ref(), text.as_bytes());
            assert!(reader.error.is_none());
        }
    }
    #[test]
    fn unescaped_scalars_borrow_the_input() {
        let mut c = context("\"plain ☃ text\"");
        let allocated = allocated_by(|| {
            let value = c.string();
            assert!(matches!(value, Cow::Borrowed(_)));
            assert_eq!(value, "plain ☃ text".as_bytes());
        });
        assert_eq!(allocated, 0);
        let mut c = context("12345678901234567890");
        assert_eq!(
            allocated_by(|| {
                assert_eq!(c.integer(false, true).as_ref(), b"12345678901234567890");
            }),
            0
        );
    }
    #[test]
    fn nested_prescans_borrow_escaped_object_keys() {
        const DEPTH: usize = 64;
        for suffix in ["", "\\u0078"] {
            let input = Box::leak(
                format!(
                    "{}{{\"{}{suffix}\":null}}{}",
                    "[".repeat(DEPTH),
                    "x".repeat(256 * 1024),
                    "]".repeat(DEPTH)
                )
                .into_boxed_str(),
            );
            let mut c = context(input);
            let allocated = allocated_by(|| {
                for _ in 0..DEPTH {
                    assert!(c.enter());
                    assert_eq!(c.array_start(), 1);
                }
                c.skip();
                assert!(c.error.is_none());
            });
            assert!(
                allocated < 1024 * 1024,
                "key pre-scans allocated {allocated} bytes"
            );
        }
    }
    #[test]
    fn large_error_paths_reserve_borrowed_keys() {
        for suffix in ["", "\\u0078"] {
            let input = Box::leak(
                format!("{{\"{}{suffix}\":truX}}", "x".repeat(256 * 1024)).into_boxed_str(),
            );
            let mut c = context(input);
            let allocated = allocated_by(|| c.skip());
            let error = c.error.unwrap();
            assert_eq!(error.kind, "type");
            assert_eq!(
                error.path,
                format!("/{}{}", "x".repeat(256 * 1024), if suffix.is_empty() { "" } else { "x" })
            );
            assert!(allocated < input.len() * 2, "error path allocated {allocated} bytes");
        }
    }
    #[test]
    fn borrowed_keys_compare_decoded_unicode() {
        for input in [
            r#"{"café/~":1,"caf\u00e9\/~":2}"#,
            r#"{"😀":1,"\uD83D\uDE00":2}"#,
            r#"{"\n":1,"\u000a":2}"#,
            r#"{"\\":1,"\u005c":2}"#,
            r#"{"\"":1,"\u0022":2}"#,
        ] {
            let mut c = context(input);
            c.skip();
            assert_eq!(c.error.unwrap().kind, "duplicate", "{input}");
        }
        let mut c = context(r#"{"caf\u00e9\/~":0}"#);
        c.object_start();
        assert!(c.object_next());
        assert!(c.key.matches("café/~".as_bytes()));
        c.push_key();
        assert_eq!(c.error_path(), "/café~1~0");
    }
    #[test]
    fn small_object_keys_reuse_storage_and_large_objects_detect_duplicates() {
        let input = Box::leak(
            format!(
                "[{}]",
                core::iter::repeat_n(r#"{"a":0,"b":{"x":0,"y":1},"c":2,"d":3}"#, 1024)
                    .collect::<Vec<_>>()
                    .join(",")
            )
            .into_boxed_str(),
        );
        let mut c = context(input);
        let allocated = allocated_by(|| c.skip());
        assert!(c.error.is_none());
        assert!(
            allocated < 4096,
            "small records allocated {allocated} bytes"
        );
        assert!(c.keys.is_empty());
        let fields = (0..100)
            .map(|i| format!("\"k{i}\":{i}"))
            .collect::<Vec<_>>()
            .join(",");
        for extra in ["", ",\"k0\":0", ",\"k8\":8", ",\"k99\":99"] {
            let input = Box::leak(format!("{{{fields}{extra}}}").into_boxed_str());
            let mut c = context(input);
            c.skip();
            assert_eq!(c.error.is_some(), !extra.is_empty());
            if let Some(e) = c.error {
                assert_eq!(e.kind, "duplicate");
            }
        }
    }
    #[test]
    fn decimal_word_boundaries() {
        for n in [
            0,
            1,
            9,
            10,
            99,
            100,
            u32::MAX as u64,
            i64::MAX as u64,
            u64::MAX,
        ] {
            let mut storage = [0; 20];
            assert_eq!(decimal_word(n, &mut storage), n.to_string().as_bytes());
        }
        for n in [i64::MIN, i64::MIN + 1, -1, 0, 1, i64::MAX] {
            for quoted in [0, 1] {
                let mut c = context("");
                unsafe { json_write_word(&mut c as *mut Context as usize, n as u64, 1, quoted) };
                let expected = if quoted == 0 {
                    n.to_string()
                } else {
                    format!("\"{n}\"")
                };
                assert_eq!(c.output, expected.as_bytes());
            }
        }
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
        c.key = Key::literal("café/☃~");
        c.push_key();
        assert_eq!(c.error_path(), "/café~1☃~0");
        c.pop_path();
        assert_eq!(c.error_path(), "");
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
            for position in 0..4 {
                let mut input = *b"AAAAAAAA";
                input[position] = byte;
                assert_eq!(unbase64(&input).is_some(), B64.contains(&byte));
            }
        }
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
