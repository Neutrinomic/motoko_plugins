# ICWire runtime ABI

All exports have prefix `icwire_`. `c`, pointers, lengths, flags, tags, positions,
and `usize` below are wasm64 `i64`; `u64` is `i64`, `f64` is `f64`.
Pointers refer to synchronous GC-free call storage. Context and borrowed input
remain valid until `done`. The first error is sticky; check `ok` before using
decoded values or constructing managed values.

```
new(ptr: usize, len: usize) -> usize        // context, borrowed decode input
done(c) -> ()
ok(c) -> usize                            // 0/1
enter(c) -> usize                         // item + nesting charge, 0/1
leave(c) -> ()
collection(c, count: usize) -> usize      // preflight remaining item budget
check_bytes(c, len: usize, kind: usize) -> usize // encode preflight before SDK copy
check_bigint(c, len: usize) -> usize      // encode preflight before SDK copy
finish(c) -> ()                          // require all decode input consumed
error_part(c, part: usize) -> usize      // 0 kind ptr, 1 kind len, 2 offset
fail(c, code: usize) -> ()               // 1 missing, 2 variant, 3 canonical,
                                        // other type
read_header(c) -> ()                     // require ASCII ICW1
write_header(c) -> ()                    // append ASCII ICW1
output_part(c, part: usize) -> usize     // 0 ptr, 1 len
scalar_part(c, part: usize) -> usize     // 0 ptr, 1 len, borrowed last bytes/LEB;
                                       // bigint: 2 small flag, 3 word bits
read_bool(c) -> usize                   // byte 0 or 1, also option tag
write_bool(c, value: usize) -> ()        // byte 0 or 1, also option tag
read_word(c, signed: usize, bits: usize) -> u64  // bits 8,16,32,64; sign extend
write_word(c, value: u64, bits: usize) -> ()    // low bits, little endian
read_char(c) -> usize                   // validated Unicode scalar, u32 LE
write_char(c, value: usize) -> ()
read_float(c, bits: usize) -> f64        // 32 or 64, finite only
write_float(c, value: f64, bits: usize) -> ()
read_bytes(c, kind: usize) -> ()         // 0 Blob, 1 UTF-8 Text, 2 Principal <=29
write_bytes(c, ptr: usize, len: usize, kind: usize) -> ()
read_bigint(c, signed: usize) -> ()      // borrowed canonical ULEB/SLEB
write_bigint(c, ptr: usize, len: usize, signed: usize) -> ()
write_small(c, value: u64, signed: usize) -> () // minimal ULEB/SLEB without SDK Blob
read_array(c) -> usize                  // u32 count + item preflight
write_array(c, count: usize) -> ()       // item preflight + u32 count
write_start(c) -> usize                 // append u32 length placeholder; position
write_field(c, tag: usize) -> usize      // charge item, append tag + placeholder
write_end(c, position: usize) -> ()      // backpatch payload length after placeholder
record_start(c) -> ()                   // read bounded u32 record length; push frame
record_next(c) -> usize                 // 1: next bounded field; 0: pop at record end
field_tag(c) -> usize                   // current field's u32 hash
field_end(c) -> ()                      // require known field consumed exactly
field_skip(c) -> ()                     // skip unknown field directly to its boundary
```

Generator calls `enter`/`leave` for each typed node, `collection` before allocating
arrays, and `field_end` after every known record field. `record_next` validates
strictly increasing unsigned tags and charges one item per field, including
unknown fields. `write_field` applies the same item charge when encoding.
`field_skip` handles unknown fields without parsing their bytes.
`record_next` pops its frame when returning 0 at normal end; a failed context
does not need balanced cleanup. Decode field values cannot cross their boundary.

Null/unit encode zero bytes. Tuples concatenate elements. Variants use ordinary
32-bit `read_word`/`write_word` for their label hash then the payload. Optional
record fields whose value is null are omitted by the generator; an explicitly
encoded absent option is rejected with `fail(c, 3)`. `record_next` returning 0
does not itself check required fields; the generator uses `fail(c, 1)`.

Limits: total bytes 16 MiB including header; nodes plus record fields 1,000,000;
typed nesting depth 128; canonical integer LEB at most 4096 bytes. Error kinds:
`header`, `truncated`, `trailing`, `limit`, `canonical`, `bool`, `char`, `float`,
`utf8`, `principal`, `length`, `missing`, `variant`, `type`. Offsets are absolute
byte positions in input (encode errors use output position), at the start of the
invalid scalar/header, the failed read, or the current cursor for structural
errors. `new` rejects oversized input at offset 0.

After successful `read_bigint`, `scalar_part(c, 2)` is 1 for at most nine LEB
bytes, and part 3 contains the decoded word (SLEB sign-extended to 64 bits).
Part 0/1 remain available for larger managed integers. A failed read resets the
small flag. Integer truncation points to the missing byte; integer limit and
canonical errors point to the first byte. Byte lengths above 16 MiB are rejected
as `limit` at the length prefix before principal validation or payload access.
