# fast

Motoko modules backed by native compiler plugins. Import the module you need;
its calls specialize directly to the plugin implementation.

| Import | API | Required compiler plugin |
|---|---|---|
| `mo:fast/CandidX` | `encode(...)` → `#ok Blob` / `#err Text` | `candidx` |
| `mo:fast/JSON` | `encode(value)`, `decode<T>(text)` | `json` |
| `mo:fast/CBOR` | `encode(value)`, `decode<T>(bytes)` | `cbor` |
| `mo:fast/SHA256` | `digest(bytes)` → 32-byte Blob | `sha256` |
| `mo:fast/Map` | Mutable ordered map | `mutable-map` |
| `mo:fast/pure/Map` | Persistent ordered map | `pure-map` |
| `mo:fast/Set` | Core-compatible mutable ordered set | `mutable-set` |
| `mo:fast/pure/Set` | Persistent ordered set with rank/select and split/join | `pure-set` |
| `mo:fast/CoreMap` | Mutable map ↔ `mo:core/pure/Map` conversions | `mutable-map` |

`CoreMap` and the mutable `Set` module use the declared `core` dependency for
conversions. Other modules import only `Prim`. Conversions rebuild the tree
while sharing elements, keys, and values. `Set.toPure`/`fromPure` use
`mo:core/pure/Set`, preserving Core's mutable Set interface; the separate
`mo:fast/pure/Set` has its own persistent representation.

## Use from a checkout

This package is not published to the Mops registry yet. Add a local dependency
to your application's `mops.toml`, adjusting the path to this checkout:

```toml
[dependencies]
fast = "../motoko_plugins/packages/fast"
```

Run `mops install`. Mops resolves the Motoko modules; you must also build and
load the matching native plugins with a compiler supporting
[Motoko PR #6443](https://github.com/caffeinelabs/motoko/pull/6443).
See the [build instructions](https://github.com/Neutrinomic/motoko_plugins#build-and-use).
For an application using only JSON:

```sh
moc $(mops sources) --plugin ../motoko_plugins/dist/json app.mo -o app.wasm
```

Or pass the source package directly:

```sh
moc --package fast ../motoko_plugins/packages/fast/src \
    --plugin ../motoko_plugins/dist/json app.mo -o app.wasm
```

Load only the plugins used by the imported modules. These native packages
must match the compiler build and host platform; a Mops version alone does
not establish native plugin compatibility. Native plugin binaries are built
separately and are not included in this source package.

```motoko
import JSON "mo:fast/JSON";

type User = { name : Text; age : Nat8; nickname : ?Text };
let decoded : JSON.Result<User> =
  JSON.decode<User>("{\"name\":\"Ada\",\"age\":37}");
switch decoded {
  case (#ok user) { assert JSON.encode(user) == #ok "{\"age\":37,\"name\":\"Ada\",\"nickname\":null}" };
  case (#err error) { /* error.kind, error.message, error.path, error.offset */ };
};
```

Both JSON and CBOR expose `Error` and `Result<T>` types. Decoding needs an
explicit concrete Motoko type; malformed data and conversion failures return
`#err`. Their full type mappings and limits are documented for
[JSON](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/json) and
[CBOR](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/cbor).

CandidX encodes zero or more arguments: `CandidX.encode(a, b)` and
`CandidX.encode((a, b))` encode two arguments and one tuple, respectively.
It returns `CandidX.Result` and currently provides encoding only.

```motoko
import Map "mo:fast/Map";
import PureMap "mo:fast/pure/Map";

let mutable = Map.empty<Nat, Text>();
Map.addNat(mutable, 42, "answer");
assert Map.getNat(mutable, 42) == ?"answer";

let original = PureMap.empty<Nat, Text>();
let updated = PureMap.addNat(original, 42, "answer");
assert PureMap.getNat(original, 42) == null;
assert PureMap.getNat(updated, 42) == ?"answer";
```

The maps retain their Core-style interfaces and typed shared payloads. See
the [mutable map](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/mutable-map)
and [pure map](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/pure-map)
API documentation, including comparator and iterator contracts.

```motoko
import Set "mo:fast/Set";
import PureSet "mo:fast/pure/Set";

let mutable = Set.empty<Nat>();
assert Set.insertNat(mutable, 42);
assert not Set.insertNat(mutable, 42);
assert Set.containsNat(mutable, 42);

let original = PureSet.empty<Nat>();
let updated = PureSet.addNat(original, 42);
assert PureSet.isEmpty(original);
assert PureSet.containsNat(updated, 42);
```

The [mutable Set](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/mutable-set)
exposes every Core mutable Set function, plus `find` and direct scalar helpers.
The [pure Set](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/pure-set)
shares unchanged branches when updated. Both store elements directly without
dummy map values. Elements remain shared Motoko references.

## Aliases and callbacks

The codec and hash exports are compiler intrinsic aliases: they add no
wrapper call and retain specialization at the caller's types. Inferred aliases
such as `let encode = JSON.encode` work. To store an operation in an ordinary
function-typed value or pass it as a callback, provide a concrete wrapper:

```motoko
import SHA256 "mo:fast/SHA256";

func hash(bytes : Blob) : Blob { SHA256.digest(bytes) };
let callbacks : [Blob -> Blob] = [hash];
```

Do not annotate an intrinsic alias with an ordinary function type or hide a
codec call behind an abstract generic wrapper; codecs need concrete types.

Instruction and allocation comparisons are in the
[repository README](https://github.com/Neutrinomic/motoko_plugins#readme).
The [Ash test guide](tests/ash/README.md) lists public API coverage and commands.
