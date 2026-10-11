# Persistent Set plugin

```motoko
import Set "mo:fast/pure/Set";
import Nat "mo:core/Nat";

let original = Set.fromArray([3, 1, 2, 1], Nat.compare);
let updated = Set.add(original, Nat.compare, 4);
assert Set.toArray(original) == [1, 2, 3];
assert Set.toArray(updated) == [1, 2, 3, 4];
```

Load `--plugin dist/pure-set --package fast packages/fast/src` when compiling.
No other plugin is required. The plugin uses ABI 1 and must be built against
the selected Motoko compiler.

Native code searches and balances an immutable, key-only AVL tree. Nodes hold
height, size, element, and two child references; there is no map value or unit
placeholder. Point updates copy the changed path and share other subtrees.
Duplicate additions and missing removals return the original tree without
allocating replacement nodes. Elements, including mutable objects, stay shared
by reference; never mutate fields used by their ordering.

The module includes the public `mo:core/pure/Set` operations. Comparator-equal
additions preserve the first element. Union retains representatives from the
larger input (left on equal sizes); intersection retains representatives from
the smaller input (right on equal sizes), matching Core 2.5.0. Set algebra uses
native split/join operations and shares surviving subtrees.

Native key operations, including lookup, updates, rank and split, automatically
select scalar ordering when the compiler proves it, including comparators passed through
aliases, record fields, or generic functions. Unrecognized comparators, including
effectful comparators, retain ordinary callbacks; `Float.compare` remains a callback. A matching
function name or key type alone is insufficient.

`addNat`, `containsNat64`, and the corresponding `get`, `insert`, `remove`, and
`delete` helpers remain optional ways to select ascending scalar order without
a comparator argument. Generic operations support arbitrary Motoko elements.
`fromSortedDistinctArray` validates ordering and constructs a tree
in linear time; `fromArray` uses stable sorting and keeps the first occurrence
of each element. Iterators use a lazy stack proportional to tree height.

Additional operations include `get`, `find`, `rank`, `indexOf`, `select`,
`splitLookup`, checked `joinDisjoint`/`concatDisjoint`, `toArray`, and `clone`.
Clone is constant time because immutable nodes are shared. Structural fields
are an implementation detail: use module constructors, and use `assertValid`
when explicitly checking manually constructed trees. Routine operations do
not run whole-tree validation.

The compiler generator and interpreter implementation both live in `compiler/`.
`tests/run` exercises tree rotations, shuffled insertion/removal, retained
versions, generic nullable elements, reference-bearing elements, scalar
specializations, and direct primitive calls in Motoko, IR, and Wasm execution.
`tests/trap` checks malformed metadata and checked-constructor failures;
`tests/fail` checks rejection of unsupported static element types. The
`tests/run-drun` regression retains old sets, iterators, and native split
results across forced collections, with allocating comparators and shared
blobs, mutable cells, and closures.
