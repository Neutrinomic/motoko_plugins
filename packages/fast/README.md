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

`Map` and `Set` expose every function from their `mo:core` counterparts,
including implicit comparator and formatter arguments. Their `toPure` and
`fromPure` conversions use Core’s pure Map/Set types, matching Core’s interface.
These two modules use the declared `core` dependency; other modules import only
`Prim`. Conversions rebuild the tree while sharing keys, values, and elements.

Both pure modules also provide Core’s function interfaces, with additional
operations. The plugin containers have different storage representations from
Core: changing an import does not migrate existing stable data or make Core
and Fast container values interchangeable. In particular, mutable conversions
return Core’s pure types, not `mo:fast/pure/Map` or `mo:fast/pure/Set`.

Native key operations reached through ordinary calls such as
`Map.get(map, Nat64.compare, key)` automatically use native ordering when the compiler proves the comparator's scalar semantics.
Passing the same comparator through aliases, record fields, or generic
functions keeps this optimization. Unrecognized comparators, including effectful
comparators, preserve normal callback behavior; `Float.compare` also remains a callback. Explicit
helpers such as `getNat64` remain optional. Recognition depends on the function
body, never just its name or the key type. Comparisons in ordinary Motoko
traversal code keep their usual calling convention.

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
import Nat "mo:core/Nat";

let mutable = Map.empty<Nat, Text>();
Map.add(mutable, Nat.compare, 42, "answer");
assert Map.get(mutable, Nat.compare, 42) == ?"answer";

let original = PureMap.empty<Nat, Text>();
let updated = PureMap.add(original, Nat.compare, 42, "answer");
assert PureMap.get(original, Nat.compare, 42) == null;
assert PureMap.get(updated, Nat.compare, 42) == ?"answer";
```

The maps retain their Core-style interfaces and typed shared payloads. See
the [mutable map](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/mutable-map)
and [pure map](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/pure-map)
API documentation, including comparator and iterator contracts.

```motoko
import Set "mo:fast/Set";
import PureSet "mo:fast/pure/Set";
import Nat "mo:core/Nat";

let mutable = Set.empty<Nat>();
assert Set.insert(mutable, Nat.compare, 42);
assert not Set.insert(mutable, Nat.compare, 42);
assert Set.contains(mutable, Nat.compare, 42);

let original = PureSet.empty<Nat>();
let updated = PureSet.add(original, Nat.compare, 42);
assert PureSet.isEmpty(original);
assert PureSet.contains(updated, Nat.compare, 42);
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
