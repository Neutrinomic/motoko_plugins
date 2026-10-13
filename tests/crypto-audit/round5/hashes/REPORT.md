# Hash and HMAC audit, round five

No new production defect was found. Production modules, compiler bridges and
runtimes are unchanged. Native and public interpreter/Wasm validation passed;
central integration owns the pending `HashLifecycle` Ash run.

The review covered SHA256, SHA512/SHA384, RIPEMD160, HMAC-SHA256/SHA512 and
BLAKE3: immutable state ownership, serialization/length policies, non-consuming
sums, reset/prepared reuse, pointer alignment and alias contracts, compiler
allocation/rooting, modes, tree transitions, and public errors. Earlier
hash-codec/native/Ash suites already cover malformed states, overflow and most
fixed block boundaries; this lane adds the following gaps rather than copying
those corpora.

- 48 deterministic varied-binary cases checked against Python `hashlib` and
  `hmac`, including zero-length data, special SHA256 lengths, padding/block
  boundaries, and non-boundary lengths. All six algorithms use 16 input/output
  pointer offsets with canaries and immutable input checks. HMAC also receives
  the same byte range as both key and message.
- Five streaming algorithms use irregular updates, empty updates, retained
  prefix digests, independent continuation branches and prepared HMAC contexts.
  SHA256 exposes only one-shot hashing; it has no streaming API to exercise.
- 35 BLAKE3 derivation cases compare the production FFI against the untouched
  upstream reference implementation. Contexts are empty, contain NUL, or contain
  UTF-8 at 64, 1024 and 1025 byte boundaries; messages cross block/chunk/tree
  boundaries and output slices cross XOF blocks.
- A shared public fixture checks 16 Python cases plus six existing official
  BLAKE3 vectors and five new context vectors. The Ash wrapper retains SHA512,
  SHA384, RIPEMD160, prepared HMAC keys/streams/bound methods, detached digests,
  and keyed/derived BLAKE3 trees across two confirmed garbage collections.
  Completed stream sums are checked before reset after the second collection.

## Execution

`run-native.sh` passed **25 tests** (2 new tests and 23 included production unit
tests) in 13.25 seconds with two test threads. The public fixture passed source,
IR, lowered IR and Wasm with RTS sanity checks in 6.67 seconds. It is silent by
design and has no expected-output files. Fixture type inference initially
required explicit class field types; this was a test-only correction.

```sh
bash tests/crypto-audit/round5/hashes/run-native.sh
# From the frozen SDK nix development environment, with SDK bin first on PATH:
test-runner -b --jobs 1 /absolute/plugins/packages/fast/tests/run/crypto-hash-lifecycle.mo
# Central Ash runner discovers packages/fast/tests/ash/HashLifecycle.ash.json.
```

Compiler and reused plugin artifact hashes are in `evidence.json`. No plugin
rebuild or benchmark was necessary. Detailed local logs remain in ignored
`_build/crypto-audit5/{native,public}.log`.

## Oracle provenance and reproduction

`generate.py` imports Python standard-library hash/HMAC oracles, never production
plugin code. Xorshift32 describes input bytes only. It reproduces the checked-in
TSV and Motoko fixtures byte for byte.

`blake3_reference.rs` is unchanged from the [BLAKE3 1.8.3 reference
implementation](https://github.com/BLAKE3-team/BLAKE3/blob/1.8.3/reference_impl/reference_impl.rs),
SHA256 `6e89a18be72e3c4d838644e1796e04d896cb4a16bd7bb803d4380d7a363fbfd2`.
Its Apache-2.0 license is included as `LICENSE.blake3-reference`. It is a small,
unoptimized implementation independent of the production `blake3` crate's
compression and streaming code. The existing official JSON corpus remains in
`tests/crypto-audit/hash-codec/blake3-official.json` (SHA256
`dcb91ea8accc77e6d6e632af7cdc1a99a9f3ae78cf648da595c7d064db32f624`).

```sh
mkdir -p _build/crypto-audit5
rustc --edition=2024 -A dead_code tests/crypto-audit/round5/hashes/generate-blake3.rs -o _build/crypto-audit5/generate-blake3
_build/crypto-audit5/generate-blake3 > tests/crypto-audit/round5/hashes/blake3-contexts.tsv
python3 tests/crypto-audit/round5/hashes/generate.py
```

These are bounded correctness and ownership checks. They do not authenticate
arbitrary serialized states, prove timing behavior or secure key erasure, or
exercise physically enormous inputs. Existing synthetic-state tests cover the
encoded maximum lengths. Existing high-seek checks remain in place; the new
independent BLAKE3 reference cases cover moderate XOF offsets.
