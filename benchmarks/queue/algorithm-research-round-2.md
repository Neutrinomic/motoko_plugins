# Queue algorithm research, optimization round 2

Research date: 2026-10-12. This is a proposal, not a new performance result.
The control is the delivered 32-slot circular-chunk Queue, frozen in
`tmp/collections-optimization-round-2/baseline`: native plugin SHA-256
`57e9a26e9f560f2486aedc158ea143d25bd7023b0cc5085f2990c95dc5578242`,
module SHA-256 `921db27b88350ca8bcc472278494fdc4b0505bf94279e811d6120511533ddc4d`.

Keep the chunked deque as the default. It already gives constant bounded
structural work at either endpoint, no whole-queue growth copy, shared payload
references, and bounded spare retention. First remove avoidable generated-code
costs; consider a smaller metadata layout only after measuring those changes.
No algorithm can be called the fastest here from desktop cache benchmarks:
our primary measures are IC instructions, managed allocation and retention.

## Practical algorithm choices

| Design | What established implementations demonstrate | Fit for this plugin |
|---|---|---|
| Doubly linked fixed blocks | CPython 3.14 uses 64-element blocks, endpoint indices and a bounded free-block cache. Growth does not relocate existing elements. [Source](https://github.com/python/cpython/blob/v3.14.0/Modules/_collectionsmodule.c) | Strong default for variable-sized queues and predictable endpoint work. Our circular chunks and one spare already provide most of this benefit. |
| Growable circular array | Rust `VecDeque` provides amortized O(1) endpoints and O(1) indexing. OpenJDK `ArrayDeque` grows and copies its reference array. [Rust documentation](https://doc.rust-lang.org/std/collections/vec_deque/index.html), [OpenJDK 25 source](https://github.com/openjdk/jdk/blob/jdk-25-ga/src/java.base/share/classes/java/util/ArrayDeque.java) | Fewer chunk/metadata objects and simple traversal, but occasional O(n) reference copying, temporary old/new arrays and retained high-water capacity unless explicitly shrunk. Worth an isolated alternative only if instruction throughput outweighs endpoint latency. |
| Directory of fixed blocks | libc++ deque stores block pointers in a resizable directory and reuses spare blocks. Directory growth moves block pointers rather than all element slots. [LLVM 21 source](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.0/libcxx/include/deque) | Attractive if indexed access becomes necessary. For our endpoint API, another directory, capacity policy and growth copy are hard to justify over linked chunks. |
| Small representation, then larger storage | LLVM `SmallVector` reserves inline elements, while `TinyPtrVector` optimizes zero/one elements under pointer/non-null restrictions. [LLVM manual](https://llvm.org/docs/ProgrammersManual.html#llvm-adt-smallvector-h) | Motivated by our cold singleton cost, but Motoko managed records do not inherit C++ stack-inline storage. A singleton variant or small initial array adds dispatch or variable-capacity handling; generic nullable values must remain valid. |

These are algorithm/layout choices, not features unique to plugins. They can
also be implemented in ordinary Motoko. Native code generation separately
controls helper calls, repeated metadata loads, tagging and loop overhead.

## Ranked experiments

1. **Simplify peeks and pop metadata access without changing storage.**
   `read_chunk` currently loads count and start, tests count, then masks even
   the front index. Every slot of a retained empty chunk is null. Therefore a
   front peek can return `values[start]` without loading count; a back peek can
   return `values[(start + count - 1) & 31]` without a separate count-zero branch.
   This preserves `?T`, including stored null/option values: the existing outer
   option representation distinguishes occupancy. Keep the endpoint-null check
   and SDK array checks. Pop can cache `values` across its read and clear, and
   defer loading start until count is nonzero. These are local invariant-based
   simplifications, not weaker GC handling. OpenJDK similarly uses cleared slots
   to recognize empty endpoints, although its ban on null payloads must not be
   copied into our API. [Source](https://github.com/openjdk/jdk/blob/jdk-25-ga/src/java.base/share/classes/java/util/ArrayDeque.java)

2. **Measure cheap-operation inlining and cursor specialization.**
   All native Queue helpers currently use `Func.Always`. Benchmark direct
   emission for small peeks while evaluating their queue argument exactly once;
   record Wasm-size cost. Inspect whether `cursor(self, reverse)` leaves a
   direction branch in each `next()`. Separate directional closures only if the
   compiler has not already removed it. Preserve the exhausted iterator's
   explicit release of its final slots array.

3. **Batch existing bulk operations.**
   `clone` and array construction currently pass through iterators and repeated
   `pushBack`. A native builder can fill fresh chunks and establish metadata
   once per chunk, keeping the public API and sharing payload references. This
   addresses per-element calls/stores; it does not improve endpoint asymptotics.
   The same block-at-a-time principle appears in libc++ bulk append.
   [Source](https://github.com/llvm/llvm-project/blob/llvmorg-21.1.0/libcxx/include/deque)

4. **Pack chunk geometry into one Nat32, if a layout experiment is warranted.**
   Five bits hold start and six hold count, including count 32. One mutable field
   could replace two, reducing managed metadata and allowing one geometry update
   for front push/pop. Masks/shifts add work, so benchmark before adopting.
   This preserves circular chunks and is a smaller redesign than moving all
   indices into the queue. It requires coordinated schema/reference/module
   changes and upgrade validation; it is not a source-only micro-optimization.

5. **Compare a few block sizes or a small initial representation only with
   workload evidence.** Larger power-of-two blocks amortize metadata and
   allocation transitions, but worsen cold/sparse queues and retained spare
   size. The present 440-byte first chunk already loses to Core for a singleton.
   A 4-slot starter can reduce that cost, but variable capacity adds hot-path
   work. Do not assume CPython's 64 is optimal for this GC and instruction meter.

## Alternatives to defer

A CPython-style endpoint-index layout could remove per-chunk count/start cells.
It is a full invariant change: CPython's blocks are linear, whereas our full
chunk may wrap from a nonzero start. Simply deleting our per-chunk metadata
would lose that geometry. Its potential reduction in endpoint metadata loads
is worth a private prototype after cheaper changes, not a blind translation.
[CPython layout](https://github.com/python/cpython/blob/v3.14.0/Modules/_collectionsmodule.c)

Two-stack queues introduce occasional reversal work and do not naturally cover
this mutable deque API. Tree-based persistent deques add structure we do not
need for a mutable queue without snapshot requirements. Lock-free/SPSC designs
address concurrent access rather than this sequential canister execution model.
None is an obvious replacement for the existing workload.

All candidates must retain ordinary managed references, conservative generic
write barriers, clearing of popped slots, detached spare links, stable storage
when `T` is stable, and identical interpreter semantics. Array growth copies
references, not deep payload objects, but still creates GC-visible allocation
and copying work.

Use the current PocketIC harness and frozen control at sizes 0/1/4/16/31/32/33,
1k/10k/100k. Include both endpoint directions, full-block LIFO churn, warmed
singleton reuse, forward/reverse traversal and export. Report instruction and
allocation changes separately; verify boundary-heavy models, generic/null
payloads, GC and upgrade behavior for accepted changes. Reclamation needs the
existing controlled-pressure probe, not arbitrary sampled heap deltas. Reject
complexity or regressions that do not pay off in the application workload.
