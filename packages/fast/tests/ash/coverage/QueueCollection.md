# Queue correctness coverage

After final validation, two module header comments were corrected to limit the
no-whole-queue-copy promise to endpoint operations. Implementation bytes and
line count are unchanged. The composition fixture passed before and after,
with byte-identical Wasm. The validation JSON records both module hashes;
earlier Ash, upgrade, and benchmark results retain the pre-comment hash.

`QueueCollection.mo` runs five public-module tests on PocketIC through Ash. The
same shared assertions run in `queue-model.mo` and `queue-generics.mo` through
the source interpreter, both IR interpreters, and compiled Wasm.

- Both-ended push, pop, and peek, with empty queues, alternating ends, partial
  drains, circular-slot wraparound, repeated reuse, and 18 lengths from zero to
  1,024 (including either side of each 32-element chunk boundary).
- Four deterministic random seeds, 2,000 operations each, checked after every
  operation against `mo:core/Queue`, including forward/reverse order, size,
  aliases, clear, and detached clones.
- Every Core-compatible public function: constructors, array/iterator/pure
  conversions, clone, queries, mutation, traversal, mapping/filtering,
  comparison, equality, and text. Predicate short-circuiting, callback order,
  duplicate elements, prefix comparison, iterator exhaustion, detached array
  outputs, and empty-callback behavior have explicit expectations.
- `Null`, `?Null`, nested optionals, huge integers, Unicode text, variants,
  mutable arrays, records, closures, and shared mutable payloads. Cloning copies
  container structure while preserving payload aliases. Supported callbacks
  read their source queue and mutate payloads or a different queue.
- Native immutable/mutable array exports cover null, nested optional, and
  pointer-bearing payloads across nine lengths around chunk boundaries,
  nonzero chunk offsets, closures and shared mutable references. Editing an
  exported mutable array leaves queue slots and immutable exports unchanged.
  Type-erased `Any` payloads also preserve their cardinality and iteration.

A mutation check replaced `popBack` with `popFront` in a temporary module copy;
the independent Core-oracle test failed at the first differing removal.

`QueueCollectionGC.mo` adds three tests with `--sanity-checks --force-gc`:

- Pointer-free native specializations are emitted before reference-bearing
  calls, checking that shared helpers preserve the necessary GC barriers.
- Queues retain records, blobs, mutable aliases, closures, and nested optionals
  during incremental collection across management-canister calls. The test
  keeps 96 MiB of live arrays among dead allocations, checks that a collection
  was pending and later completed, and observes at least 32 MiB reclaimed.
  It mutates both ends across chunk allocation/detachment and retains forward
  and reverse iterators through subsequent collection without mutating their
  queue. Native array exports are created during collection and retained over
  a message boundary. Exhausted iterators remain exhausted after the queue is
  cleared and further collection runs.
- A focused representation check verifies that popped slots are null, empty
  detached chunks no longer point at neighbors, the single spare is cleared
  during 128 cycles alternating endpoint reuse, and clear drops all three
  queue roots. This directly tests reference release. It does **not** infer
  retained live bytes from a short `rts_heap_size()` sample: collection and
  allocation-partition reuse can defer changes to that counter.

`run-drun/queue-collection-upgrade.mo` additionally exercises two actual
upgrades, preserving queue aliases, independent cloned chunks, shared mutable
payloads, nullable values, and continued mutation after each upgrade. Its
post-upgrade checks also run after real collection.

```sh
scripts/test-ash.sh --ash-source /path/to/ash QueueCollection QueueCollectionGC
# From the selected compiler checkout's Nix environment:
test-runner -b /path/to/plugins/packages/fast/tests/run/queue-model.mo \
  /path/to/plugins/packages/fast/tests/run/queue-generics.mo \
  /path/to/plugins/packages/fast/tests/run-drun/queue-collection-upgrade.mo
```

The Ash instruction/heap figures include test oracles and sanity checks; the
GC test metrics cover only its final synchronous verification. These are
correctness tests, not Queue performance measurements. Mutation-invalidated
iterators and callbacks that structurally mutate their own source queue are
outside the documented API contract and are not assigned behavior here.

Initial validation after all three optimization passes: **4 native fixtures and
8 Ash checks passed**, including two real upgrades. Positive native outputs
were inspected, and the final expectation comparison ran without accept mode.
[Validation evidence](QueueCollection.validation.json) records the compiler,
plugin, module, test source, and compiled test-Wasm hashes.

The second optimization round packs each chunk's start/count into one `Nat32`.
Its expanded checks cover all 32 start offsets at lengths 31, 32, and 33 in both
directions, checking both peeks after every removal and after complete drains.
Heterogeneous `Any` values and native exports also survive actual incremental
GC, and the upgrade fixture now retains and reuses a detached spare across both
upgrades. **All 4 native fixtures and 8 Ash checks passed again**, with positive
outputs inspected and expectation comparison run without accept mode. Both
deliberately wrong endpoint removal and a trap on a drained back peek were
rejected by mutation controls. The packed stable representation changes the old
shape; these upgrade tests cover the new layout only, without claiming a
migration from the earlier unpacked layout.

[Round 2 evidence](QueueCollection.round2.validation.json) preserves the new
hashes separately. It also links the independent controlled-pressure retention
probe: three 4,096-element refill/clear cycles returned to the initial heap with
zero reachable storage or payloads, and 12,288 churn operations at 33 elements
showed no heap growth. A completely drained Queue retained one cleared 408-byte
chunk; clear released it. These figures come from the separate retention probe,
not the Ash correctness metrics.
