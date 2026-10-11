# CBOR

Typed CBOR encoding and decoding without a generic value tree or Candid round trip.

```motoko
import Prim "mo:⛔";

type User = {id : Nat64; name : Text; active : Bool};
let encoded = Prim.to_cbor({id = 42 : Nat64; name = "Ada"; active = true});
switch encoded {
  case (#ok bytes) {
    let decoded = Prim.from_cbor<User>(bytes);
  };
  case (#err error) { /* error.kind, message, path, offset */ };
};
```

```sh
moc --plugin ../../dist/cbor app.mo
```

`to_cbor(value)` returns `{#ok : Blob; #err : CborError}`.
`from_cbor<T>(blob)` returns `{#ok : T; #err : CborError}` where
`CborError = {kind : Text; message : Text; path : Text; offset : Nat64}`.
The explicit output type supplies record names and scalar ranges. Error paths
use JSON Pointer escaping (`~0`, `~1`); offsets count input bytes from zero and
are zero for encoding errors. Expected input errors return `#err`; platform
out-of-memory failures remain platform failures.

## Representation

| Motoko | CBOR |
|---|---|
| `Bool`, `Null`, `Text` | Boolean, null, UTF-8 text string |
| Fixed-width integers, `Nat`, `Int` | Integer; tag 2 or 3 for values outside CBOR's direct integer range |
| `Float`, `Float32` | Shortest exact binary16, binary32, or binary64 float |
| `Blob` | Byte string |
| `Principal` | Untagged byte string, at most 29 bytes |
| `Char` | Text string containing one Unicode scalar |
| Arrays, tuples, `()` | Array, fixed-length array, empty array |
| Records | Map with source field names as text keys |
| `#case(payload)` | One-entry map `{"case": payload}`; a bare case has an empty-array payload |
| Optional | Null or the payload; nested/null optional payloads use `{"some": payload}` |

For example, `null : ??Nat`, `?null : ??Nat`, and `??7 : ??Nat` remain distinct.
`Nat8` arrays remain CBOR arrays; use `Blob` for byte strings. Principal bytes
are distinguished by the requested Motoko type; no private CBOR tag is used.

The encoder implements the [RFC 8949 core deterministic encoding rules](https://www.rfc-editor.org/rfc/rfc8949.html#section-4.2.1):
shortest integer/length heads, definite lengths, and lexicographically ordered
encoded map keys. Because record keys are text, their order is UTF-8 byte length
then bytewise value. Integers keep their type distinct from floats. Negative
zero is preserved; NaNs use the single encoding `f9 7e 00`; infinities use
binary16. Bignums use tags 2/3 only when needed and have no leading zero bytes.

The decoder accepts nonpreferred definite-length encodings, unsorted record
fields, and bignums with redundant leading zeros. It validates UTF-8, integer
ranges, tuple lengths, variant cases, and duplicate text keys, including keys
inside ignored unknown fields. Missing optional fields become `null`; missing
required fields return `#err`. Float64-to-Float32 conversion rounds to binary32
and rejects finite overflow. Floats and integers do not implicitly convert into
each other. Trailing bytes are rejected.

This is a typed application profile, not a general CBOR tree API. Indefinite
lengths, maps with non-text keys, undefined/other simple values, and tags other
than 2/3 return `#err`, including inside unknown fields. Functions, actors,
mutable data, `Any`, and runtime handles are rejected at compile time.

## Bounds and memory

Each call permits at most 16 MiB of encoded data, 1,000,000 visited values,
128 nested typed values, and 4,096 bytes of bignum magnitude. Options count as
visited values. Declared array/map lengths are checked against remaining input
and item budgets before allocation. Oversized integer bridges and text ropes
are rejected before conversion or flattening.

The compiler owns Motoko layouts and managed allocation. The runtime borrows
input string/blob slices while decoding and writes directly to an ephemeral
output buffer while encoding. Arrays allocate their final managed size from
the CBOR length; there is no counting pass. Calls have no GC safepoints,
callbacks, persistent plugin memory, or retained input pointers. Temporary
buffers and abandoned managed values after errors are reclaimed by the normal
Motoko GC. Results are ordinary managed Motoko values.

The tests cover RFC encodings, every binary16 bit pattern, signed and large
integer bridges, decoder diagnostics, quotas, interpreter/Wasm parity, and
retained results and early decode errors across forced GC.
