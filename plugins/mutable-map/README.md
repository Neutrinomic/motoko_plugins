# Mutable ordered map

A mutable B-tree over ordinary Motoko heap objects. Native plugin kernels search,
insert, replace, and delete in place. A normal update changes only a bounded
number of nodes on its search path; it never copies the whole map. The tree has
up to 31 entries per node, with 32 child slots in internal nodes.

Keys and values keep their real Motoko types, including optional values,
closures, mutable records, and large Blobs. Payloads stay shared references;
there is no serialization boundary or private plugin heap. Writes use the SDK's
typed managed mutation operations and the runtime's GC barriers. `clone`
explicitly copies nodes and their arrays while sharing keys, values, and entry
tuples. Changing either clone's bindings does not change the other clone.

```motoko
import Map "mo:fast/Map";

let map = Map.empty<Nat, Text>();
Map.addNat(map, 42, "answer");
let alias = map;
Map.addNat(alias, 7, "seven");
assert Map.getNat(map, 7) == ?"seven";

let copy = Map.clone(map);
Map.removeNat(copy, 42);
assert Map.getNat(map, 42) == ?"answer";
assert Map.getNat(copy, 42) == null;
```

Build and compile from the matching Motoko checkout's Nix shell:

```sh
../plugins/scripts/build.sh --motoko "$PWD" mutable-map
bin/moc --plugin ../plugins/dist/mutable-map \
  --package fast ../plugins/packages/fast/src app.mo -o app.wasm
```

The package uses ABI **1** and must match the compiler it was built against. It
emits Wasm through the compiler SDK and needs no separate runtime Wasm module.

## API

[`mo:fast/Map`](../../packages/fast/src/Map.mo) follows the argument order and result
conventions of `mo:core/Map` for these operations. Compare-equal keys replace both
the stored key and value; construction keeps the last occurrence. `insert`
returns whether a new key was added; `swap`, `replace`, and `take` return the
previous optional value; `delete` returns whether a key was removed.

| Family | Operations |
|---|---|
| Construction and size | `empty`, `singleton`, `fromIter`, `fromArray`, `fromVarArray`, `size`, `isEmpty`, `clear` |
| Point operations | `get`, `getEntry`, `containsKey`, `insert`, `add`, `swap`, `replace`, `remove`, `delete`, `take` |
| Scalar order | `getNat64`, `addNat64`, `replaceNat64`, `removeNat64`; corresponding `Nat`, `Text`, and `Blob` functions |
| Ordered iteration | `entries`, `entriesFrom`, `reverseEntries`, `reverseEntriesFrom`, `keys`, `values`, `minEntry`, `maxEntry` |
| Traversal | `find`, `forEach`, `foldLeft`, `foldRight`, `all`, `any` |
| Copies and transforms | `clone`, `map`, `filter`, `filterMap`, `toArray`, `toVarArray` |
| Comparison and diagnostics | `equal`, `compare`, `toText`, `assertValid` |
| Optional core interop | [`CoreMap.toPure`, `CoreMap.fromPure`](../../packages/fast/src/CoreMap.mo) |

Scalar helpers use ascending natural ordering without a comparator callback.
They must only be used on maps built with that ordering. The lower-level
`Prim.mmap_*_static<K,V>` operations also support the other integer types,
`Bool`, `Char`, and `Principal`; unsupported key types are rejected at compile
time. The normal functions accept any lawful synchronous comparator.

Point operations are `O(log n)` in tree height and comparator cost. `clear` is
constant time and releases the map's reference to its tree. `clone`, `map`,
iteration, folds, and array conversion are `O(n)`; `find` stops at the first
matching entry in ascending order. Construction, `filter`, and `filterMap` use
successive insertions, costing `O(n log n)`. Iterators own an `O(height)` stack,
return stored entry tuples, and perform their initial descent lazily. Seek is
inclusive and starts at the nearest key in the requested direction.

The optional `mo:fast/CoreMap` module requires `--package core PATH/TO/core/src`.
`toPure` and `fromPure` rebuild the destination structure in `O(n log n)` time
and share payloads. The main module has no core-library dependency. These
conversions use core's pure map, independently of the persistent `pure-map`
plugin.

## Mutation and lifetime

Use the same lawful comparator for all operations on a map. Never mutate a
stored key in a way that changes its ordering. The structural fields of `Map`
and `Node` are private by contract; applications should access maps through
these functions. `assertValid` performs an explicit full check of occupancy,
ordering, cleared slots, equal leaf depths, and total size.

Comparators and traversal callbacks may read the same map, mutate other maps,
and mutate payload objects. They must not insert, delete, replace, or clear
entries in the same map being operated on. Any mutation attempt invalidates
existing iterators, even if the requested key is absent; do not resume them.
There is no runtime lock, version counter, or fail-fast guarantee. Violating
these contracts can produce incorrect logical results or traps.

A map is stable when its key and value types are stable. GC manages the complete
structure and its payloads. A removed payload can remain live through another
reference, a clone, or an iterator, just like any other Motoko value. The plugin
has no hidden persistent state or manually freed resources.

Tests cover source/IR/lowered/Wasm behavior, mixed operations against
`mo:core/Map`, splitting and deletion to an empty root, inclusive seeks, nullable
and shared mutable payloads, closure identity, independent clones, GC, and
actor upgrade. Performance measurements compare against core's **mutable** map
and report instruction counts and cumulative allocated/reclaimed bytes; these
allocation counters are not peak or live memory.
