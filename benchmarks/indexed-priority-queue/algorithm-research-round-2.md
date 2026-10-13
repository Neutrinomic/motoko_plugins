# IndexedPriorityQueue: algorithm research for optimization round 2

Research date: 2026-10-12. This is a recommendation for experiments, not a claim of measured Motoko speedups. The baseline is the delivered binary heap frozen under `tmp/collections-optimization-round-2/baseline`, with native artifact SHA-256 `4cbe7359b0b4f88c6f520575ea92e9dc660e3689a20afa1a2e3344839df3c912`. Previous optimizations are documented in [OPTIMIZATION.md](OPTIMIZATION.md).

Keep the indexed array heap for this round. The strongest small experiments are caching immutable priorities and a scalar-only bottom-up pop. A uniform 4-ary heap is the strongest alternative structure to benchmark privately. Pairing and rank-pairing heaps become interesting for workloads dominated by actual priority decreases; they are not an obvious improvement for our current mix of arbitrary rescheduling, cancellation, and pop.

## Ranked experiments

| Rank | Candidate | Why it could help here | Cost or constraint | Recommendation |
|---|---|---|---|---|
| 1 | Cache the moving entry's priority once per sift | The generator caches the entry but reloads its immutable `priority` field at each level. Avoiding those loads needs no storage change. | An extra local/setup can cost more for operations with no movement. A priority object remains mutable through aliases; cache its reference, not a derived comparison result. | Measure first; retain only useful gains. |
| 2 | Bottom-up binary pop for proven scalar comparators | Choose the smaller-child path down to a leaf, then move the replacement back upward to its final position. This can avoid the replacement comparison at every descending level. | Extra upward movement costs array writes, handle updates, and GC barriers. Duplicate-heavy heaps and replacements near the root can regress badly. | Private candidate with equal-key and mixed-comparator tests; preserve the current callback path. |
| 3 | Uniform 4-ary indexed heap | About half as many levels as binary, hence potentially fewer handle-index writes and loop branches. Four is also cheap for index arithmetic. | More child loads/comparisons per level; custom callbacks and small heaps can lose. Changes the heap invariant and existing persisted contents, even if record types remain identical. | Only after the small candidates; measure all operations before accepting. |
| 4 | Cheaper direction selection for scalar repair | `reschedule` already has old and new priorities. If new > old, only down is needed; if new < old, only up is needed. Equal scalar keys need no repair. This can avoid parent array/entry loads in some cases. | Still needs one comparison, may cause an unnecessary sift call when the parent test would stop immediately, and changes callback traces if applied to callbacks. | Small isolated scalar candidate if rescheduling remains hot. |
| 5 | Bulk heap construction / combined pop-and-push | Bottom-up heapify avoids repeated insertion repairs; combined operations need only one heap repair. | Requires a useful new API/call site and correct handle lifetimes. These are not transparent speedups to the existing `push` and `pop` calls. | Keep as future API work, not a reason to expand this round. |

The existing scalar hole sift, cached entries, and separate scalar/callback generated helpers are already in the baseline. Repeating those changes is not a new optimization.

## What established implementations actually do

Rust's `BinaryHeap::pop` calls `sift_down_to_bottom`: it descends through the preferred child and then sifts back upward. Its ordinary downward repair remains a separate operation. This supports trying bottom-up specifically for pop, where the replacement comes from a leaf, rather than replacing every repair. Rust's heap has neither our externally readable handles nor Motoko GC barriers, so its speed is not evidence of our speed. [Rust source, `pop` and `sift_down_to_bottom`](https://github.com/rust-lang/rust/blob/master/library/alloc/src/collections/binary_heap/mod.rs).

CPython's `heapq` also descends before reinserting the replacement. Its source explains that repeated early-stop comparisons often do not pay during pop and reports reduced comparison counts in its own experiments. This is especially relevant when comparisons are costly, but those measurements are Python comparison counts, not IC instructions. [CPython source, `_siftup` and `_siftdown`](https://github.com/python/cpython/blob/main/Lib/heapq.py).

.NET uses an array-based quaternary heap with distinct default-comparer and custom-comparer paths. Its move-down scans up to four children; its combined enqueue/dequeue operations perform one repair, and bulk construction uses heapify. This is practical evidence for testing arity four, not a claim that four is universally optimal. Its public `Remove` scans for an element, unlike our handle-indexed removal. [.NET `PriorityQueue` source](https://github.com/dotnet/runtime/blob/main/src/libraries/System.Collections/src/System/Collections/Generic/PriorityQueue.cs).

Boost's mutable d-ary heap retains stable node locations and updates node indices when the array order changes. Its mutable wrapper introduces an extra indirection through list iterators. This confirms that stable handles and array heaps are compatible; it also makes clear that addressable queues carry costs absent from plain push/pop heaps. Our managed handles already provide the corresponding indirection without a separate linked list. [Boost d-ary heap](https://github.com/boostorg/heap/blob/master/include/boost/heap/d_ary_heap.hpp), [mutable wrapper](https://github.com/boostorg/heap/blob/master/include/boost/heap/detail/mutable_heap.hpp).

The experimental study *Priority Queues and Dijkstra's Algorithm* includes bottom-up binary, aligned 4-ary, standard indexed binary, and pairing heaps. Its results depend on operation mix and whether decrease-key support is needed. Its cache-aware and no-decrease-key results should not be transferred directly to an IC instruction comparison with addressable handles. [Chen et al., technical report](https://www3.cs.stonybrook.edu/~rezaul/papers/TR-07-54.pdf).

## Binary versus 3-, 4-, or 8-ary

For a full downward path, a simple d-ary heap does approximately `d × log_d(n)` comparisons: up to `d−1` to select a child, then one against the moving entry. This is an algorithmic estimate, not an instruction model. Binary and quaternary have the same leading comparison coefficient in this approximation; quaternary halves path length and therefore may reduce writes. Ternary has a slightly smaller comparison coefficient but less convenient index arithmetic. Eight reduces levels further but increases child scanning.

Our inference is that **4 is the first alternative worth measuring**, with 3 as a follow-up only if callback comparison cost dominates. Eight is lower priority. Our heap array stores references to entries, not inline priority/value pairs, so adjacent children still require loads from separate managed objects. CPU cache-alignment results for flat numeric heaps do not automatically apply.

Arity belongs to the queue's representation. A scalar operation using binary rules cannot safely alternate with a callback operation using quaternary rules on the same queue. A new arity also needs matching reference semantics, model validation, and an explicit treatment of old stable heap contents; a type-compatible Wasm upgrade alone cannot establish that those contents satisfy the new invariant.

## Bottom-up pop: exact adaptation requirements

Our callback comparators can inspect handles and entries between comparisons. The existing callback path completes each swap and both handle-index changes before the next callback. A hole temporarily duplicates entries and leaves the moving entry outside its final slot, so the bottom-up candidate should initially remain **proven-scalar only**. No callback purity assumptions are needed.

To retain the existing final array, choose the left child on equal priorities and, on the upward phase, move upward while `moving <= parent`, including equality. The current top-down algorithm stops before an equal child; the usual strict-less upward test can instead leave equal-key entries farther down. Even with unspecified tie order, preserving the current layout avoids unnecessary divergence between the interpreter and native execution and between subsequent scalar and callback operations.

Two separate algorithm checks support that equality rule: this research checked 7,400 seeded random root repairs with duplicate-heavy priorities, while an independent audit exhaustively checked 3,088 valid binary heaps of sizes 1–10 with priorities 0–2. Both found identical final layouts. These are algorithm-model checks, not Motoko tests or a proof of generated-code/GC correctness.

Unconditional bottom-up movement is particularly poor on an all-equal heap: the current sift stops immediately, whereas descending and returning to the top does logarithmic work. A single early-stop comparison at the root could protect that case, but adds work on long descents. Benchmark both the common case and this adverse case before selecting a variant. Arbitrary `remove`, `reschedule`, and `replace` often need little movement and should retain ordinary repair unless separately measured.

Keep all entry moves and index writes on managed SDK operations, with the existing conservative `Any` physical storage view. The moving entry and its priority remain managed locals. Reducing comparisons must not remove write barriers or leave popped handles attached.

## Pairing and rank-pairing alternatives

The original pairing heap is a linked, self-adjusting heap built around linking roots and combining children. It is a credible alternative for many decreases and melds. That design introduces child/sibling/back links and more pointer manipulation than our indexed array. [Fredman, Sedgewick, Sleator and Tarjan, original paper](https://sedgewick.io/wp-content/themes/sedgewick/papers/1986Pairing.pdf).

Rank-pairing heaps obtain Fibonacci-style amortized bounds with only one structural cut during decrease-key; rank changes can cascade. This improves theoretical decrease-key guarantees but adds rank maintenance and consolidation logic. [Haeupler, Sen and Tarjan, paper](https://www.cs.princeton.edu/courses/archive/spr10/cos423/handouts/rankpairingheaps.pdf).

For this plugin, arbitrary priority **increases** must also work, active handles must locate their queue, and removed handles must stop retaining it. Linked alternatives therefore still need ownership/invalidation machinery and careful GC cleanup. We have no meld API and no measured decrease-heavy workload justifying that complexity. Keep both as research alternatives; do not replace the binary heap solely for asymptotic decrease-key bounds.

Do not use lazy deletion as a transparent substitute for cancellation: stale entries would retain priorities/payloads and move cleanup cost to future pops. It conflicts with the existing prompt-release behavior and could inflate the heap under repeated rescheduling.

## Layout and API limits

The earlier mutable-priority/value entry experiment saved one 48-byte entry allocation per reschedule but added 48 bytes to every created entry and worsened several operations. Keep the immutable entry layout unless a materially different design wins on both the actual operation mix and memory.

Parallel priority/value/handle arrays could avoid entry allocations and some indirection, but multiply array accesses, resizing, and barrier work. More compact handles could reduce mutable-record overhead, but change stable representation and might require heterogeneous storage or additional type machinery. Neither is a small algorithm substitution. Do not add untyped storage or SDK complexity speculatively.

An O(1) clear based on shared generation tokens needs especially careful lifetime analysis: an old removed handle must not keep a context that still owns the live queue. The current O(n) clear detaches every owner. Fewer instructions without equivalent release semantics is not the same operation.

## Minimum experiment matrix

Compare against the frozen **current** implementation with identical compiler, plugins, paths, and counter harness. Include 1,000, 10,000, and 100,000 entries, plus small sizes and growth/shrink boundaries. Measure instructions and allocation separately for push, pop, remove, reschedule, replace, get, peek, clear, and steady churn.

Use descending, ascending, shuffled, all-equal, and small-domain duplicate priorities. Include real upward decreases, downward increases, and unchanged priorities. The existing descending-prefill benchmark with larger subsequent pushes is not enough to choose a heap algorithm. Include small Nat, large Nat/Int, and callbacks with composite priorities. For callback overhead comparisons, a wrapper around the same scalar comparator isolates overhead more cleanly than changing both comparator and key type.

For accepted code, run model/handle tests, mixed scalar/callback sequences, duplicate-key layout checks, allocating comparators, stale-handle release under real GC pressure, and the two-upgrade fixture. Report any operation regressions along with headline gains. No numerical improvement is predicted by this research alone.
