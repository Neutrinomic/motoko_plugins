# Persistent ordered map

An immutable ordered map over ordinary Motoko heap nodes. A point update copies
only the changed AVL path and rotation nodes; unchanged children, keys and
values remain shared references. `clone` returns the same root. Removing an
absent key returns the original root without allocating tree nodes. Replacing
an absent key also returns it unchanged, and replacement reuses metadata along
the copied path. Multi-value results stay on the Wasm stack when destructured.

The plugin emits Wasm directly through the compiler SDK. It needs no separate
runtime module, Rust allocator, external pointers, or canister-owned plugin
state. Generic key/value types retain their real Motoko types. Integrated
search calls ordinary Motoko comparators through the compiler's closure calling
convention, and native scalar-order helpers avoid comparator dispatch when the
key order is known.

```motoko
import Map "mo:fast/pure/Map";

let original = Map.addNat<Text>(Map.empty(), 42, "answer");
let changed = Map.addNat(original, 7, "seven");
assert Map.getNat(original, 7) == null;
assert Map.getNat(changed, 42) == ?"answer";

func reverse(a : Nat, b : Nat) : Map.Order {
  if (a > b) #less else if (a == b) #equal else #greater
};
let custom = Map.add<Nat, Text>(Map.empty(), reverse, 7, "seven");
assert Map.get(custom, reverse, 7) == ?"seven";
```

Build and compile from the matching Motoko checkout's Nix shell:

```sh
../plugins/scripts/build.sh --motoko "$PWD" pure-map
bin/moc --plugin ../plugins/dist/pure-map \
  --package fast ../plugins/packages/fast/src app.mo -o app.wasm
```

The package uses ABI **1**. It must be built against the exact compatible native
compiler interfaces, like the other plugins. The public library is
[`mo:fast/pure/Map`](../../packages/fast/src/pure/Map.mo); applications normally use its functions rather
than the lower-level `Prim.pmap_*` intrinsics.

## API

| Family | Operations |
|---|---|
| Construction and size | `empty`, `singleton`, `size`, `isEmpty`, constant-time `clone` |
| Point operations | `get`, `getEntry`, `containsKey`, `add`, `swap`, `insert`, `replace`, `remove`, `delete`, `take`, `alter`, `update`, `insertWith` |
| Native scalar order | `getNat64`/`addNat64`/`replaceNat64`/`removeNat64`, and corresponding `Nat`, `Text`, `Blob` helpers |
| Order statistics | `rank`, `indexOf`, `select`, `lower`, `floor`, `ceiling`, `higher`, `minEntry`, `maxEntry`, `popMin`, `popMax` |
| Splits and ranges | `split`, `splitLookup`, checked `join`, `concatDisjoint`, `splitAt`, `takeRank`, `dropRank`, `rangeMap`, `removeRange`, `countInRange` |
| Iteration and snapshots | `entries`, `reverseEntries`, `entriesFrom`, `reverseEntriesFrom`, bounded forward/reverse iterators, `keys`, `values`, `snapshot`, `rangeSnapshot`, `replay` |
| Set operations | `union`, `unionWith`, `intersection`, `intersectionWith`, `difference`, `symmetricDifference`, `isDisjoint`, `isSubmap` |
| Callbacks and transforms | `map`, `mapKeys`, `filter`, `filterMap`, `partition`, `foldLeft`, `foldRight`, `foldValues`, `forEach`, `find`, `any`, `all`, `equal`, `compare`, `toText` |
| Bulk construction | `fromSortedDistinctArray`, `fromArray`, `fromIter`, `toMap`, `addList`, `toArray`, sorted `thaw`/`thawAppend`/`freeze` builder |
| Debugging | `assertValid`, `treeDepth`, `nodeCount` |

Every `mo:core/pure/Map` function is available with the same argument order,
result type, and implicit comparator/formatter parameters. `filter` and
`filterMap` accept Core’s comparator argument; preserving the tree’s ordering
does not require calling it. `equal` and `compare` take the two maps first.
The storage representation remains specific to this plugin. `add` replaces
both the stored key and value when comparator keys are equal. `swap`, `replace`, `take`, and `update` return the previous optional
value. `replace` does not insert a missing key. `alter` calls its update function
exactly once, after one comparator search, including for an absent key. An
optional value remains distinct from an absent binding: `?null` is a stored
`null`, while `null` means no entry.

An iterator uses a private mutable stack containing managed references. A
replayable snapshot contains only a root and rank bounds, so capturing a range
never copies its entries. Captured roots keep that version alive. Explicit
`toArray` materializes entries by request. Callback transformations that change
every binding must construct the resulting nodes; their allocation is O(n).
Cursor descent happens on demand, including the initial rank seek. Creating a
cursor still allocates its bounded stack and captures its complete snapshot.

## Representation and safety

The structural representation is
`?(height : Nat32, count : Nat, key : K, value : V, left : Map<K,V>, right : Map<K,V>)`.
It is intentionally ordinary Motoko data and is stable when its key and value
types are stable. The tuples are immutable and all edges use the normal compiler
forwarding/allocation barriers. Mutable payloads remain shared mutable payloads;
the map does not silently deep-copy them. Closures are valid transient values
and retain Motoko's usual stable-type restrictions.

Use one lawful, stable ordering for every operation on a map. Changing a stored
key's order through mutation invalidates its ordering. The native scalar helpers
use ascending Motoko order; do not use them with a map built under a different
comparator. The lower-level static intrinsics also support fixed integer types,
`Bool`, `Char`, and `Principal`. Floating-point keys require an explicit lawful
comparator, including a chosen NaN policy.

Application code can forge the structural map and builder types, which must
satisfy their invariants. Native traversals are depth-bounded; native traversal
and balancing kernels range-check the height/count metadata they consume, and
counts must fit a positive signed 64-bit word. They do not guarantee rejection
of every malformed tree. Direct accessors such as `size` and `treeDepth` trust
the stored metadata. Invalid depth and checked join/sorted-builder preconditions
trap. Hot operations do not
scan the entire tree to verify ordering and metadata: use `assertValid` when
accepting manually constructed data or in tests. Ordinary well-formed trees
cannot approach these bounds within the heap's capacity.

Callbacks are synchronous and may allocate, capture mutable state, or reenter
the plugin. The SDK uses normal Motoko calls and preserves actor context in both
interpreters. The current collector runs after synchronous message frames
return. Only managed references remain live across a callback; no borrowed
pointer or private allocator state is retained. This contract must be revisited
if the compiler introduces collection during synchronous local execution.

Point-update allocation grows with the path, not the total tree or payload
size. Retaining many independently edited versions retains their changed paths;
dropping those roots lets ordinary Motoko GC reclaim unreachable nodes. A live
iterator or snapshot also retains its captured version. Stable representation
changes and ordering changes require an explicit migration or rebuild.

## Validation and measurements

The tests use an independent sorted-array oracle, randomized branching histories,
AVL/count/order checks, callback counts and reentry, nested optional values,
mutable and closure payloads, and forced collection with retained versions.
The compiler's separate small fixtures validate opaque typing, callback arities,
static scalar boundaries, and zero-allocation multiargument calls.

PocketIC comparisons use the pinned `mo:core/pure/Map` and identical inputs in
the same canister. Core's map already shares unchanged branches. Instruction
and allocation gains therefore come from representation, generated operations,
and algorithms rather than removing a full-map clone. See the repository
[performance table](../../README.md) and [benchmark instructions](../../benchmarks/README.md)
for the measured workload scope and reproducible reports.
The [optimization-round report](../../benchmarks/results/optimization-round/pure-map/README.md)
compares the same actors before and after wrapper simplification, including
instructions and allocated bytes for public functions at 1,000, 10,000, and
100,000 entries. It retains the rows where Core remains cheaper.
