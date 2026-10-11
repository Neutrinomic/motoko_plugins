# Mutable Map coverage

`Map.mo` exercises all 58 public functions of `mo:fast/Map` through the package
import, loading only the mutable-map native plugin. The 17 Ash methods run on
PocketIC. Three stress methods use update calls because full-tree validation
after thousands of changes exceeds a query's instruction budget.

The tables list test method suffixes; every method has the `test_` prefix.

| Public functions | Ash methods and assertions |
| --- | --- |
| `empty`, `size`, `isEmpty`, `clear` | `empty_contracts`, `mutation_result_states`: empty behavior, insertion/clearing through aliases; stress methods check size after changes. |
| `singleton` | `constructors_and_detached_arrays`, `equal_key_replacement`: one binding, minimum, validity. |
| `get`, `getEntry`, `containsKey` | `mutation_result_states`, `equal_key_replacement`, `differential_mixed_operations`: missing versus present-null values, original stored key identity, independently checked results. |
| `insert`, `add`, `swap`, `replace`, `remove`, `delete`, `take` | `mutation_result_states`: all inserted/existing/absent return states; `equal_key_replacement`: equal keys replace both stored key and value; `differential_mixed_operations`: independent core-map oracle. |
| `getNat`, `addNat`, `replaceNat`, `removeNat` | `nat_scalar_helpers`: immediate/boxed and 64/128-bit boundaries, nullable values, missing keys, generic comparator agreement; `scalar_multilevel_trees`: big-Nat trees. |
| `getNat64`, `addNat64`, `replaceNat64`, `removeNat64` | `nat64_scalar_helpers`: zero, signed midpoint, maximum unsigned value; `scalar_multilevel_trees`: values near the unsigned upper bound. |
| `getText`, `addText`, `replaceText`, `removeText` | `text_scalar_helpers`: empty, NUL, prefix, decomposed/composed Unicode, emoji, expected lexical ordering; `scalar_multilevel_trees`: NUL/Unicode keys. |
| `getBlob`, `addBlob`, `replaceBlob`, `removeBlob` | `blob_scalar_helpers`: empty, zero, prefix, `0x7f`/`0x80`/`0xff` and binary keys; `scalar_multilevel_trees`: variable binary keys. |
| `minEntry`, `maxEntry` | `empty_contracts`, `ordered_iterators_and_inclusive_seeks`, `differential_mixed_operations`: both comparator directions and changing endpoints. |
| `entries`, `reverseEntries`, `entriesFrom`, `reverseEntriesFrom`, `keys`, `values` | `ordered_iterators_and_inclusive_seeks`: all exact keys and gaps across a multilevel tree, inclusive endpoints, out-of-range seeks, descending comparison, repeated exhaustion and interleaved independent cursors. `empty_contracts` checks empty cursors. |
| `clone` | `clone_reference_payloads_and_closures`: independently mutable binding trees, shared mutable keys/values and closure state, null values, clearing the source. `empty_contracts` checks empty clone. |
| `fromIter`, `fromArray`, `fromVarArray`, `toArray`, `toVarArray` | `constructors_and_detached_arrays`: empty inputs, duplicate key last-wins behavior, ordered output, mutation of input/output arrays does not change the map. |
| `foldLeft`, `foldRight`, `forEach` | `folds_find_and_short_circuit_order`: exact ascending/descending callback order and counts, independently calculated totals. `empty_contracts`: no callbacks on empty maps. |
| `find`, `any`, `all` | `folds_find_and_short_circuit_order`: first/middle/last/missing matches, exact early-stop call counts, all-true/all-false and vacuous empty results. |
| `map`, `filter`, `filterMap` | `transforms_order_and_tree_independence`: ordered once-per-entry callbacks, independently predicted transformed bindings, nested optional values, valid and independent result trees. `empty_contracts`: no callbacks on empty maps. |
| `equal`, `compare` | `equality_comparison_and_text`: equality independent of insertion order, key/value/length differences, prefix order, less/equal/greater results; `empty_contracts`: two empty maps. |
| `toText` | `equality_comparison_and_text`, `empty_contracts`: exact rendered output, order and formatter invocation counts. |
| `assertValid` | All construction/stress methods: ordering, node occupancy, cleared slots, leaf depth and size consistency after valid public operations. |

Additional behavioral stress:

- `differential_mixed_operations` starts with 550 entries, then performs 1,600
  deterministic mixed operations for **each** ascending and descending
  comparator. Return values, the complete ordered contents, size, emptiness,
  extrema, and tree validity are checked after every operation against
  `mo:core/Map`. The operation selector cycles through all nine cases rather
  than relying on random coverage.
- `btree_split_merge_borrow_and_root_collapse` covers 30, 31, 32, 255, 1,024
  and 2,048 keys in both orders. A coprime permutation inserts each key once;
  alternating endpoint removal exercises rebalancing and eventual root
  collapse. Validity is checked after every deletion, contents periodically,
  and the empty tree is reused. This does not instrument native branch counts
  or claim a proof that every borrow/merge branch ran.
- `scalar_multilevel_trees` independently compares all four scalar
  specializations with `mo:core/Map`, using 1,100 keys per specialization,
  overwrites, nullable replacement, and even-then-odd removal. This size exceeds
  the maximum capacity of a tree with only a root and leaf level.
- `valid_callback_reentrancy` reads the current map and mutates another map
  from comparison and traversal callbacks, preserving the documented callback
  contract.

Limits: this is finite deterministic coverage, not an exhaustive proof for all
types or operation sequences. It does not depend on or test the private tree
representation directly. Prohibited same-map mutation during callbacks and
resuming invalidated iterators are not supported behavior. Deliberately
malformed trees, compile-negative cases, cross-plugin GC, and upgrades have
separate repository test coverage; the Ash methods here do not replace it.
