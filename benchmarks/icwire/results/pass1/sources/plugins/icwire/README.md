# ICWire

Compiler-specialized binary encoding and decoding for immutable Motoko data.
The compiler supplies the schema; encoded messages carry values and stable
field identities without a runtime type table.

```motoko
import ICWire "mo:fast/ICWire";

type Request = { id : Nat; owner : Principal; memo : ?Text };
let request : Request = { id = 42; owner = principal "aaaaa-aa"; memo = null };
switch (ICWire.encode(request)) {
  case (#ok bytes) {
    assert ICWire.decode<Request>(bytes) == #ok request;
  };
  case (#err error) { /* error.kind, error.offset */ };
};
```

Build and load the `icwire` plugin with the matching compiler:

```sh
scripts/build.sh --motoko /path/to/motoko icwire
/path/to/motoko/bin/moc --package fast packages/fast/src \
  --plugin dist/icwire app.mo -o app.wasm
```

`ICWire.encode(value)` returns `ICWire.Result<Blob>`.
`ICWire.decode<T>(bytes)` requires an explicit concrete result type and returns
`ICWire.Result<T>`. The result is `{#ok : T; #err : ICWire.Error}`, with
`Error = {kind : Text; offset : Nat64}`. Decode offsets are byte offsets into
the complete input; encoding errors use the output position. Expected
malformed-input and resource-limit failures return `#err`; platform allocation exhaustion remains
a platform failure. The intrinsics specialize at each call; use an explicitly
typed Motoko wrapper when an encoder or decoder is needed as an ordinary
function value.

Error kinds are `header`, `truncated`, `trailing`, `limit`, `canonical`, `bool`,
`char`, `float`, `utf8`, `principal`, `length`, `missing`, `variant` and `type`.
Offsets identify the invalid scalar's start, a failed read or the current cursor
for structural errors. The first error is retained.

One call encodes one value. Use `encode((a, b))` for a tuple and `encode(())`
for unit. There is no generic value tree, schema registry, method dispatch,
transport implementation or Candid conversion in this API.

## ICW1 wire contract

Each complete Blob starts with ASCII `ICW1` (`49 43 57 31` in hexadecimal),
followed by exactly one typed value. Nested values have no magic prefix.
Multi-byte fixed-width words and lengths use little-endian byte order.
The requested type determines how to read each payload; these bytes are not
self-describing.

| Motoko type | Payload representation |
| --- | --- |
| `Null`, `()` | Zero bytes |
| `Bool` | One byte: `0` or `1` |
| `Nat8`, `Nat16`, `Nat32`, `Nat64` | Unsigned fixed-width word of 1, 2, 4 or 8 bytes |
| `Int8`, `Int16`, `Int32`, `Int64` | Two's-complement fixed-width word of 1, 2, 4 or 8 bytes |
| `Nat` | Minimal unsigned LEB128 |
| `Int` | Minimal signed LEB128 |
| `Float32`, `Float` | Finite IEEE-754 binary32 or binary64; signed zero is preserved |
| `Char` | A Unicode scalar value as a u32; surrogate values are invalid |
| `Blob` | u32 byte length followed by those bytes |
| `Text` | u32 UTF-8 byte length followed by valid UTF-8 |
| `Principal` | u32 byte length followed by at most 29 principal bytes |
| `?T` | One byte `0` for null, or `1` followed by the payload of `T` |
| `[T]` | u32 element count followed by consecutive element payloads |
| Tuple | Consecutive element payloads, without a count |
| Record | u32 body byte length, followed by ordered field frames |
| Variant | u32 case identity followed by its typed payload |

A record field frame is `u32 identity | u32 payloadByteLength | payload`.
Identities use Motoko's Candid label convention: `_123_` denotes numeric identity
123; other names drop one trailing escape underscore, if present, before
hashing. Start the hash at zero and, for each UTF-8 label byte, multiply by 223
and add the byte, modulo 2^32. Fields are ordered by ascending unsigned identity.
Record and variant hash collisions are rejected at compilation. Source
declaration order does not affect the bytes.

Null optional record fields are omitted. Present optional fields retain their
`1` option tag, so nested options and `?Null` remain unambiguous. Required fields
are always encoded, including fields whose payload occupies zero bytes.
The record body length covers all field headers and payloads, excluding its
own four-byte length. Fixed-width lengths let the encoder fill them after
writing each field, without a preliminary sizing traversal or moving payloads.
The framing cost is four bytes per record plus eight bytes per present field.

For example, `{x = 7 : Nat}` encodes as:

```text
49 43 57 31  09 00 00 00  78 00 00 00  01 00 00 00  07
ICW1         body: 9       hash("x")     field: 1     Nat 7
```

`null : ?Nat` encodes as `49 43 57 31 00`, while `()` encodes as
`49 43 57 31`. An empty record additionally carries its zero body length.

## Evolution and deterministic bytes

Adding an optional record field preserves existing readers and writers.
Readers skip unknown fields using their bounded payload lengths and initialize
absent optional fields to null. Encoding a newly added field as null preserves
the bytes of the old record. Existing fields keep their names, types and
semantics. Renaming a field changes its identity; changing a payload type is
not an evolution rule, even when a particular value happens to occupy the
same bytes.

Variant identities are label hashes rather than positions in a case list.
Adding a case therefore preserves all existing case tags. A decoder rejects an
unknown case; a transport can retain a message until its required reader version
is available. Method identity, authorization and reader-version gates belong to
the application. `ICW1` identifies this encoding profile, not a message schema
or authenticated producer. Use the intended concrete type at every boundary.

Encoding is deterministic for the supplied type and value. Decoding rejects
nonminimal integers, invalid booleans/options, unordered or duplicate record
identities, invalid UTF-8, invalid scalar values, non-finite floats, missing
required fields, incorrectly framed payloads and trailing bytes. It checks
canonical scalar and framing rules while decoding, without re-encoding the
value. Opaque unknown field payloads are skipped; their internal encoding
cannot be validated without their schema. Consequently, decoding a projection
does not establish canonicality of every byte in an unknown field, and
re-encoding that projection discards unknown fields. Retain original encoded
bytes for retries, hashes and evidence.

## Bounds and execution

Each call permits at most 16 MiB of complete encoded data, 1,000,000 visited
values and record-field frames, 128 nested typed values and 4,096 encoded bytes
per arbitrary precision integer. Options and zero-byte values still count
toward traversal limits. Array lengths are admitted before allocating their
managed storage,
including arrays of unit values. Record frames and byte lengths are checked
against their enclosing input boundary before copying, skipping or decoding.
These are codec limits; callers can enforce lower application payload limits.

The compiler owns Motoko heap layouts, allocation and GC barriers. The Rust
runtime borrows input slices and writes into an ephemeral output buffer during
one synchronous call. The generated visitor constructs ordinary managed Motoko
values directly. Calls retain no input pointers or plugin state and have no
callbacks or GC safepoints. Temporary buffers and abandoned decoded values are
reclaimed by normal Motoko GC.

Supported compositions include recursive immutable records, variants and
arrays under these dynamic limits. Mutable values, functions, actors, `Any`
and runtime handles are rejected during compilation. Both float widths reject
NaN and infinity on encoding and decoding; this is deliberately narrower than
Candid's float value domain.

## Relationship to Rust IC Wire

The design follows [dragginzgame/ic-wire](https://github.com/dragginzgame/ic-wire)'s
use of typed binary contracts for controlled peers. The reviewed source is
[revision `9e336f402258cccdb1433e44f8c8b07b65f93756`](https://github.com/dragginzgame/ic-wire/tree/9e336f402258cccdb1433e44f8c8b07b65f93756).
Its [runtime contract](https://github.com/dragginzgame/ic-wire/blob/9e336f402258cccdb1433e44f8c8b07b65f93756/crates/ic-wire/README.md)
uses canonical Postcard payloads, optionally wrapped with `IW`, a method ID
and a request/response direction. Its positional records cannot add optional
fields compatibly. This Motoko implementation uses tagged record frames to
support that evolution, retains Motoko's arbitrary `Nat` and `Int`, and checks
canonical scalar encodings directly during decoding.

**ICW1 is not compatible with Rust IC Wire, Postcard, Candid or CandidX bytes.**
It introduces a separate encoding contract. Adopting it in existing applications
requires an explicit change at the owned message boundaries; public actor
interfaces and existing libraries are not rewritten by importing the module.
