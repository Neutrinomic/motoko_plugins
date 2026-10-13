# fast

Motoko modules backed by native compiler plugins. Import the module you need;
its calls specialize directly to the plugin implementation.

| Import | API | Required compiler plugin |
|---|---|---|
| `mo:fast/CandidX` | `encode(...)` → `#ok Blob` / `#err Text`; `estimateSize(...)` → conservative `Nat` | `candidx` |
| `mo:fast/JSON` | `encode(value)`, `decode<T>(text)` | `json` |
| `mo:fast/CBOR` | `encode(value)`, `decode<T>(bytes)` | `cbor` |
| `mo:fast/SHA256` | `digest(bytes)` → 32-byte Blob | `sha256` |
| `mo:fast/BLAKE3` | Hash, keyed hash, context derivation, streaming, XOF | `blake3` |
| `mo:fast/SHA512` | SHA-512/SHA-384 digest and streaming | `sha512` |
| `mo:fast/RIPEMD160` | Digest and streaming | `ripemd160` |
| `mo:fast/HMAC` | HMAC-SHA256/SHA512, prepared keys, streaming | `hmac-sha2` |
| `mo:fast/Secp256k1` | Key operations, deterministic ECDSA, BIP340 Schnorr, tweaks | `secp256k1` |
| `mo:fast/P256` | P-256 keys, deterministic ECDSA and signature encoding | `p256` |
| `mo:fast/Base58` | Bitcoin alphabet encode/decode | `base58` |
| `mo:fast/Base58Check` | Base58 with a double-SHA256 checksum | `base58`, `sha256` |
| `mo:fast/Bech32`, `mo:fast/Segwit` | Bech32/Bech32m and witness addresses | `bech32` |
| `mo:fast/BLS12381` | G1/G2, MSM, hash-to-curve, pairings and IC/Ethereum verification | `bls12-381` |
| `mo:fast/Map` | Mutable ordered map | `mutable-map` |
| `mo:fast/pure/Map` | Persistent ordered map | `pure-map` |
| `mo:fast/Set` | Core-compatible mutable ordered set | `mutable-set` |
| `mo:fast/pure/Set` | Persistent ordered set with rank/select and split/join | `pure-set` |
| `mo:fast/Queue` | Core-compatible mutable double-ended queue | `queue` |
| `mo:fast/HistoryRing` | Bounded history indexed by absolute sequence | `history-ring` |
| `mo:fast/IndexedPriorityQueue` | Mutable priority queue with cancellation and rescheduling handles | `indexed-priority-queue` |

The cryptographic APIs use `Blob` for bytes. Each primitive module loads only
its own plugin; HMAC and curve signing include their internal hash operations.
Streaming state is held in managed Motoko values, and a digest can be finalized
without consuming its saved state. Individual modules document malformed-input
errors, output/batch limits, scalar byte order, and signature encoding.

`BLS12381` distinguishes the IC profile (G1 signatures, G2 keys) from the
Ethereum proof-of-possession profile (G2 signatures, G1 keys). Its aggregate
verification functions enforce their respective distinct-message or
proof-of-possession requirements. These are local cryptographic operations;
full certificate/delegation verification and threshold-signing protocols are
separate layers.

The Bitcoin modules assemble the primitives into complete operations:

| Import | Operations | Required compiler plugins |
|---|---|---|
| `mo:fast/Bitcoin/Hash` | HASH160, double-SHA256, tagged hashes | `sha256`, `ripemd160` |
| `mo:fast/Bitcoin/Bip32` | Parse/serialize extended public keys; derive public children and paths | `sha256`, `ripemd160`, `hmac-sha2`, `secp256k1`, `base58` |
| `mo:fast/Bitcoin/Address` | Legacy, SegWit and Taproot addresses; local Taproot key-path signing | `sha256`, `ripemd160`, `secp256k1`, `base58`, `bech32` |
| `mo:fast/Bitcoin/Script` | Script serialization, pushdata and Taproot leaf helpers | `sha256` |
| `mo:fast/Bitcoin/Transaction` | Transaction serialization, txid/wtxid, legacy/BIP143/BIP341 sighashes | `sha256` |

These modules are composed Motoko libraries rather than another native plugin.
See the source API comments and public test vectors for exact transaction and
address types. [Crypto benchmarks](../../benchmarks/crypto/) distinguish
primitive costs from full address, key-derivation and transaction workflows.

`Map` and `Set` expose every function from their `mo:core` counterparts,
including implicit comparator and formatter arguments. Their `toPure` and
`fromPure` conversions use Core’s pure Map/Set types, matching Core’s interface.
These two modules and `Queue` use the declared `core` dependency for their
conversions. Conversions rebuild the container while sharing keys, values, and
elements.

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

## Queues and retained history

[`Queue`](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/queue)
provides Core's mutable Queue interface, including both ends and conversions to
Core's pure Queue. Its lazy chunks share the original payloads. Removing an
element clears its slot. It retains at most one empty chunk for reuse;
`clear` releases all its storage. `toArray` and `toVarArray` copy directly into
one result array while sharing payloads. As with the maps and sets, Core and
Fast Queue values have different representations.

The current Queue packs chunk position and count into one field, replacing the
earlier experimental `start`/`count` fields. This changes its stable storage
shape: queues stored in that earlier format need explicit migration or
recreation. There is no legacy-format adapter; upgrade tests cover queues
created in the current format.

[`HistoryRing`](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/history-ring)
retains the latest entries up to a fixed capacity. `append` returns an absolute
`Nat` sequence, and `get` and `page` address entries by that sequence without
scanning an older prefix. Storage grows lazily, so a large configured capacity
does not allocate all its element slots at construction.

```motoko
import HistoryRing "mo:fast/HistoryRing";

let history = HistoryRing.empty<Text>(2);
let first = HistoryRing.append(history, "started");
ignore HistoryRing.append(history, "waiting");
ignore HistoryRing.append(history, "completed");
assert HistoryRing.get(history, first) == null;
assert HistoryRing.page(history, first, 10) == ["waiting", "completed"];
```

Sequences start at zero and are arbitrary-precision `Nat` values. Removing
entries or clearing the ring preserves the next sequence. Capacity zero retains
no entries but still advances it. `page` includes its starting sequence and
clamps evicted starts to the oldest retained entry. Use
`emptyAt(capacity, nextSequence)` to start an empty history at an existing
sequence when copying retained data. Partial drops release empty chunks but
retain the directory's high-water length until the ring becomes empty or is
cleared.

Both containers remain stable when their elements are stable. Their public
representation fields are private by contract. Mutation invalidates iterators;
traversal callbacks must not structurally mutate the container being traversed.

## Cancellable priorities

[`IndexedPriorityQueue`](https://github.com/Neutrinomic/motoko_plugins/tree/main/plugins/indexed-priority-queue)
is a mutable min-heap with generic priorities and values. `push` returns a
handle for `get`, `remove`, `reschedule`, or `replace`, without a second key
lookup. `peek` and `pop` return the minimum `(priority, value)` pair;
`peekPriority` reads only the priority without constructing that pair.
`entries` traverses heap order, not sorted order. Equal priorities have no FIFO
guarantee: include an explicit tie-breaker in the priority when order matters.

Handles belong to the queue that created them. Removal, popping, and clearing
invalidate them; stale operations return `null` or `false`. A live handle
retains its queue, while an invalidated handle releases that reference and
retains no payload. `clear` visits the entries to invalidate their handles.
The queue and its handles can be stable when their priority and value types
are stable.

Use the same comparator for every operation on a queue. As with Map and Set,
proven scalar comparators select native comparisons, and custom comparators
use normal Motoko callbacks. A callback must not structurally mutate the queue
being compared. It may read the evolving queue, but must not assume an
in-progress heap operation is atomic. Do not mutate a stored priority in a way
that changes its ordering. Mutation invalidates iterators.

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
