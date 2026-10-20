# RRT plugins on memory32 and memory64

Run after building Tripwire and the five matching plugins:

```sh
python3 tests/wasm32/run.py --motoko /path/to/tripwire \
  --output /tmp/tripwire-plugin-wasm32-test
```

The output directory must be fresh. The runner compiles the same actor for
default memory32 and explicit memory64 at both ICWire optimization levels.
An additional compile checks default and explicit `--wasm32` byte identity.
It checks the memory/table types with `wasm-objdump` and validates each module.

One owned PocketIC server executes four canisters. A small independent host
ICWire encoder checks automatic endpoints, the eight explicit operations,
malformed-input errors and recovery, fixed-width and arbitrary integers,
Unicode, options, variants, and a 64-KiB Blob. Node's SHA-256 checks single and
segmented hashing against independently computed answers. Managed Map, Queue
and HistoryRing entries, a shared mutable cell and closures survive message
boundaries, mutation and confirmed reclamation. These are correctness tests,
not throughput benchmarks.

Compiler, runtime, plugin, source and output hashes and actual child-process
exit codes are retained. Set `POCKET_IC_BIN` to choose the server and
`PIC_PACKAGE_DIR` to choose the installed `@dfinity/pic` package.

Plugin kernels are built with 64-bit words, including their Rust `usize` and
pointer ABI. Tripwire lowers the fully linked module to memory32 afterward.
The same plugin package supports both final targets; rebuilding kernels as
native Rust wasm32 would change the ABI and SHA256 part-descriptor layout.
