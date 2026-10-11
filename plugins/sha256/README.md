# SHA-256

`Prim.sha256(Blob) : Blob` computes a 32-byte SHA-256 digest. It is an ordinary
first-class Motoko function backed by a one-shot Rust Wasm kernel.

```motoko
import Prim "mo:⛔";
let digest = Prim.sha256("abc");
```

Build with `scripts/build.sh --motoko /path/to/motoko sha256`, then pass
`--plugin /path/to/plugins/dist/sha256` to the matching compiler. See the
[repository build instructions](../../README.md#build-and-use).

`compiler/` contains registration, direct Blob access, and an interpreter
reference. `runtime/` contains the Rust kernel and its native unit tests.
`tests/` contains Motoko fixtures. The kernel reads the input in place and
allocates only the result Blob; it retains no state between calls.

The implementation includes specialized empty, 32-byte, and 64-byte paths.
See [the design](../../docs/design.md) and
[PocketIC measurements](../../benchmarks/README.md).
