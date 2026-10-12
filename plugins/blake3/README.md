# BLAKE3

`import BLAKE3 "mo:fast/BLAKE3"` with `--plugin dist/blake3` enables portable
BLAKE3 hashing, keyed hashing, context-separated key derivation, immutable
incremental states and seekable extended output.

```motoko
let digest = BLAKE3.digest("hello");
let start = BLAKE3.new();
switch (BLAKE3.update(start, "hello")) {
  case (#ok(state)) {
    assert BLAKE3.finalize(state) == #ok(digest);
    ignore BLAKE3.finalizeXof(state, 64, 128);
  };
  case (#err(_)) assert false;
};
```

| Operation | Arguments | Result |
| --- | --- | --- |
| `digest` | data: Blob | 32-byte Blob |
| `keyedHash` | key: Blob, data: Blob | Result<Blob> |
| `deriveKey` | context: Text, material: Blob | 32-byte Blob |
| `xof` | data: Blob, offset: Nat64, length: Nat32 | Result<Blob> |
| `new` | () | State |
| `newKeyed` | key: Blob | Result<State> |
| `newDeriveKey` | context: Text | State |
| `update` | state: State, data: Blob | Result<State> |
| `finalize` | state: State | Result<Blob> |
| `finalizeXof` | state: State, offset: Nat64, length: Nat32 | Result<Blob> |

`Result<T> = { #ok : T; #err : Error }`; errors are `#invalidKey`,
`#invalidState`, `#outputTooLarge`, `#inputTooLong`, and `#invalidSeek`.
Keys are exactly 32 bytes. Each output is limited to 16 MiB; request successive
ranges for longer XOF output. Offset plus length and accumulated input must fit
in unsigned 64 bits. Empty output at the maximum offset is valid. Output limit
and seek failures precede state validation in `finalizeXof`.

Derivation follows both BLAKE3 stages: hash the UTF-8 context with
`DERIVE_KEY_CONTEXT`, then hash key material with `DERIVE_KEY_MATERIAL` and that
context key. Changing the context changes the result. `blake3@0.1.2` on Mops
ignores its context argument, so that operation is not a correctness baseline.

## Implementation and memory

The Wasm64 kernel uses upstream `blake3 = 1.8.7`, with default features disabled
and `pure` enabled: no C assembly, thread pool, native heap allocations, or
retained hash state or pointers. Complete one-shot operations use upstream complete-message hashing
functions. Streaming uses upstream chunk/parent hashing primitives, with extensive
differential tests against Hasher to verify the binary tree shape. Interpreter
semantics use independent portable OCaml compression and tree code.

`State` is a managed immutable Blob. Its 2816-byte canonical encoding contains:

| Offset | Contents |
| --- | --- |
| 0 | `B3S1` version marker |
| 4 | mode: 0 hash, 16 keyed hash, 64 derive material |
| 5 | 3 zero reserved bytes |
| 8 | 32-byte key (zero in unkeyed mode) |
| 40 | completed-chunk count, unsigned 64-bit little endian |
| 48 | pending-byte count, unsigned 16-bit little endian |
| 50 | chaining-value stack length |
| 51 | 13 zero reserved bytes |
| 64 | pending chunk, 1024 bytes, zero padding |
| 1088 | 54 chaining values, 32 bytes each, largest/oldest first, zero padding |

All lengths, counts, flags, padding and stack shape are validated before use.
The pending chunk has 0–1024 bytes, and can be empty only before any completed
chunk. The final complete chunk stays pending until more input arrives. Stack
length equals the population count of completed chunks. Forging valid-shaped
states supplies arbitrary hash chaining values; states are not authenticated.
Treat state bytes as implementation data, and keep keyed states confidential:
they contain secret key material. Dropping a state does not securely erase it.

Each call borrows inputs synchronously and writes only its fresh output. It
retains no raw pointers and invokes no GC safepoint. Updating and finalizing a
state leave it valid for repeated finalization and independent branches.

Finalization validates the entire canonical state and then borrows its pending
chunk and chaining values directly, avoiding a copied writable state. Output
ranges use upstream `OutputReader`. Empty output still validates state,
and output-size/seek failures retain their precedence. Padding checks read
unaligned groups of eight bytes and check every remaining byte. Runtime pointers
and the managed 2816-byte state encoding are unchanged.

## Validation and benchmarks

Native tests include all official upstream BLAKE3 vectors for all three modes,
eight streaming split sizes, unaligned guarded ABI buffers, input preservation,
canonical malformed states, size/seek overflow, immutable branches, and
Hash-versus-streaming comparisons through one million bytes.

`packages/fast/tests/run/crypto-blake3*.mo` exercises public APIs in both
interpreters and Wasm. `packages/fast/tests/ash/BLAKE3.mo` adds actor execution.
Expected vectors originate from
[BLAKE3 1.8.2](https://github.com/BLAKE3-team/BLAKE3/blob/1.8.2/test_vectors/test_vectors.json)
and include extended output beyond the 32-byte digest. Performance measurements
live in the repository's crypto benchmark suite, comparing equivalent operations
against Mops `blake3@0.1.2`. Its context derivation ignores context, its tree
stack is not implemented, and its XOF output only handles one output block.
Only correctness-validated, equivalent workloads may report speedups; input
beyond 1024 bytes and output crossing a 64-byte block are not valid comparators.
The empty unkeyed digest is specialized to its official constant after measuring
compression overhead; nonempty inputs retain the upstream portable kernel.

The first optimization round's empty-input specialization reduced instructions from 3,078 to 643
(79.1%), with the same 56 allocated bytes. The branch adds four instructions to
nonempty inputs: 3,251 for 64 bytes and 35,930 for 1024 bytes. These are identical
across three PocketIC trials in the
[optimization archive](../../benchmarks/crypto/results/blake3-native-candidate/results.json);
its sibling `build.json` records source, compiler and artifact provenance.

The second round compares against that delivered implementation. Dedicated
fixed-output entry points avoid generic dispatch and redundant initialization;
wordwise padding validation and borrowed finalization reduce streaming overhead.
All 28 workloads passed independent output checks in three fresh-canister trials,
with identical counters between trials and unchanged Motoko allocations.

| Workload | Delivered instructions | Updated instructions | Reduction |
| --- | ---: | ---: | ---: |
| Digest, 64 bytes | 3,251 | 3,066 | 5.69% |
| Keyed hash, 64 bytes | 3,499 | 3,256 | 6.94% |
| Derive key, 64 bytes | 6,538 | 6,126 | 6.30% |
| Streaming, 64 bytes in 1-byte updates | 4,457,418 | 1,131,415 | 74.62% |
| Streaming, 1024 bytes in 256-byte updates | 333,237 | 112,934 | 66.11% |
| Streaming, 8192 bytes in 1024-byte updates | 782,411 | 454,855 | 41.86% |
| Streaming, 16384 bytes in 1024-byte updates | 1,499,790 | 904,840 | 39.67% |

Every measured workload improved; the long-XOF improvement is only six
instructions, and large one-shot hashing remains compression-bound. Final
canister Wasm shrank by 1750–1918 bytes across the workload set. A separate
short-output specialization was rejected: its small extra streaming savings
added about 2.5 KiB to the delivered Wasm and slightly regressed long XOF calls.
The [second-round comparison](../../benchmarks/crypto/round2/comparisons/blake3-c.json)
and [raw results](../../benchmarks/crypto/results/round2-blake3-c/results.json)
record all workloads; the sibling `build.json` captures exact source, compiler,
toolchain and artifact provenance.
