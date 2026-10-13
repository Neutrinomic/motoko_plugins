# Queue

`mo:fast/Queue` follows the public function interface of `mo:core/Queue` with
native push, pop, and peek operations on both ends. Load `dist/queue` when
compiling. Its managed representation is stable whenever the element type is
stable; existing Core queue values require explicit conversion.

Storage is a doubly linked sequence of circular 32-element chunks. Chunks are
allocated lazily; endpoint operations never copy the whole queue. Popping clears
the vacated slot and releases exhausted chunks. The sole final empty chunk stays
available for reuse; `clear` releases it. Generic values remain references to
ordinary Motoko values, including mutable objects, nested options and closures.

All representation fields are private by contract, matching fast Map and Set.
Mutation invalidates iterators. Traversal callbacks must not mutate the queue
being traversed. `clone` copies queue storage and shares payload references.

Both interpreter semantics and native code generation implement the same
operations. The plugin uses ABI 1 managed array/object writes and their existing
GC barriers; no compiler or runtime change is required.
