# Managed array movement SDK regression

This test-only compiler plugin calls `B.Arr.move_within` directly. It does not
add a primitive or API to `mo:fast`. The evaluator is a snapshot-copy oracle,
independent of the Wasm generator's movement direction.

Run inside the selected compiler's build environment:

```sh
python3 tests/managed-array-move/build.py --motoko /path/to/sdk
node tests/managed-array-move/runtime.mjs
```

The model enumerates all 825 valid source/destination/length combinations for
array lengths zero through eight. Additional cases cover nullable mutable
payload identity, copied closures, and exactly-once left-to-right operand
evaluation. The build runner executes the model in the source, IR, lowered IR,
and Wasm engines. The Wasm actor repeats these cases, then moves pointer payloads
under forced GC on a fragmented heap, checks invalid ranges (including unsigned
overflow), and upgrades with live moved references. The runner owns its private
PocketIC server and removes its temporary directory on exit.

`--output DIR` selects build artifacts; set `MOVE_TEST_BUILD=DIR` for the runtime
runner. `PIC_PACKAGE_DIR` and `POCKET_IC_BIN` select the Node client and server.
These are correctness regressions, not throughput measurements.
