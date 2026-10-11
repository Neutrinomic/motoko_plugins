# Set garbage collection coverage

`SetGC.mo` runs on PocketIC through Ash with `--sanity-checks --force-gc` and
only the mutable-set native plugin loaded. It deliberately mixes immediate
Bool/Nat8 native specializations with records, text, nested optional elements,
mutable payloads, and closures in the same canister.

The test keeps 96 MiB of live arrays between interleaved dead allocations so
collection cannot finish in one slice. It checks that a pending collection was
observed, that collection later completed, and that at least 32 MiB was reclaimed.
Point replacement, sibling borrowing/merging, splitting, nested comparator reads,
other-set mutation, and allocation run across message boundaries during GC.
Final checks retain an iterator without subsequent set mutation.

This covers a native helper-sharing regression: mutable-set helpers are reused
across element types, so all slot stores must retain their write barriers even
when the first specialization stores immediate scalar values. Direct intrinsic
calls exercise this compiler specialization case; construction, traversal, and
invariant checks use `mo:fast/Set`.

Both Ash tests pass with the fixed plugin. Running the identical source against
the preserved plugin from before the barrier fix fails the GC test with an RTS
panic in `gc/incremental/phases/mark_increment.rs`:
`assertion failed: !value.is_forwarded()`. The scalar test still passes. The last
declared scalar query is emitted first by the compiler, ensuring the test
actually exercises scalar-first native helper sharing.

```sh
scripts/test-ash.sh SetGC
```

The reported Ash metrics cover the final synchronous verification only. This
is a correctness stress test, not a performance benchmark.
