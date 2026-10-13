# HistoryRing algorithm research, round 2

Research date: 2026-10-12. This is a design assessment, not a benchmark result.
It examines the delivered segmented ring frozen in
`tmp/collections-optimization-round-2/baseline`, whose native plugin SHA-256 is
`844490083c0cf4f392d5f08dfc5dcdbc3480a0f4dcc0e9cc7b80c83f0ef236db`.
The previous optimization gains in [README.md](README.md) are the starting
point; they are not new gains for this round.

The current layout remains a good fit: a lazy directory of small managed
arrays gives constant-time sequence lookup without allocating storage for an
arbitrarily large declared capacity. The most promising work is simplifying
operations within that layout. There is no evidence yet that a more elaborate
data structure would improve the relevant workload.

## What established implementations suggest

| Primary source | Relevant technique | Application here |
|---|---|---|
| [Boost circular buffer insertion source](https://raw.githubusercontent.com/boostorg/circular_buffer/develop/include/boost/circular_buffer/base.hpp) and [overwrite rationale](https://www.boost.org/doc/libs/latest/doc/html/circular_buffer/implementation.html) | Full-buffer insertion replaces an element and advances positions without decrementing and incrementing the size. | Fuse eviction and append, avoiding redundant metadata writes. Our physical padding requires an extra case described below. |
| [Rust VecDeque source](https://doc.rust-lang.org/src/alloc/collections/vec_deque/mod.rs.html) | `wrap_index` uses conditional subtraction under a less-than-two-capacities bound. `as_slices` exposes contiguous runs across wraparound. | Benchmark conditional wrapping and copying runs within a chunk, avoiding a directory lookup for every returned element. |
| [CPython deque source](https://raw.githubusercontent.com/python/cpython/main/Modules/_collectionsmodule.c) | Fixed blocks of 64 references reduce allocation and link overhead; sequential traversal advances an index and changes blocks only at boundaries. Its linked-block random access still traverses blocks. | Preserve our indexed directory, and borrow the inexpensive block cursor for pages. A linked-block replacement would lose constant-time middle lookup. |
| [Linux circular-buffer documentation](https://docs.kernel.org/core-api/circular-buffers.html) | Power-of-two buffers permit bit masking, and processing a contiguous range avoids crossing the physical boundary repeatedly. | Useful arithmetic ideas, but arbitrary HistoryRing capacities prohibit unconditional masking. The concurrent producer/consumer machinery is unnecessary for these synchronous Motoko operations. |
| [Boost space-optimized circular buffer overview](https://www.boost.org/doc/libs/latest/doc/html/circular_buffer.html) | Storage can grow as elements arrive instead of reserving the entire capacity. | Supports retaining lazy allocation as a deliberate capability, rather than replacing it with an eager fixed array. |

These sources establish techniques and their tradeoffs, not Motoko speedups.
In particular, replacing a divide instruction with several branches may help
native CPU timing without reducing IC instruction charges. PocketIC counters
must decide which arithmetic form to keep.

## Ranked experiments

| Priority | Experiment | Expected mechanism | Cost and acceptance evidence |
|---:|---|---|---|
| 1 | Fuse full-ring overwrite | Remove the eviction helper call, discarded old-value load, repeated geometry loads, and size decrement/increment. | No layout change. Test both exact physical capacity and padded capacities; measure allocation as well as instructions. |
| 2 | Page with a cached chunk and slot cursor | Resolve a directory entry once per visited chunk instead of once per output item. | No persistent state or extra output allocation. Compare pages of 0, 1, 32, 64, 65, and larger sizes, including wrapped boundaries. |
| 3 | Detach complete chunks during bulk drop | One directory write can release a wholly removed chunk instead of clearing every element slot. | Boundary fragments still need clearing. Check wrapped shared chunks, refill behavior, and real reference release under GC. |
| 4 | End-relative sequence lookup | One arbitrary-precision difference can replace two, followed by bounded machine arithmetic. | Preserve arbitrary `Nat` sequences; benchmark valid, evicted, future, and empty reads, including very large sequences. |
| 5 | Conditional-subtraction wrapping | Replace remainder when the operand is known to be below twice the physical span. | Small implementation change; keep only if metered instructions improve. Do not apply where the bound is unproved. |

### 1. Fused overwrite

Let `n` be the retained size, `h` the head slot, `w` the chunk width, and
`span = directory.length * w`. When `n == capacity > 0`, the current append
first removes one value, writes `size = n - 1`, then appends and restores
`size = n`. No user callback runs between those steps.

The fused operation can calculate the destination as `(h + n) % span`, advance
the head to `(h + 1) % span`, and leave the size unchanged. It still stores the
new sequence and returns the old sequence. When `n == span`, the destination is
the old head and a single managed overwrite releases the old reference. When
`n < span`, the old head and destination differ: clear the old slot and write
the destination. For example, capacity 1,000 has 1,024 physical slots, so
blindly overwriting the head would corrupt ordering.

Cache geometry in locals rather than adding record fields. Destination chunk
allocation remains necessary if that chunk has not yet been materialized.
Use existing SDK managed writes with the conservative `?Any` view; deleting a
redundant clear must not delete the actual overwrite barrier.

### 2. Chunk cursor for pages

After sequence validation and count clamping, compute the first physical slot
once. Maintain a local directory index, slot index, and current managed chunk.
Read successive slots directly; resolve another chunk only on a boundary.
The output remains a fresh immutable array sharing the original payloads.

Do not load the next chunk after producing the last requested value: that
chunk may correctly be absent. Empty pages must not resolve any chunk. Pages
at capacities below 64 also wrap at their actual stored width, not at 64.

A similar persistent iterator could retain old chunk references after
`clear`, whereas the current iterator captures the ring and calls `get`.
That lifetime tradeoff needs a separate review. The temporary page cursor
does not introduce it.

### 3. Drop complete chunks

For a partial drop, the removed prefix has length less than `size`, and
`size <= span`. Split that prefix into an initial partial chunk, zero or more
complete physical chunks, and a final partial chunk. Clear partial fragments
through ordinary slot writes. A complete chunk entirely inside the removed
interval contains no retained slot and can be detached by clearing its
directory entry through the SDK.

This is a plugin-specific inference from managed reachability: unlike a C++
container, HistoryRing has no per-element destructor to execute. Representation
fields are private by contract. Detachment releases the ring's reference to
the entire chunk; actual reclamation still follows the collector schedule.

The head and wrapped tail can share a chunk. Never infer that a partially
consumed chunk is dead merely because a cursor crossed its end; preserve the
existing retained-range guard for such fragments. Full removal already resets
the directory in constant work and should retain that path.

### 4. End-relative lookup

For `get(sequence)`, first reject `sequence >= next`. Compute
`distance = next - sequence` using the existing arbitrary-precision-safe
subtraction, and reject `distance > size`. Only then convert `distance` to a
machine word and use `offset = size - distance`.

This avoids computing both `first = next - size` and `sequence - first`.
The proof that `distance <= size` must precede conversion; otherwise an
evicted, very old sequence could cause a narrowing failure. Empty rings and
huge future sequences are useful regression cases. The same principle may
simplify page bounds, but a standalone lookup change is easier to measure.

## Structural alternatives

| Alternative | Potential benefit | Why it is lower priority |
|---|---|---|
| One growable contiguous array | One fewer indirection; straightforward sequential copies. | Growth copies all retained references, creates larger allocation spikes, and complicates releasing storage after large drops. An eager capacity-sized array also violates lazy construction for huge capacities. |
| Power-of-two physical directory/span | Cheap masking at wraparound. | The current final directory can have a non-power-of-two length. Rounding it up increases spare storage and can eventually retain nearly twice as many allocated physical slots during long overwrite streams. Logical capacity still needs separate handling. |
| Larger chunks, such as 128 or 256 | Fewer directory entries, allocations, and boundary crossings. | More allocation on the first append to a large-capacity ring, more slack, and larger boundary fragments to clear. Worth an isolated parameter experiment only after the hot-loop changes. |
| Linked blocks | Simple append/pop without copying a directory. | Middle lookup would traverse blocks unless a separate index is retained, which returns us to the present design with more links. |
| Tree or trie of chunks | Bounds directory-growth copying and could support additional persistent operations. | Extra pointer traversals and nodes on ordinary reads; no current requirement justifies replacing direct indexed lookup. |
| Extra cached head/tail/first fields | Fewer arithmetic operations in some methods. | Every mutation must maintain them, and mutable fields consume managed cells. Prefer local caching before enlarging every ring. |

## Measurement and correctness gates

Measure against the frozen delivered plugin, using identical source paths,
compiler, RTS, benchmark code, and checksums. Preserve the Core control. Use
small targeted runs while selecting candidates, then repeat the accepted
version over capacities 0, 1, 63, 64, 65, 1,000, 10,000, and 100,000, including
head wrap and partial-drop/refill cases. Existing capacity- and sequence-boundary
model tests remain important; add specific regressions for each changed branch.

Report metered instructions, allocated bytes, directory/chunk reachability,
and observed GC counters separately. An unchanged allocation count can still
accompany a useful instruction reduction; an arbitrary post-GC heap sample is
not proof of live container memory. Re-run generic nullable/reference cases,
incremental-GC pressure, and upgrade tests for accepted generated-code changes.
None of the leading experiments requires a compiler/SDK change or a public
representation change.
