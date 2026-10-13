# Collection alternatives for Takt, Reactor and Rechain

Research date: 2026-10-12, updated after the integration measurements. Rechain's private FIFO is now adopted; the remaining alternatives are proposals, not predicted instruction gains. The existing `mo:fast/Map` is already a mutable 31-entry-node B-tree; “try a B-tree” would repeat what we have.

**An addressable FIFO proved a useful library fit for Rechain's cache; native minimum removal in the existing Map plugin is the strongest next plugin option.** Rechain's FIFO is implemented in ordinary Motoko, not a new plugin. Takt and Reactor retain their Map deadline indexes after testing the latest IPQ. Queue remains useful for endpoint work and HistoryRing for bounded trace history. An indexed heap is valuable for arbitrary priority changes through handles, but the libraries do not spend all their time on that operation.

The [integration report](README.md) records the adopted changes and tradeoffs. Combined Takt inline Queue reuse and Rechain FIFO save instructions and allocation, with completion unchanged at 57 rounds and higher replica dirty-page accounting; that application result cannot be attributed to FIFO alone.

| Consumer inspected | Required operations and order | Consequence |
|---|---|---|
| Rechain `Transactions.Cache` | Global insertion FIFO; reads do not refresh order; replacement becomes newest; arbitrary deletion from per-chain limits/prefix deletion | Private linked FIFO adopted. A heap maintains more ordering than necessary. |
| Takt `Engine.wakes` | Minimum `{at : Int; ticket : Nat}`, cancellation by saved key, arbitrary absolute `#Until(at)`, persistent reconstruction | Needs exact ordering and arbitrary cancellation. Pure FIFO and unrestricted radix-heap substitution are invalid. |
| Reactor `Scheduler.deadlines` | Minimum `{at : Int; driver : Nat}`, arbitrary driver deadline changes, cancellation; transient reconstruction | Few library drivers is the normal application case; a 100,000-driver heap benchmark is not representative. |
| Reactor delayed receives/sends | Exact alarm ordering and cancellation; receives can accumulate, sends are keyed by peer/lane | Evaluate these separately from the small scheduler index. Pop-heavy composite keys need not benefit from handle rescheduling speed. |
| Rechain idempotency expiry | Exact timestamp buckets, bounded pruning, immutable duplicate-expiry evidence | Already uses `Map<Int, List<Blob>>`; bucket organization is present. Preserve its admission and commit boundaries. |

Source sites: Takt `src/Engine.mo` (`wake`, `cancelWake`, `due`, `#Wait`); Reactor `src/Scheduler.mo` (`update`, `enqueueDue`, `arm`) and `src/Transport.mo`; Rechain `src/storage/Transactions.mo` (`Cache`) and `src/reducers/idempotency/lib.mo` (`expire`, `hasCapacity`).

Reactor's deadline-index ordering is only one part of scheduling. `updateAll` and the existing ready queues also establish observable ordering; replacing the index must not turn all overdue work into a globally deadline-sorted drain.

## 1. Addressable FIFO: adopted in Rechain, possible future plugin extraction

The adopted implementation keeps the data lookup and per-chain ordered ID maps. It replaces only the global sequence-to-key Map with head/tail references and nodes linked in insertion order. Each data entry supplies its node, so eviction, replacement and prefix deletion can unlink it directly. Append, head removal and unlink take a fixed number of link changes; the other cache maps still have their existing costs. Doubly linked lists support removal through a known node; established implementations embed links into the stored object. [Linux list implementation](https://www.kernel.org/doc/html/latest/core-api/list.html).

This does **not** implement LRU: reads must leave order unchanged. Do not replace the per-chain ID Map with FIFO because IDs can arrive out of order. Do not use an ordinary Queue with permanently retained tombstones: arbitrary deletion would leave ordering metadata proportional to historical churn rather than live cache size.

The private prototype became the exact adopted `Transactions.mo` source, SHA-256 `d98868f1b3d57b3a59817a7ff5fd228134649e3d5ff298fa8dfcabd2466beadf`, after a 315-sample five-variant cache comparison, 31 focused integration tests, 205 Muck checks and the combined application screen. At 100,000 records, oldest-evicting insertion batches use 23.06% fewer instructions than the Map baseline. Some deletion/churn allocations increase and the 10,000-record read batch regresses 2.08%; this is not a general memory-footprint win. [Rechain cache results and validation](https://github.com/Neutrinomic/rechain/blob/main/test/benchmarks/cache-collections-round2/README.md).

A reusable addressable FIFO plugin remains a possible future extraction, justified only after measuring generated-code/link-update overhead. The current ordinary-Motoko implementation uses managed nodes, copies no payloads, clears both neighbor links on removal and exposes no nodes. If a future public handle escapes, it needs defined invalidation and payload-release semantics; the private Cache avoids a general public handle owner/context system. Benchmark that extra generality rather than assuming the application result transfers unchanged.

The separate `Map.take(data, Nat.compare, key)` experiment was measured and not adopted. It improves some deletion paths, but missing-key removal changes tree work: at 1,000 records the Map-plus-take variant raises fill instructions 8.46% and allocation 11.50%. Plain FIFO was the more balanced choice; the existing lookup followed by removal remains.

## 2. Native Map minimum removal: broadest low-risk next plugin API

Takt and Reactor often call Motoko `Map.minEntry`, check the deadline, then call native `Map.remove` with a composite comparator. This repeats tree traversal and searches for a key whose exact position is already known. Rechain's per-chain cache prefix/lowest-ID eviction and Arena page release have related patterns; its global FIFO eviction no longer traverses an ordering Map.

A native `takeMin`/`popMin` can follow the leftmost child, remove that entry, repair the B-tree and return its existing pair, without invoking the key comparator. It retains the current Map representation and requires no persistent handles. Rust's BTreeMap exposes this operation as `pop_first`; it also offers a first-entry API for inspecting/removing the same entry. [Rust BTreeMap documentation](https://doc.rust-lang.org/std/collections/struct.BTreeMap.html#method.pop_first).

The deadline pre-check still matters: unconditional pop followed by reinsertion of a future deadline would be wasteful. Initially retain `minEntry` for that check and replace the generic removal. A conditional minimum-removal operation could later combine the descent if one predicate call and its API rules are justified. This is work in the Map plugin/module, not evidence that the SDK needs changing.

Do not reuse today's iterator across deletion: the Map contract invalidates it on mutation. Do not pre-remove a batch of Takt deadlines before executing handlers; handling one deadline can create another earlier deadline, and the current order and instruction budget must remain intact. A separate bounded bulk-delete operation may suit Rechain prefix cleanup, but must also perform the other indexes' accounting.

## 3. Exact timestamp buckets: promising only with shared deadlines

Use an outer scalar-Int Map or heap with one entry per distinct timestamp, and retain exact tie order inside each timestamp bucket. This can replace repeated composite comparator calls and reduce the outer index from `n` entries to `u` distinct timestamps. When almost every timestamp is unique, the extra bucket objects and second structure are likely a liability; no speedup is claimed without the actual distribution.

Takt's increasing wake tickets allow insertion-order buckets during normal operation, but cancellation requires removable nodes. Restore/migration must reconstruct buckets in ticket order rather than execution/node traversal order. Reactor's equal-deadline order uses **driver ID**, so an insertion-order bucket is incorrect; it needs an ordered ID collection or a small sorted vector. Rechain idempotency already uses exact timestamp buckets because it does not need arbitrary removal within a live bucket.

Measure `live deadlines / distinct timestamps`, bucket size distribution, cancellation ratio and timestamp changes on the real workload before implementing. Preserve arbitrary `Int` times and `Nat` tie keys; packing them into a fixed integer without proven bounds changes semantics. This proposal does not round time or fire early.

## 4. Small deadline vector: only for Reactor's few-driver index

A compact transient array with a cached minimum could avoid allocating a tree/heap node and a handle for each driver. Scan on minimum invalidation or deadline changes; repeated minimum reads use the cache. Preserve the exact `{at; driver}` ordering and clear removed slots. The application normally has a handful of library drivers, not one per workflow, so the relevant first sizes are 0, 1, 2, 4, 8 and 16, followed by a scaling check.

The tradeoff is linear update/recomputation work instead of logarithmic heap work. This is a small-library-index experiment, not a replacement for Takt's potentially large wake set. The different costs of arrays, binary heaps and indexed heaps are summarized by their textbook implementations. [Princeton priority-queue comparison](https://algs4.cs.princeton.edu/cheatsheet/). Avoid adding an adaptive two-representation system unless measurements justify its complexity.

## Lower-priority alternatives

A radix heap requires newly inserted priorities not to precede the last extracted priority. Takt permits arbitrary absolute `#Until(at)`, including a time in the past; “time moves forward” does not establish the necessary property. The restriction is explicit in a primary radix-heap implementation. [Akiba's radix heap](https://github.com/iwiwi/radix-heap). Restricting only Reactor's future-deadline path is a different candidate and still needs cancellation/tie handling; its small normal index makes it a low priority.

Timing wheels can suit large timeout sets when the precision and range contract allows them, but exact ordering inside buckets, long jumps and cascading costs require care. Linux deliberately uses an ordered tree for its precise timer subsystem, separate from its timeout wheel. This is an applicability lesson, not proof that all wheel designs are unsuitable. [Linux high-resolution timer design](https://docs.kernel.org/timers/hrtimers.html).

Pairing/Fibonacci heaps favor decrease-key/meld workloads; they do not directly solve Rechain's FIFO mismatch and add managed links and consolidation work. A 4-ary indexed heap remains a reasonable isolated algorithm experiment, but it still maintains unnecessary priority order for the cache and performs more child comparisons per level. These were already assessed in the [IPQ algorithm research](../indexed-priority-queue/algorithm-research-round-2.md).

Keep the current Map wherever the measured application workload favors it. Compare instructions, cumulative allocation and actual reclamation separately; a post-update heap sample includes garbage and is not retained-live memory. New mutable links and handles must use managed write barriers, clear removed references and pass existing GC/upgrade tests. No alternative here calls for unmanaged persistent Wasm memory or speculative SDK machinery.
