# `mo:fast/pure/Map` Ash coverage

Run from the plugins repository with the current compiler and built native
`pure-map` plugin:

```sh
scripts/test-ash.sh PureMap
```

`PureMap.mo` contains 22 independent PocketIC tests. All 101 exported functions
in `src/pure/Map.mo` have semantic assertions across this suite and the shared
`CoreAPI.mo` contract suite, which covers `toMap` and implicit arguments. Expected results use literal
arrays, array filtering, or an independent slot model. Public types `Map`,
`Order`, `Bound`, `Iter`, `EntryIter`, `EntrySnapshot`, and `Builder` are used by
these tests. This is API coverage, not a claim that every possible input or
runtime state is covered.

Names in the table omit the `test_` prefix. The shared `check` helper verifies
the complete ordered array, exact size, and `assertValid`; iterator checks also
verify repeated exhaustion.

| Functions | Tests and assertions |
|---|---|
| `empty`, `singleton`, `size`, `isEmpty`, `clone`, `treeDepth`, `nodeCount`, `toArray`, `assertValid` | `empty_and_singleton`; exact empty/singleton metadata, full contents, preserved copies. Every subsequent group validates resulting trees. |
| `get`, `getEntry`, `containsKey`, `add`, `swap`, `insert`, `replace`, `remove`, `take`, `delete` | `point_operations_and_old_values`; hits and misses, replacement versus insertion, old values and booleans, original versions unchanged. `deterministic_state_machine_against_array_model` checks 2,048 generated operations. |
| `alter`, `update`, `insertWith` | `optional_values_and_callback_contract`; exactly one callback, insert/replace/delete/no-op cases, old values, combine argument order, callback reentry. `empty_transforms_and_null_specializations` exercises nullable and generic payload layouts. |
| `getNat`, `addNat`, `replaceNat`, `removeNat`, `getNat64`, `addNat64`, `replaceNat64`, `removeNat64` | `scalar_nat_and_nat64_boundaries`; zero, boxed natural, 129-bit natural, high-bit and maximum `Nat64`, hits/misses, old values, ordering, persistence. |
| `getText`, `addText`, `replaceText`, `removeText`, `getBlob`, `addBlob`, `replaceBlob`, `removeBlob` | `scalar_text_and_blob_prefixes`; empty keys, strict prefixes, embedded NUL, UTF-8 and bytes above 127, hits/misses, replacement/removal and retained prior versions. |
| `minEntry`, `maxEntry`, `rank`, `indexOf`, `select`, `lower`, `floor`, `ceiling`, `higher` | `rank_select_and_neighbors`; all 71 probes through a 33-entry gapped map, independent filtered-array expectations, out-of-range and 129-bit indices. Empty/singleton and descending-order cases are separate. |
| `splitLookup`, `split`, `join`, `concatDisjoint`, `splitAt`, `takeRank`, `dropRank` | `split_join_concat_and_rank_cuts`; each present/absent pivot and every rank cut through and past the end, ordering, exact partitions, successful reconstruction, empty joins, persistence. |
| `popMin`, `popMax` | `pop_min_max_exhaustion`; remove all 64 entries in both directions, exact returned pairs, count and balance after each operation, repeated empty behavior, original retained. |
| `rangeSnapshot`, `countInRange`, `rangeMap`, `removeRange`, `entriesInRange`, `reverseEntriesInRange` | `exhaustive_range_boundaries`; all 169 pairs from 13 lower/upper bounds, inclusive/exclusive/unbounded, present/absent/outside/reversed bounds, exact forward/reverse contents and complementary removal. |
| `snapshot`, `replay`, `entries`, `reverseEntries`, `entriesFrom`, `reverseEntriesFrom`, `keys`, `values` | `cursors_seek_snapshot_replay_and_versions`; independent interleaved cursors, snapshot replays start at view origin, no replayed comparator calls, seeks past endpoints, ordered keys/values, snapshots retain old versions. |
| `foldLeft`, `foldRight`, `foldValues`, `forEach`, `find`, `any`, `all`, `toText` | `folds_order_short_circuit_and_counts`; noncommutative accumulation establishes exact order, first match, negative match, short-circuit callback counts, zero callbacks on empty, exact rendered text. |
| `map`, `filter`, `filterMap`, `partition` | `transforms_partition_and_callback_order`; exact results and callback order/count, type-changing mapping, all-accept/all-reject paths, balanced outputs, unchanged input. Empty behavior covered separately. |
| `union`, `unionWith`, `intersection`, `intersectionWith`, `difference`, `symmetricDifference`, `isDisjoint` | `set_algebra_bias_and_conflict_callbacks`; exact conflicts, right/left bias, argument order, one callback per overlap in key order, both relative input sizes, empty/self cases. `set_algebra_against_all_small_subsets` verifies all 1,024 pairs of five-key subsets against independent arrays. |
| `isSubmap`, `equal`, `compare` | `submap_equal_and_lexicographic_compare`; structure-independent equality, size/key/value mismatches, prefix ordering, key precedence, callback short circuit, empty cases. All-subsets test also checks submap membership with heterogeneous value equality. |
| `fromSortedDistinctArray`, `thaw`, `thawAppend`, `freeze` | `sorted_builder_capacity_boundaries_and_reuse`; 19 sizes from 0 to 129 around growth/tree boundaries, repeated freeze, append after freeze, equal-last-key replacement, prior trees isolated from buffer changes. |
| `fromIter`, `fromArray`, `addList`, `mapKeys` | `constructors_stable_duplicates_and_mapkeys`; empty/singleton/sorted/unsorted input, stable last-duplicate wins, exactly one iterator consumption, list precedence, duplicate transformed keys, decreasing transforms, callback order/count. |

Additional tests cross these API groups:

- `descending_order_and_equivalent_key_policy` checks descending search,
  neighbors, ranges and joins; comparator-equivalent record keys replace the
  stored key in point operations and constructors. Union keeps the right key;
  intersection keeps the left key, including both divide-by-size branches.
- `shared_mutable_payloads_and_closures` checks shared payload objects and
  closures across clones, updates, filters, snapshots and frozen builders while
  their map structures remain independent.
- `empty_transforms_and_null_specializations` checks zero callbacks on empty
  transformations, `Null`, nested options, generic wrappers, absent versus
  present-null, and type-changing intersection.
- `deterministic_state_machine_against_array_model` runs 2,048 operations over
  127 keys, validates every intermediate tree and old selected binding, checks
  rank/select, and rechecks 64 retained historical versions.
- `rotations_large_ordered_and_shuffled_updates` covers sizes 1, 2, 3, 31, 128,
  1,000 and 4,096, ascending/descending/permuted insertion, complete permuted
  deletion, bounded depth, exact contents and retained roots. Heavy tests use
  update methods; ordinary cases use queries.

Expected traps for malformed trees/snapshots, overlapping joins, and invalid
sorted input belong to the central negative suite. Heap relocation, deliberate
GC pressure, malformed raw nodes and native/reference differential execution
also retain their existing compiler-harness tests. These façade tests validate
successful typed use on PocketIC; they do not establish pointer identity of
immutable subtrees or replace the performance and GC suites.

Validation: 22 passed, 0 failed, 0 skipped. On the recorded local run the three
heaviest test bodies reported approximately 244M instructions/15 MB heap
(state machine), 334M/30 MB (rotations), and 186M/15 MB (all subsets). These are
test-workload measurements, not comparative plugin benchmarks.
