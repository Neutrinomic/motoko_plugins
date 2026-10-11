# JSON

Typed JSON encoding and decoding as a standalone Motoko compiler plugin.
The compiler specializes visitors for your Motoko types; a linked Wasm kernel
handles JSON syntax, escaping, numeric conversion, and buffering.

```sh
moc --package fast /path/to/motoko_plugins/packages/fast/src \
    --plugin /path/to/motoko_plugins/dist/json main.mo
```

```motoko
import JSON "mo:fast/JSON";

type User = { name : Text; age : Nat8; nickname : ?Text };

let parsed = JSON.decode<User>("{\"name\":\"Ada\",\"age\":36}");
switch parsed {
  case (#ok user) {
    let encoded : JSON.Result<Text> = JSON.encode(user);
  };
  case (#err error) {
    // error.kind, error.message, error.path, error.offset
  };
};
```

Both operations return ordinary managed Motoko variants:

```motoko
// JSON.Error = {
//   kind : Text;
//   message : Text;
//   path : Text;   // JSON Pointer; "" identifies the root
//   offset : Nat64; // UTF-8 byte offset; zero when encoding
// }
// JSON.encode(value) : JSON.Result<Text>
// JSON.decode<T>(text) : JSON.Result<T>
```

`JSON.decode<T>` requires an explicit result type. Unsupported types are rejected
at compile time. Supply one value to `JSON.encode`; parenthesize a tuple argument
(`JSON.encode((tupleValue))`).

## Mapping

| Motoko | JSON |
| --- | --- |
| `Null`, `Bool`, `Text` | `null`, boolean, string |
| `Nat`, `Int`, `Nat64`, `Int64` | Decimal strings, preserving every integer bit |
| `Nat8/16/32`, `Int8/16/32` | Integer numbers, checked against the requested range |
| `Float`, `Float32` | Finite numbers; `"NaN"`, `"Infinity"`, `"-Infinity"` for nonfinite values |
| `Char` | String containing one Unicode scalar |
| `Blob` | Standard padded base64 string |
| `Principal` | Canonical principal text string |
| Immutable record | Object with the original Motoko field names |
| Variant `#case(payload)` | `{"case": payload}` |
| Array, tuple | Array; unit `()` is `[]` |
| `?T` | `null` or the encoded payload |
| `?T` when `T` is optional or `Null` | `null` or `{"some": payload}` |

The tagged option rule preserves distinctions such as `null`, `?null`, and
`??null`. A variant without a payload therefore encodes as `{"case":[]}`.
Record keys are emitted in source-name lexical order. A name such as `_42_`
is emitted literally; Candid numeric-field escaping does not apply.

Integer decoders also accept exact integer number tokens for the four types
encoded as strings. They never route integers through floating point. Smaller
integer types reject strings; all integer types reject fractions, exponents,
leading zeros, and out-of-range values. Finite float output uses 17 significant
decimal digits for repeatable round trips, including negative zero. Decimal
`Float32` input is rounded directly to binary32.

Unknown object fields are ignored after validation. Missing optional fields
become `null`; missing required fields and duplicate object keys return `#err`.
Duplicate checking also applies inside ignored fields. Tuples require the
exact length; variants and tagged options require exactly one object field.
Records, variants, arrays, and options can be recursive. Functions, actors,
mutable arrays/fields, `Any`, and runtime handles are unsupported.

## Limits and memory

Each call permits 16 MiB of JSON, 1,000,000 visited values, depth 128, and
4,096 decimal digits per arbitrary-precision integer. Limits return `#err`.
Error kinds are `syntax`, `type`, `range`, `missing`, `duplicate`, `base64`,
`principal`, and `limit`. Offsets identify where the reader detected the error.
Arrays receive a bounded syntax pre-scan before decoding, so array syntax
errors take precedence over errors converting their elements.

The Wasm path reads typed Motoko values directly and builds managed results
using the compiler's allocation and write barriers. It does not build a
generic JSON tree or serialize structures through Candid. Array decoding
counts elements before allocating the final Motoko array. Scratch storage
belongs to one synchronous call and is reclaimed by Motoko's GC; no plugin
state persists between calls. Input pointers are borrowed without GC
safepoints. Platform instruction limits and out-of-memory failures still
follow normal canister behavior.

Tests cover scalar boundaries, Unicode, recursive data, options, malformed
JSON, quotas, source/IR/Wasm agreement, and keeping decoded records, arrays,
bignums, and errors alive across forced GC and heap evacuation.

The public module is distributed in the [`fast` Mops package](../../packages/fast/).
