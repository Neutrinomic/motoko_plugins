# ICWire

Compiler-specialized binary encoding and decoding for immutable Motoko data.
Messages contain only their typed payload: no magic prefix, type table, record
field identifiers or record framing. Writers and readers must share the exact
wire schema.

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
`ICWire.encodeBounded(value, maxBytes)` returns the same result and exactly the
same bytes, using a caller-provided bound on the complete encoded payload.
`maxBytes` is a `Nat` from zero through 16 MiB. Exceeding it returns `#err` with
kind `limit` at the first value that does not fit; a bound above 16 MiB returns
`limit` at offset zero. A bound is a total byte capacity, not a schema with
separate maxima for individual fields, strings or arrays.

For composite variable-size values, bounded encoding writes in one traversal
into unpublished capacity, checks byte, node, depth and scalar limits while
writing, and finalizes the Blob at its actual length. It never pads the wire
message to the bound. Reserved capacity counts toward allocation until GC;
finalization makes its unused tail reclaimable but does not rewind the heap.
Choose a close, independently known bound and measure the relevant workload. Calling
`estimateSize` solely to supply the bound still traverses the value first.
Scalar and fixed-width roots retain cheap exact sizing and allocation, where
a capacity reservation would not remove a traversal. The ordinary encoder
remains appropriate when the size bound is unknown or excessively loose.

`ICWire.decode<T>(bytes)` requires an explicit concrete result type and returns
`ICWire.Result<T>`. The result is `{#ok : T; #err : ICWire.Error}`, with
`Error = {kind : Text; offset : Nat64}`. Decode offsets are byte offsets into
the complete input; encoding errors use the output position. Expected
malformed-input and resource-limit failures return `#err`; platform allocation
exhaustion remains a platform failure. The first error is retained.

`ICWire.unwrap(result)` extracts the successful value and traps with the error
kind and byte offset on failure. `ICWire.toOption(result)` converts success to
`?value` and failure to `null`. These ordinary generic helpers operate on the
result after the codec intrinsic has specialized at the concrete call site.

`ICWire.estimateSize(value)` returns the exact encoded byte size without
encoding or allocating scratch storage. Fixed-width arrays use only their
count. Signed integer sizing borrows the magnitude without temporary values.
It returns `2 ** 61 - 1` if a byte, node, depth or integer bound is exceeded.
Float values are sized without checking finiteness; `encode` still rejects
NaN and infinity. This is an admission size bound, not an encodability check.

The intrinsics specialize at each call; use an explicitly typed Motoko wrapper
when an encoder or decoder is needed as an ordinary function value. One call
encodes or estimates one value. Use `encode((a, b))` for a tuple and
`encode(())` for unit; the same parentheses apply to `estimateSize`.
The API provides no schema registry, method dispatch, transport or Candid
conversion.

## Wire contract

The requested type determines how to read each payload. Fixed-width words use
little-endian byte order. Lengths, element counts and variant ordinals use
minimal unsigned LEB128, bounded to 32 bits; the resource limits below are
checked before allocation or traversal.

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
| `Blob` | Unsigned LEB128 byte length followed by those bytes |
| `Text` | Unsigned LEB128 UTF-8 byte length followed by valid UTF-8 |
| `Principal` | Unsigned LEB128 byte length followed by at most 29 principal bytes |
| Actor reference | The same principal-byte representation |
| Shared function reference | Actor principal followed by the method name as `Text` |
| `?T` | One byte `0` for null, or `1` followed by the payload of `T` |
| `[T]` | Unsigned LEB128 element count followed by consecutive element payloads |
| Tuple | Consecutive element payloads, without a count |
| Record | Consecutive field payloads in the compile-time order below |
| Variant | Unsigned LEB128 case ordinal followed by its typed payload |

Record fields and variant cases are sorted by their unsigned Candid label
identity at compilation. No identity bytes are transmitted. Motoko's label
convention applies: `_123_` denotes numeric identity 123; other names drop one
trailing escape underscore, if present, before hashing. The hash starts at zero
and, for each UTF-8 label byte, multiplies by 223 and adds the byte, modulo 2^32.
Collisions within a record or variant are rejected at compilation. Source
declaration order therefore does not affect bytes.

Every record field is encoded. In particular, a null optional field contributes
its `0` option byte; it is never omitted. Records add no count, length, tags or
field delimiters. Variant ordinals start at zero in the sorted case list, so
the first 128 cases each need only one discriminant byte. Nested options and
`?Null` preserve their ordinary `0`/`1` tags.

Shared references contain no signature or protocol tag. The static actor or
function type determines whether a call uses Candid or ICWire. Function
signatures, including recursive callback result types, are not traversed as
payloads. An actor reference charges one typed node; a shared function charges
its root plus its actor and method-name children. Decoding validates principal
length and UTF-8 exactly as for the corresponding scalar types.

Examples, in hexadecimal:

| Value and type | Bytes |
| --- | --- |
| `{x = 7 : Nat}` | `07` |
| `{a = 7 : Nat; b = null : ?Nat}` | `07 00` |
| `null : ?Nat` | `00` |
| `?null : ??Nat` | `01 00` |
| `()` or an empty record | Empty Blob |
| `"A" : Text` | `01 41` |
| `#z(7)` with type `{#a; #z : Nat}` | `01 07` |

## Schema agreement and deterministic bytes

Both endpoints must use the same scalar widths, field order, variant ordinals
and collection structure. The decoder validates a payload against its supplied
schema; without a runtime schema descriptor, it cannot establish that the sender
used that schema. Different types can produce identical bytes, and decoding
under a different schema may succeed with a different interpretation.

Adding an optional record field has no automatic compatibility behavior. It
adds an option byte even when null. Adding a variant case can renumber existing
cases, and renaming a field or case can change the sorted order. Changes to
types, field order or discriminants require explicit contract-version handling
at the application boundary. Message identity, authorization, version gates and
retained-message handling belong to the later transport integration. This
codec has no fallback reader, unknown-field projection or migration mechanism.

Encoding is deterministic for the supplied schema and value. Decoding rejects
nonminimal integers and lengths, invalid booleans/options, invalid UTF-8 and
Unicode scalars, non-finite floats, out-of-range variant ordinals, truncation and
trailing bytes. Canonical scalar rules are checked during decoding, without
re-encoding the value. Retain original encoded bytes for retries, hashes and
evidence, together with the contract identity needed to interpret them.

## Bounds and execution

Each call permits at most 16 MiB of encoded data, 1,000,000 visited typed values,
128 nested typed values and 4,096 encoded bytes per arbitrary precision integer.
Options, records, arrays, tuples and zero-byte values count as typed visits;
record fields have no separate framing charge. Array lengths are admitted
before allocating their managed storage, including arrays of unit values.
Byte lengths are checked against the remaining input before access or copying.
Callers can enforce lower application payload limits.

Encoding first measures the exact output size and admits values against the
byte and item limits. Finite schemas use compile-time depth bounds; recursive
or deeper schemas track the actual visited depth during measurement.
It then allocates the final Blob once and writes directly into it, including
text ropes and arbitrary precision integers through compiler stream helpers.
The successful common path has no intermediate output vector or per-integer
Blob bridge. Compact integers use generated width-specific packed stores.
Fixed-width arrays, including floats, use their count during size admission.
Float finiteness is checked while writing. If measurement or writing
rejects a value, a bounded streaming visitor reports the first error and its
precise output position. Any partially written Blob remains unpublished.
`encodeBounded` skips whole-value measurement for variable-size composites.
Its byte-capacity checks use the supplied bound without weakening the global
node, depth or integer limits. The compiler owns unpublished Blob allocation
and finalization, including GC filler objects and the allocation barrier;
the plugin never changes a managed Blob header directly. Failed output is
finalized and discarded before diagnostic fallback.

Decoding borrows input slices and constructs ordinary managed Motoko values
directly. Primitive admission and decoding are combined. Boolean, fixed-width
integer and floating-point arrays validate their input before constructing
the array through direct loads. Larger integers construct their final managed
magnitude directly from the validated bytes without intermediate arithmetic
values. These specializations
favor instruction cost over generated-code size and temporary allocation;
the benchmark reports both. The compiler owns heap layouts, allocation and
GC barriers. Calls are
synchronous, retain no input pointers or plugin state, and have no callbacks
or GC safepoints. Temporary buffers used by the streaming encoder, unpublished
output Blobs and abandoned decoded values are reclaimed by normal Motoko GC.

Supported compositions include recursive immutable records, variants, arrays,
actors and shared function references under these dynamic limits. Mutable
values, local functions, `Any`
and runtime handles are rejected during compilation. Both float widths reject
NaN and infinity on encoding and decoding.

## Benchmarks

The [codec benchmark suite](../../benchmarks/icwire/README.md) compares IC
instruction counts, allocation and output sizes with native Candid and CandidX
on scalar, array, Blob, Takt, Rechain and Reactor-shaped payloads. It retains
source/artifact hashes, raw observations, optimization passes and reproduction
commands. Reports identify their wire format; archived measurements of the
earlier tagged format do not describe the current raw positional codec.
These compare complete codecs with different contracts; application throughput
is a separate measurement.

## Relationship to Rust IC Wire

The design follows [dragginzgame/ic-wire](https://github.com/dragginzgame/ic-wire)'s
use of typed binary contracts for controlled peers. The reviewed source is
[revision `9e336f402258cccdb1433e44f8c8b07b65f93756`](https://github.com/dragginzgame/ic-wire/tree/9e336f402258cccdb1433e44f8c8b07b65f93756).
Its [runtime contract](https://github.com/dragginzgame/ic-wire/blob/9e336f402258cccdb1433e44f8c8b07b65f93756/crates/ic-wire/README.md)
uses canonical Postcard payloads, optionally wrapped with `IW`, a method ID
and a request/response direction. This implementation similarly depends on
schema agreement for positional records. It retains fixed-width Motoko words,
arbitrary `Nat` and signed-LEB128 `Int`, and derives variant ordinals from
Motoko's sorted labels.

**This format is not byte-compatible with Rust IC Wire, Postcard, Candid or
CandidX.** Adopting it in existing applications requires an explicit change at
the owned message boundaries; importing the module does not rewrite public
actor interfaces or existing libraries.
