# Queue

`mo:fast/Queue` follows the public function interface of `mo:core/Queue` with
native push, pop, and peek operations on both ends, plus direct array export. Load `dist/queue` when
compiling. Its managed representation is stable whenever the element type is
stable; existing Core queue values require explicit conversion.

Storage is a doubly linked sequence of circular 32-element chunks. Chunks are
allocated lazily; endpoint operations never copy the whole queue. Popping clears
the vacated slot. At most one empty chunk is retained for reuse, either a detached
spare while the queue is nonempty or its final empty endpoint chunk. This avoids
reallocating a chunk on every push/pop at a chunk boundary; `clear` releases it. Generic values remain references to
ordinary Motoko values, including mutable objects, nested options and closures.

All representation fields are private by contract, matching fast Map and Set.
Mutation invalidates iterators. Traversal callbacks must not mutate the queue
being traversed. `clone` copies queue storage and shares payload references.

Both interpreter semantics and native code generation implement the same
operations. The plugin uses ABI 1 managed array/object writes and their existing
GC barriers; no compiler or runtime change is required.

Chunk metadata packs its start slot into the low five bits of one `Nat32` and
its occupied count (0..32) into the remaining bits. A detached spare has zero
metadata, null links, and only null slots. An empty retained endpoint may keep
its previous start slot; its count and all slots are zero/null.

This preproduction packed representation replaces the earlier separate
`start`/`count` fields and changes the stable storage shape. Existing stored
queues from that experimental format require migration or recreation; this
plugin does not provide a legacy representation adapter. Stable upgrade tests
cover queues created in the new format.
