# Managed array prefix SDK regression

This test-only compiler plugin calls `B.Arr.with_prefix` directly, reversing a
validated logical prefix into a newly allocated immutable array. No production
primitive or `mo:fast` API is added. Every borrowed load index is proved in range
by the output tabulation loop; neither the body nor any callee has a GC safepoint.

Run inside the selected compiler's build environment:

```sh
python3 tests/managed-array-prefix/build.py --motoko /path/to/sdk
node tests/managed-array-prefix/runtime.mjs
```

For both mutable and immutable sources, the model checks every logical prefix
of every array length zero through sixteen: 306 cases. The oracle snapshots
source values and checks every output index. Additional cases exercise nullable
mutable payload identity, copied closures and once-only operand evaluation in
order. Output allocation occurs inside the borrowed cursor's lifetime.

The build runner executes the model in source, IR, lowered IR and Wasm engines.
The PocketIC actor repeats it, then borrows fragmented arrays over sixteen forced
GC executions and requires an observed change in their resolved element address.
It verifies copied payloads, rejects invalid prefix lengths including Nat64
overflow boundaries, and upgrades with live source and copied references.

`--output DIR` selects build artifacts; set `PREFIX_TEST_BUILD=DIR` for the runtime
runner. `PIC_PACKAGE_DIR` and `POCKET_IC_BIN` select the Node client and server.
The private PocketIC server and temporary instance directory are removed on exit.
These are correctness checks; no performance claim is made.
