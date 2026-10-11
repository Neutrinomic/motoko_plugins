# CandidX

`Prim.to_candid_canonical(...) : Blob` encodes Motoko values directly into the
CandidX `cx` canonical profile. The compiler specializes traversal, sizing,
and writing for the argument types. A Rust Wasm helper handles dynamic shapes.

```motoko
import Prim "mo:⛔";
let encoded = Prim.to_candid_canonical({ height = 42; memo = ?"hello" });
```

Build with `scripts/build.sh --motoko /path/to/motoko candidx`, then pass
`--plugin /path/to/plugins/dist/candidx` to the matching compiler. See the
[repository build instructions](../../README.md#build-and-use).

`compiler/` contains registration, typed code generation, and the interpreter
reference. `runtime/` contains the Rust kernel. `tests/` contains Motoko
fixtures and the adapter for the CandidX repository's fuzz and conformance
tests. Ordinary Motoko `to_candid` and `from_candid` are unaffected.

Canonical types depend on values, absent optional record fields are omitted,
and NaNs are normalized. Limits are 32 MiB output, 2,000,000 visited items,
1,024 output types, depth 256, and 256 MiB scratch allocation per call.
Unsupported actual function or service values and invalid schemas trap.

This is a typed intrinsic: inferred aliases preserve specialization, while
ordinary function annotations cannot erase its identity. Wrap calls in an
explicitly typed Motoko function when passing an encoder as a callback.

See [the design and validation](../../docs/design.md) and
[benchmark reproduction](../../benchmarks/README.md). Compiler and runtime
sources retain their MIT license files.
