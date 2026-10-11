# Mutable Set

A dedicated key-only managed B-tree with native lookup, insertion and deletion.
Use `import Set "mo:fast/Set"` and compile with `--plugin dist/mutable-set`.
The module follows `mo:core/Set`'s public interface; `toPure` and `fromPure`
convert to and from `mo:core/pure/Set`. It does not load either map plugin.

```motoko
import Set "mo:fast/Set";
import Nat "mo:core/Nat";
let set = Set.empty<Nat>();
Set.add(set, Nat.compare, 42);
assert Set.contains(set, Nat.compare, 42);
assert Set.delete(set, Nat.compare, 42);
```

The native point operations are `contains`, `add`, `insert`, `remove`, and
`delete`. Ordinary calls using a proven scalar comparator, such as
`Set.contains(set, Nat64.compare, key)`, automatically select native ordering.
This also works when that comparator arrives through an alias, record field,
or generic function. Unrecognized comparators, including effectful comparators,
retain normal callback behavior; `Float.compare` remains a callback. Matching a key type or function
name alone never selects native ordering.

Optional `Nat`, `Nat64`, `Text`, and `Blob` helpers use ascending native ordering
without a comparator argument. Lookup and updates are logarithmic.
Nodes hold up to 31 elements directly: there is no dummy map value or allocated
key/value tuple. Clone copies tree nodes and arrays but shares the elements.

As in Core's implementation, adding a comparator-equivalent element replaces
its stored representative; `insert` returns false in that case. Union retains
the left set's representative. `find`, ordered iterators, inclusive seek,
algebra, transformations and folds are available in the Motoko module.

Elements remain ordinary Motoko values, including mutable objects, closures,
and nested options. Nodes and slots use the SDK's managed allocation, mutation
barriers and option operations; no private memory or raw heap layout is used.
The representation is stable when its element type is stable.

Use a consistent lawful ordering and do not modify an element's ordering while
it is stored. Treat the exposed representation fields as private. Callbacks may
read the set and mutate other sets, but must not mutate bindings in this set.
Any mutation attempt invalidates its iterators. There are no runtime locks or
iterator version counters. Comparator exceptions trap normally; there is no
plugin-specific rollback beyond the enclosing execution's usual behavior.

The compiler plugin registers ABI 1 primitives `mset_*` and `mset_*_static`.
It has no runtime Wasm module. The repository's native tests cover structural
updates, nullable and non-Shared elements, scalar ordering, malformed trees and
type rejection. The `fast` package's Ash suite checks the full module API.
