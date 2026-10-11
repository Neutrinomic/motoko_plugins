# Mutable Set coverage

`Set.mo` tests all 66 public functions of `mo:fast/Set`, loading only the
mutable-set native plugin. Its 15 Ash methods execute on PocketIC. The three
large tree/differential methods use updates; the remaining methods use queries.
Method names below omit the `test_` prefix.

| Public functions | Methods and independent assertions |
| --- | --- |
| `empty`, `singleton`, `clear`, `size`, `isEmpty` | `empty_singleton_and_point_contracts`: empty extrema, repeated clearing, aliases, reuse after emptying; stress methods check sizes after mutation. |
| `contains`, `add`, `insert`, `remove`, `delete` | `empty_singleton_and_point_contracts`, `deterministic_differential_sequences`: present/absent states, idempotent membership, insertion/deletion booleans, independent Core and membership-array oracles. |
| `containsNat`, `addNat`, `insertNat`, `removeNat`, `deleteNat` | `scalar_helpers_and_ordering_edges`: zero, immediate/boxed boundary, values above 128 bits; `scalar_multilevel_trees`: 1,100 boxed keys compared with Core. |
| `containsNat64`, `addNat64`, `insertNat64`, `removeNat64`, `deleteNat64` | `scalar_helpers_and_ordering_edges`: zero, signed midpoint, maximum unsigned value; `scalar_multilevel_trees`: 1,100 keys near the unsigned maximum. |
| `containsText`, `addText`, `insertText`, `removeText`, `deleteText` | `scalar_helpers_and_ordering_edges`: empty, NUL, prefixes, Unicode; `scalar_multilevel_trees`: 1,100 dynamically concatenated NUL/Unicode keys. |
| `containsBlob`, `addBlob`, `insertBlob`, `removeBlob`, `deleteBlob` | `scalar_helpers_and_ordering_edges`: empty, prefixes, zero, `0x7f`/`0x80`/`0xff`; `scalar_multilevel_trees`: 1,100 binary keys. |
| `addAll`, `insertAll`, `deleteAll`, `retainAll` | `bulk_boolean_contracts_and_aliases`: empty inputs, duplicate/absent values, all inputs processed after the first change, size-change booleans, ascending predicate visitation; `reverse_order_seeks_and_core_algebra_representatives`: replacement-only insertion returns false. |
| `min`, `max`, `values`, `reverseValues`, `valuesFrom`, `reverseValuesFrom` | `iteration_seek_folds_and_short_circuit`: present/absent inclusive bounds, endpoints, exhausted iterators; `reverse_order_seeks_and_core_algebra_representatives`: descending comparator; differential sequences check seeks against filtered arrays. |
| `fromArray`, `fromIter`, `toSet`, `toArray` | `empty_singleton_and_point_contracts`, construction throughout: duplicate elimination and sorted output. |
| `clone`, `toPure`, `fromPure` | `representatives_clone_and_core_conversion`: independent containers sharing mutable payload references; clear/replace in a copy leaves source membership intact. |
| `union`, `intersection`, `difference`, `isSubset`, `equal`, `compare` | `algebra_and_comparison`: overlapping/disjoint/empty/self operands, input independence, proper subsets, insertion-order independence, lexical and prefix ordering; `reverse_order_seeks_and_core_algebra_representatives`: Core controls confirm left-side representatives. |
| `join`, `flatten` | `algebra_and_comparison`: overlapping sets, empty join, independently expected union; representative control confirms last iterated equal representative for `join`. |
| `map`, `filter`, `filterMap` | `transformations_and_projection_collisions`: ascending callbacks, collisions, last projected representative wins, dropped elements, independent result container. |
| `foldLeft`, `foldRight`, `forEach`, `find`, `all`, `any`, `toText` | `iteration_seek_folds_and_short_circuit`: exact callback order, early exit, missing matches, vacuous empty predicates, exact rendered strings. |
| `assertValid` | Construction and stress methods check occupancy, ordering, equal leaf depth, cleared slots, and size after public operations. |

Additional coverage:

- `deterministic_differential_sequences` performs 2,500 operations for each of
  three fixed seeds. Both Core Set and an independent 193-element membership
  array check results and ordered contents.
- `btree_boundary_growth_and_removal_orders` covers 1 through 2,049 elements,
  including 15/16/17, 31/32/33, 255/256/257, and 1,023/1,024/1,025. Three
  insertion/removal orders exercise growth, rebalancing, endpoint deletion,
  and complete root collapse. This does not claim native branch coverage.
- `null_optional_keys` and `bool_null_and_nested_option_elements` distinguish
  missing values from stored `null`, `?null`, `false`, and nested options.
  The latter grows 131 nested-option elements through splits and removes 66
  while retaining a clone.
- `comparator_reentrant_reads_and_other_set_writes` verifies allowed reads of
  the current set and mutation of another set from comparison callbacks.
- `key_only_leaf_insertion_allocation` asserts zero allocation when inserting
  an immediate Nat into a leaf with spare capacity. A hidden `(key, ())` map
  entry would violate this bound.

Run:

```sh
scripts/test-ash.sh Set
```

Finite tests do not prove correctness for every type or operation sequence.
Unsupported same-set mutation during callbacks and resuming invalidated
iterators are intentionally excluded. Compile/trap negatives, upgrades, and
multi-message GC are separate tests; see `SetGC.md` for the barrier regression.
