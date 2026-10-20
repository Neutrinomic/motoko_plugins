# SHA-256

`SHA256.digest(Blob) : Blob` computes a 32-byte SHA-256 digest. It is a compiler
intrinsic backed by a one-shot Rust Wasm kernel.

```motoko
import SHA256 "mo:fast/SHA256";
let digest = SHA256.digest("abc");
assert SHA256.digestParts(["a", "", "bc"]) == digest;
```

Inferred aliases preserve the intrinsic. Use an ordinary Motoko wrapper when
passing the operation as a callback or storing it in a function-typed field:

```motoko
func hash(bytes : Blob) : Blob { SHA256.digest(bytes) };
let callbacks : [Blob -> Blob] = [hash];
```

Build with `scripts/build.sh --motoko /path/to/motoko sha256`, then pass
`--plugin /path/to/plugins/dist/sha256` and
`--package fast /path/to/plugins/packages/fast/src` to the matching compiler. See the
[repository build instructions](../../README.md#build-and-use).

`compiler/` contains registration, direct Blob access, and an interpreter
reference. `runtime/` contains the Rust kernel and its native unit tests.
`tests/` contains Motoko fixtures. The kernel reads the input in place and
allocates only the result Blob; it retains no state between calls.

`SHA256.digestParts([Blob]) : Blob` hashes the concatenated bytes of its parts
without creating a combined payload. The compiler borrows each immutable Blob
through its normal forwarding barriers and creates a 16-byte descriptor per part.
The Rust kernel reads complete SHA blocks directly from each part; only blocks
crossing part boundaries use its fixed 64-byte stack buffer. Empty parts and an
empty array are supported. This operation allocates the descriptors and result,
and retains no pointers or hash state after returning.

The implementation includes specialized empty, 32-byte, and 64-byte paths.
See [the design](../../docs/design.md) and
[PocketIC measurements](../../benchmarks/README.md).

The public module is distributed in the [`fast` Mops package](../../packages/fast/).
