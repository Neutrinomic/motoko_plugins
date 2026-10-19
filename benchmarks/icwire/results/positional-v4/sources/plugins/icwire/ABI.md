# ICWire runtime ABI

This is a raw, schema-directed positional codec. There is no root header, record
frame, field identifier, field length or schema on the wire. Records concatenate
every field in ascending unsigned Candid-hash order, including absent options
as the byte zero. Variants encode the zero-based position in that same sorted
schema as canonical ULEB32, then their payload. Peers must share the schema.

All exports have prefix `icwire_`. `c`, pointers, lengths, flags and `usize`
are wasm64 `i64`; `u64` is `i64`, `f64` is `f64`. Borrowed input remains valid
for a single synchronous GC-free call. The first error is sticky. Check `ok`
before using decoded values or constructing managed objects.

```
new(ptr: usize, len: usize) -> usize       // context borrowing decode input
done(c) -> ()
ok(c) -> usize                           // 0/1
enter(c) -> usize                        // typed node + nesting charge, 0/1
leave(c) -> ()
collection(c, count: usize) -> usize     // preflight remaining typed-node budget
check_bytes(c, len: usize, kind: usize) -> usize
check_bigint(c, len: usize) -> usize
finish(c) -> ()                         // require all input consumed
error_part(c, part: usize) -> usize     // 0 kind ptr, 1 kind len, 2 byte offset
fail(c, code: usize) -> ()              // 2 variant, 3 canonical, other type
output_part(c, part: usize) -> usize    // 0 ptr, 1 len
scalar_ptr(c) -> usize                 // borrowed bytes/LEB pointer
scalar_len(c) -> usize                 // borrowed bytes/LEB length
read_length(c) -> usize                // canonical ULEB32; also variant ordinal
write_length(c, value: usize) -> ()
read_bool(c) -> usize                  // byte 0/1; also option tag
write_bool(c, value: usize) -> ()
read_word(c, signed: usize, bits: usize) -> u64
write_word(c, value: u64, bits: usize) -> ()
read_char(c) -> usize                  // validated Unicode scalar, u32 LE
write_char(c, value: usize) -> ()
read_float(c, bits: usize) -> f64       // 32/64 LE, finite, preserving signed zero
write_float(c, value: f64, bits: usize) -> ()
read_bytes(c, kind: usize) -> ()        // ULEB32 length + bytes; 0 Blob,1 Text,2 Principal
write_bytes(c, ptr: usize, len: usize, kind: usize) -> ()
utf8_valid(ptr: usize, len: usize) -> usize // pure validator for a proven input range
read_bigint(c, signed: usize) -> ()     // borrowed canonical ULEB/SLEB
integer_chunk(c, index: usize, signed: usize) -> u64 // <=9-byte/63-bit chunk
write_bigint(c, ptr: usize, len: usize, signed: usize) -> ()
write_small(c, value: u64, signed: usize) -> ()
read_array(c) -> usize                 // ULEB32 count + node preflight
write_array(c, count: usize) -> ()
read_words(c, bits: usize) -> usize     // bulk fixed-word array, borrowed payload
read_bools(c) -> usize                 // bulk validated Bool array, borrowed bytes
leaf_null(c) -> ()                     // fused primitive enter/read/leave
leaf_bool(c) -> usize
leaf_word(c, signed: usize, bits: usize) -> u64
leaf_char(c) -> usize
leaf_float(c, bits: usize) -> f64
leaf_bytes(c, kind: usize) -> usize     // borrowed payload ptr; 0 on error
leaf_text(c) -> usize                  // specialized UTF-8 Text leaf, same errors/bounds
leaf_bigint(c, signed: usize) -> u64    // small word or 0x8000000000000000 sentinel
```

Null/unit use zero bytes, so empty input is valid for these types. Tuples and
records concatenate their schema-directed values. Fixed words have exact widths
8/16/32/64 bits in little endian; signed reads sign-extend. Text validates UTF-8;
Principals contain at most 29 bytes. Lengths and ordinals use at most five ULEB
bytes and reject redundant high zero groups or values exceeding `u32::MAX`.

Limits are 16 MiB total bytes, 1,000,000 typed nodes, depth 128 and 4096 bytes per
Nat/Int LEB. Records do not add any work charge beyond their node and their
typed fields. `collection` runs before managed array allocation. `leaf_*` checks
depth and charges one node without transient depth writes. Composite nodes
retain `enter`/`leave`.

`read_words` runs inside an entered array. It reads/preflights the count,
checks child depth for nonempty arrays, validates the entire fixed-width byte
range, charges all child nodes, and exposes the borrowed payload via scalar
getters. Width is 8/16/32/64. Truncation points to the first incomplete element,
matching individual reads. Empty arrays do not require child depth.

`read_bools` follows the same array admission and depth rules, then scans the
available payload in order. The first invalid Boolean precedes a later missing
byte error. Failure cursor and node charges match individual leaf reads,
including the missing node on truncation. Success exposes the validated bytes
through the scalar getters so generated code can load each Boolean directly.

`leaf_bigint` directly returns the decoded word for at most nine canonical LEB
bytes; larger values return `0x8000000000000000`, and the scalar getters supply the
borrowed LEB. That sentinel is outside both nine-byte ULEB and SLEB ranges.
Check `ok` before inspecting it. `write_small` avoids a temporary managed Blob.

For validated LEB values up to 27 bytes, `integer_chunk` reads at most nine bytes
starting at `index * 9`, returning their 63-bit payload. Only the last chunk is
sign-extended when `signed` is set. Index must be 0, 1 or 2 and point inside the
scalar. This helper allocates nothing; generated code combines two or three
chunks through managed BigNum operations. Larger LEB values keep the SDK's
general conversion path. `leaf_bytes` returns its borrowed payload pointer
directly; `scalar_len` supplies the length after `ok` succeeds.

`leaf_bytes` and `leaf_text` return zero exactly on failure. A successful
borrowed Rust slice has a nonzero pointer even when empty. Generated code may
test the full wasm64 pointer against zero instead of making a separate `ok`
call before constructing a managed value.

Error kinds: `truncated`, `trailing`, `limit`, `canonical`, `bool`, `char`,
`float`, `utf8`, `principal`, `variant`, `type`. Offsets are absolute input
positions; encode errors use output position. Invalid scalars, noncanonical
integers/lengths, integer byte limits, and oversized byte lengths point to their
first byte. Truncation points to the failed read (the missing byte for LEB).
Array count limits point immediately after the count. Oversized input fails at
offset zero. ULEB32 overflow is `canonical`; a valid byte length above 16 MiB is
`limit` before payload access or principal validation. A suffix is `trailing`.

`utf8_valid` accepts only a pointer/length range already proven inside the
immutable input by generated code; it does not read a length prefix or allocate.
