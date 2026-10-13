# CandidX

`CandidX.encode(...) : { #ok : Blob; #err : Text }` encodes Motoko values directly into the
CandidX `cx` canonical profile. The compiler specializes traversal, sizing,
and writing for the argument types. A Rust Wasm helper handles dynamic shapes.

```motoko
import CandidX "mo:fast/CandidX";
switch (CandidX.encode({ height = 42; memo = ?"hello" })) {
  case (#ok encoded) { /* use the canonical Blob */ };
  case (#err message) { /* invalid input or an encoding limit */ };
};
```

Build with `scripts/build.sh --motoko /path/to/motoko candidx`, then pass
`--plugin /path/to/plugins/dist/candidx` and
`--package fast /path/to/plugins/packages/fast/src` to the matching compiler. See the
[repository build instructions](../../README.md#build-and-use).

`compiler/` contains registration, typed code generation, and the interpreter
reference. `runtime/` contains the Rust kernel. `tests/` contains Motoko
fixtures and the adapter for the CandidX repository's fuzz and conformance
tests. Ordinary Motoko `to_candid` and `from_candid` are unaffected.

Canonical types depend on values, absent optional record fields are omitted,
and NaNs are normalized. Limits are 32 MiB output, 2,000,000 visited items,
1,024 output types, depth 256, and 256 MiB scratch allocation per call.
Unsupported actual function or service values, invalid schemas, and encoding
limits return `#err(message)` in both interpreters and compiled Wasm. Successful
calls return `#ok(bytes)`. Error propagation releases no persistent resources;
all scratch allocations are reclaimed by Motoko's ordinary GC.

This is a typed intrinsic: inferred aliases preserve specialization, while
ordinary function annotations cannot erase its identity. Wrap calls in an
explicitly typed Motoko function when passing an encoder as a callback.

## Fast size estimates

`CandidX.estimateSize(...) : Nat` estimates the byte size of ordinary Motoko
`to_candid(...)`, including its original type table. Use it when an admission
bound is sufficient; it does not estimate the canonical encoder's exact output.

```motoko
if (CandidX.estimateSize(value) > byteLimit) { /* reject or defer */ };
```

The compiler calculates schema bounds and fixed payload widths. Generated Wasm
reads Blob/Text byte lengths directly, multiplies fixed-width array lengths,
and visits only value-dependent structures. Compact Nat/Int values use a
nine-byte bound; larger integers use magnitude tiers without allocating,
including negative Ints. No encoding buffer or scratch heap is allocated.
Argument construction can still allocate in the caller.

The result conservatively bounds every Blob ordinary `to_candid` can produce.
Estimates can be loose and reject values whose actual encoding would fit.
Functions encountered in the value, dynamic traversal depth above 256, exhausted one-million
dynamic-visit budget, or a saturated size return **`2 ** 61 - 1`**. Treat this
sentinel as too large or too expensive to estimate. A deeply nested small value
can therefore be rejected. Shared service references are supported; absent
options and unselected variants containing functions do not trigger rejection.
Values erased to `Any` have no Candid payload and are not traversed.

[PocketIC results](../../benchmarks/candid-size/README.md) compare the estimator
with allocating an ordinary Candid Blob for its exact size. These are different
size contracts, not an encoding throughput comparison.

See [the design and validation](../../docs/design.md) and
[benchmark reproduction](../../benchmarks/README.md). Compiler and runtime
sources retain their MIT license files.

The public module is distributed in the [`fast` Mops package](../../packages/fast/).
