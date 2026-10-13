# IndexedPriorityQueue coverage

`IndexedPriorityQueue.mo` exercises the public `mo:fast/IndexedPriorityQueue`
module through Ash/PocketIC. Its independent cases are shared with two compiler
fixtures in `tests/run` so the interpreter, IR interpreter, lowered interpreter,
and generated Wasm must agree.

The semantic cases cover:

- Two deterministic 600-step histories against an independent array oracle:
  insertion, minimum removal, arbitrary removal, rescheduling, replacement,
  clearing, stale handles, nullable values, and unordered iteration membership.
  Duplicate priorities deliberately do not assume FIFO ordering.
- Growth and shrink boundaries from empty through 1,024 entries, handle identity
  after movement, repeated exhaustion, and old handles after storage reuse.
- Separate queues, clear invalidation, and handle-directed owner selection.
- Built-in Nat, Int, Nat64, and Text orderings, integers through 2^2048, Unicode
  text, and an effectful reverse comparator that must use the callback path.
- `peekPriority` on empty, scalar, Null, nullable, and record priorities,
  including calls through a generic wrapper and references read after GC/upgrades.
- Nested options, Null priorities and payloads, mutable payload aliases,
  closures, blobs, and explicit composite priorities for deterministic ties.
- A comparator that allocates, reads the current queue, and mutates a different
  queue. A separate case verifies every active handle's priority and payload
  during each comparator call, including replacements and removals in progress.
- A mixed-dispatch regression compares proven Nat64 comparators with opaque
  equivalent comparators, including all-equal and duplicate-heavy priorities. It
  compares heap traversal, popped payload IDs, handle states, and observable
  callback traces through size boundaries from zero to 129.
- Exact observable comparator argument traces during upward reschedule,
  replacement, and removal. This regression fails against the initial native
  implementation, which repeated the first comparison, while the reference
  interpreter passes. The repaired native implementation matches the reference.

`IndexedPriorityQueueGC.mo` adds forced incremental-GC coverage. It instantiates
native helpers with Bool/Null before heap-reference specializations, retains
96 MiB of live arrays, and updates record priorities, nullable payload records,
owner links, indices, and closures across message boundaries while a collection
is pending. A parallel Nat64-priority queue pops and refills 64 managed payloads
in each generation, exercising the proven scalar path during the same GC cycle;
minimums, detached handles, and live payload aliases are checked after each pop. It verifies that a pending cycle was observed and later completed,
and that more than 32 MiB was reclaimed. Another test retains detached handles
while checking owner and payload reclamation. It reuses one retained input array
to create 24 distinct 1 MiB blobs, then drops the queues while retaining their
detached handles. Bounded allocation-pressure/collection batches must reclaim
more than 20 MiB **beyond all bytes allocated after the measurement began**.
This prevents temporary conversion arrays or pressure garbage from satisfying
the payload-reclamation assertion. Empty awaits alone cannot reliably start a
new collection on the partitioned heap.

`tests/run-drun/indexed-priority-queue-upgrade.mo` performs two real upgrades with
stable queue aliases, cyclic queue/handle ownership, a shared mutable payload
cell, live handles, and detached handles. Mutations and forced collections after
each upgrade verify the retained graph, handle indices, and payload contents.

Run the canister suites with:

```sh
scripts/test-ash.sh --ash-source /path/to/ash IndexedPriorityQueue IndexedPriorityQueueGC
```

Run the native fixtures from the matching compiler checkout's Nix environment:

```sh
test-runner -b /path/to/plugins/packages/fast/tests/run/indexed-priority-queue-model.mo \
  /path/to/plugins/packages/fast/tests/run/indexed-priority-queue-generics.mo \
  /path/to/plugins/packages/fast/tests/run-drun/indexed-priority-queue-upgrade.mo
```

The Ash GC metrics cover only final verification; they are correctness tests,
not performance benchmarks. Tests use supported public operations and do not
resume iterators after mutation or mutate the current queue inside a comparator.

First-round validation on 2026-10-12 passed all three native fixtures, ten semantic
Ash cases, and three GC Ash cases against native plugin SHA-256
`4cbe7359b0b4f88c6f520575ea92e9dc660e3689a20afa1a2e3344839df3c912`
(Motoko PR compiler `92b1bde`). Actual native typecheck/compile/execution outputs
were inspected: no errors, traps, or accepted failure-return expectations.

A separate negative-control canister intentionally kept the popped handle's
owner queue reachable, retaining seven large payloads. The retention assertion
correctly failed after its bounded pressure batches; both unrelated GC cases
still passed. This checks that the accounting assertion detects an owner leak,
in addition to the public stale-handle behavior checks.

Second-round validation on 2026-10-12 passed the three native fixtures again
(68.9 seconds), eleven semantic Ash cases, and all three GC cases against the
published plugin SHA-256
`87627cd033f978563ad17d991376427de4118343f5fc6b697306c500e0e6364e`.
No expected output was accepted or changed. This round added mixed comparator
dispatch, duplicate-priority layout checks, scalar pops during pending GC, and
scalar minimum removal across upgrades. [The validation record](IndexedPriorityQueue.round2.validation.json)
contains source/artifact hashes, output checks, and the comparator specialization
evidence: Core Nat64.compare matches descriptor 6, and the generated native
fixture includes `ipq_sift_pop_bottom_scalar_Nat64`. No runtime coverage
instrumentation was used.
