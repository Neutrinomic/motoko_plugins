# History ring

`mo:fast/HistoryRing` stores bounded histories under arbitrary-precision Nat
sequence numbers. The module follows the self-first functional API used by
`mo:fast/Map` and `Set`; its mutable managed representation is stable whenever
the payload type is stable. All representation fields are private by contract.

`empty(capacity)` allocates no element storage. `emptyAt(capacity, nextSequence)`
starts an empty history at an existing sequence for migrations or copies. Append retains the newest
`capacity` values and returns their absolute sequence number. Capacity zero
still advances the sequence. `get(sequence)` is direct indexed access;
`page(from, limit)` starts inclusively, clamps stale cursors to the oldest
retained entry, and allocates only its returned array. `popFront`, `drop` and
`clear` preserve the next sequence. No operation clones payload graphs.

Storage uses lazy 64-entry chunks (smaller for capacities under 64) with a
geometrically grown directory. Growth copies chunk references and at most one
boundary chunk, never the whole history. At most `capacity + 63` element slots
are retained; explicit removal releases fully consumed chunks and clearing
releases the directory. The directory retains its high-water length during
partial removal, while consumed chunks are released; this retained reference
array is bounded by the configured capacity. Eviction reuses existing chunks. Ordinary point
operations are constant time; growth is amortized constant time. Pages are
linear in their output length. Partial drops discard complete chunks with one directory write each and clear
only boundary fragments. Dropping all entries is constant time. Iterators are invalidated by mutation.

The plugin emits Wasm at compilation time and has no separate runtime module or
foreign persistent memory. All writes use SDK managed heap barriers, with a
conservative generic physical slot type for nullable values.
