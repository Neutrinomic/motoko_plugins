# Pure Set coverage

`PureSet.mo` tests all 70 public functions of `mo:fast/pure/Set`, loading only
the pure-set native plugin. Its 16 Ash methods execute on PocketIC. Four large
tree/differential methods use updates; the remaining methods use queries.
Method names below omit the `test_` prefix.

| Public functions | Methods and independent assertions |
| --- | --- |
| `empty`, `singleton`, `clone`, `size`, `isEmpty`, `treeDepth` | `empty_singleton_and_persistent_point_contracts`: empty/singleton depth, retained versions, repeated insertion/removal, constant-time clone; allocation checks verify no-op sharing. |
| `get`, `contains`, `add`, `insert`, `remove`, `delete` | `empty_singleton_and_persistent_point_contracts`, `deterministic_differential_sequences`: present/absent results, boolean contracts, old versions preserved, Core and independent membership-array controls. |
| `getNat`, `containsNat`, `addNat`, `insertNat`, `removeNat`, `deleteNat` | `scalar_helpers_and_ordering_edges`: zero, boxed boundary, values above 128 bits; `scalar_multilevel_trees`: 1,100 boxed keys and persistence through complete removal. |
| `getNat64`, `containsNat64`, `addNat64`, `insertNat64`, `removeNat64`, `deleteNat64` | `scalar_helpers_and_ordering_edges`: signed midpoint and maximum unsigned value; `scalar_multilevel_trees`: 1,100 keys near the maximum. |
| `getText`, `containsText`, `addText`, `insertText`, `removeText`, `deleteText` | `scalar_helpers_and_ordering_edges`: empty, NUL, prefixes, Unicode; `scalar_multilevel_trees`: concatenated NUL/Unicode keys. |
| `getBlob`, `containsBlob`, `addBlob`, `insertBlob`, `removeBlob`, `deleteBlob` | `scalar_helpers_and_ordering_edges`: empty, prefixes, zero and high bytes; `scalar_multilevel_trees`: 1,100 binary keys. |
| `min`, `max`, `values`, `reverseValues` | `iteration_find_folds_and_short_circuit`, empty/nullable tests: sorted order, repeated exhaustion, retained iterator unaffected by creating new versions; `reverse_order_and_reentrant_callbacks`: descending comparator. |
| `rank`, `indexOf`, `select` | `rank_select_split_and_disjoint_joins`: keys and gaps, absent/out-of-range indices, empty input; differential sequences independently calculate ranks. |
| `splitLookup`, `joinDisjoint`, `concatDisjoint` | `rank_select_split_and_disjoint_joins`: stored representative versus missing, empty sides, 1,024-node split/rejoin and strongly imbalanced joins; `reverse_order_and_reentrant_callbacks`: descending comparator. |
| `fromArray`, `fromIter`, `toSet`, `fromSortedDistinctArray`, `toArray` | Point-contract tests: sorted and unsorted constructors, duplicates, empty sorted input; large tests exercise balanced sorted construction. |
| `union`, `intersection`, `difference`, `isSubset`, `equal`, `compare` | `algebra_comparison_join_and_flatten`: expected contents and lexical/prefix order; `differential_algebra_across_tree_shapes`: independent arithmetic membership predicates plus Core controls over dense/sparse shapes and 2,049:1 input size imbalance. |
| `join`, `flatten` | `algebra_comparison_join_and_flatten`: overlapping nested sets, empty join, exact union contents, preserved input versions. |
| `map`, `filter`, `filterMap` | `transformations_and_projection_collisions`: exact callback visitation order, retained/dropped elements, collisions preserve the first projected representative; nullable test maps every element to stored null. |
| `foldLeft`, `foldRight`, `forEach`, `find`, `all`, `any`, `toText` | `iteration_find_folds_and_short_circuit`: exact order and early-stop counts, missing matches, vacuous empty predicates, exact rendered strings. |
| `assertValid` | Point, split/join, construction, algebra, and differential tests check ordering, heights, AVL balance, and subtree sizes after operations. |

Additional coverage:

- `deterministic_differential_sequences` performs 2,500 mixed operations for
  each of three fixed seeds, with Core Set and an independent membership-array
  oracle. Prior versions remain valid after each update.
- `avl_rotations_boundaries_and_persistence` begins with all four three-key
  rotation patterns, then tests three insertion/removal orders up to 1,023
  elements. It retains and rechecks each complete original tree after removal.
- `first_representative_and_shared_payloads` confirms duplicate insertion
  preserves the original object while old/new versions share payload objects.
  `algebra_representatives_match_core` separately checks the size-sensitive
  representative selection of Core pure union/intersection using record keys.
- `null_optional_keys_and_results` distinguishes absent lookup from stored
  `null` in get/min/select/find/split. `bool_null_and_nested_option_elements`
  covers false, Null, and 131 nested optional elements across updates.
- `reverse_order_and_reentrant_callbacks` reads a separate retained set and
  changes another pure-set variable from comparison callbacks.
- `noop_sharing_and_key_only_allocations` asserts zero allocation for clone,
  duplicate add, and absent remove. Adding one element to a 1,023-node balanced
  tree must allocate less than 4 KiB, ruling out a whole-tree clone.

Run:

```sh
scripts/test-ash.sh PureSet
```

These finite tests are not a correctness proof or native branch-coverage claim.
Compile-negative inputs, malformed structures, invalid disjoint joins, and
unsorted/duplicate sorted-constructor inputs have separate repository tests.
GC and upgrade tests complement these single-call functional checks.
