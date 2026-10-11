# Independent SHA-256 audit

No correctness or performance regression found in the accepted change against
`093957ad1ba611384a8b998c83bd86c75b585e4f`. Audited runtime source SHA-256:
`3075fbac11f627825828d84ab9ec993dcc015bd0abd41da6e0c2408aacb33f78`.
This is a source simplification with **zero measured speedup**: independently
compared baseline/final runtime and actor files are byte-for-byte identical.

The whole SHA plugin was reviewed, including the Rust kernel, OCaml reference,
ABI 1 registration, tests, and the frozen compiler's Blob/GC operations. The
accepted delta removes the production digest-array wrapper and shares the
existing unaligned output stores. Compression, padding, empty-input dispatch,
and the 32/64-byte specializations retain their algorithms. None of the rejected
iterator-chain or grouped-round experiments remains in production source.

- Rust round constants, indices, and state permutations were mechanically
  checked against the OCaml reference; the rolling schedule and wrapping
  arithmetic were reviewed. Input words, length encoding, and output words
  consistently use big-endian SHA representation.
- Complete blocks use bounded 64-byte slices. The generic tail has 128 bytes,
  writes its marker at a remainder below 64, and selects one or two blocks at
  the 55/56 boundary. Fixed 32-byte input pads one block; fixed 64-byte input
  adds a separate padding block. The helper writes exactly eight unaligned
  32-bit words, initializing all 32 output bytes without reading or creating
  references to the uninitialized payload. Empty input writes exactly four
  unaligned 64-bit words. Input access requires only byte alignment.
- Registration allocates the result before borrowing payload addresses, uses
  the compiler's forwarding/allocation barriers, and returns a managed Blob.
  The Rust kernel has no allocation, callback, suspension, retained pointer,
  or GC safepoint. The existing forced-GC fixture checks retained inputs and
  outputs after collection, as well as size-independent result allocation.

The audit suggested one small improvement, now resolved: the fixed-size
const-generic guard is an inline const assertion. An isolated copy instantiating
`sha256_fixed::<31>` fails compilation with E0080 under the selected Rust
nightly. The private fixture was never executed; its source and diagnostic are
under `_build/opt-sha256/audit/`. No test framework or runtime guard was added.

Independently regenerated all 18 xorshift32 inputs and Python `hashlib` answers,
then reconciled all 216 baseline/final records: 18 sizes × 3 trials × 2
implementations × 2 builds. Every output size/hash agrees with its oracle,
every trial is identical, and all baseline/final measurements match. Inputs
cover empty, 31/32/33, both padding transitions, multiple blocks, 64 KiB, and
1 MiB. At 1 MiB, both plugin builds use 78,124,848 instructions and 56 allocated
bytes; Mops sha2 uses 323,721,060 instructions and 1,008 allocated bytes. Every
phase reports zero reclaimed bytes. These are synchronous measured intervals,
not end-to-end latency or later GC costs.

Source/build/artifact pins, the frozen clean compiler revision and executable,
and all 43 sha2 0.2.5 / 57 core 2.5.0 dependency files were checked. The benchmark
actor and runner use identical inputs and validate both implementations' actual
digest bytes outside measurement. Rejected-experiment rows also agree with
their raw results. Reviewed the final three passing Rust tests and seven
passing Motoko fixtures, including source/IR/Wasm and forced-GC coverage;
those suites and PocketIC were not redundantly rerun during this audit. The
compile-time guard was rebuilt by the owner and preserves the measured Wasm.

Full measurements, methodology, hashes, and test logs are linked from
[the round report](README.md).
