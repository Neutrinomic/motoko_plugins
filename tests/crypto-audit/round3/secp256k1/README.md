# Independent Secp256k1 optimization audit

This audit covers the Wasm64 10x26 field selection and public-verification
GLV/width-five NAF optimization. It is an internal source and differential
review, not an external cryptographic certification or a timing proof.

**Approved:** all eight Motoko fixtures passed across source, IR, lowered IR
and Wasm execution; debug and release field-backend suites passed. Reviewed
implementation commits are `fdaec67` and `041412e`. The tested runtime hash is
`8dc0a4d19b68de3c7858410c73f276f2b876441ec57ad9e910c17f90d122ab57`,
identical to the selected measured artifact. No unresolved findings remain.

The later predicate-allocation cleanup is independently approved in
[predicate/README.md](predicate/README.md), including the final artifact hashes,
eager-effect/error/alias tests and nine Ash methods with confirmed GC.

## Reproduction

From the matching compiler checkout, inside its Nix development shell:

```sh
python3 /path/to/plugins/tests/crypto-audit/round3/secp256k1/run.py \
  --plugin /path/to/plugins/dist/secp256k1 \
  --motoko /path/to/motoko \
  --out /path/to/plugins/_build/secp-independent-final
```

The runner rejects mismatched compiler, plugin artifacts, or source hashes,
and checks identity again after testing. It executes the Motoko source, IR,
lowered IR and Wasm paths and requires all expected engine outputs.

## Coverage

- The exact unmodified vendored 10x26 and 5x52 field backends are included
  directly in one native crate. Both debug and optimized builds compare
  2,820 full-width operand pairs with independent `BigUint` modular arithmetic,
  using input magnitudes 1, 2, 4 and 8. Tests cover multiplication, squaring,
  negation, addition, normalization, range parsing, integer conversion and
  zeroization. Upstream normalization regressions execute too.
- Actual Wasm execution covers 476 Wycheproof ECDSA vectors, 19 published
  BIP340 vectors, 18 independently calculated RFC6979 boundary signatures,
  and BIP341 secret/public tweak boundaries from the earlier audit generator.
- Additional Python-bigint expectations cover 32 deterministic full-width
  key/scalar pairs, 128 point-arithmetic operations, exact ECDSA and Schnorr
  signatures, ECDSA high-S counterparts, and 64 signature/message mutations.
  The BIP340 Python signer is checked against every published signing vector
  before generating new expectations.
- Four equation cases explicitly cover ECDSA identity rejection and the rare
  valid branch where the verification point's x coordinate exceeds the scalar
  order, with both low and high S.

The implementation owner's additional direct constant-time/variable-time
linear-combination comparisons and independent integer NAF recoding checks
are documented in `benchmarks/crypto/round3/secp256k1/`.

## Source review

The field change selects the existing 32-bit-limb backend for Wasm64 in both
normal and debug-wrapper configuration. Native 64-bit configuration retains
5x52. The 10x26 arithmetic formulas are unchanged, use fixed-width limbs and
fit their documented magnitude bounds; the shared coordinate representation
still occupies 40 bytes.

ECDSA retains the upstream equation, reduction, nonzero scalar parsing,
high-S acceptance and error ordering. An identity result has x=0 and cannot
equal the already validated nonzero r. BIP340 retains its distinct zero-r/s
input policy, range checks, identity rejection, even-Y requirement and exact
x-coordinate comparison.

The new helper receives public verification scalars and points only. Its two
production call sites are ECDSA verification and Schnorr verification. Signing,
key derivation, generic scalar multiplication and secret/public tweaks retain
their existing multiplication paths; secret zeroization is unchanged. The
ECDSA variable-time scalar inversion was already used by the upstream verifier.

NAF scalar decomposition reuses the upstream proof that each signed GLV
component has magnitude below 2^128. Recoding writes at most digit 128 of a
129-element array, and nonzero digits are odd values from -15 through 15.
Table indices therefore stay in 0..7. Multiplication performs a fixed maximum
129-bit traversal with four terms; input values cannot cause unbounded work.
The table and digit arrays are fixed stack storage, and no persistent plugin
state or managed allocation was added.

The runtime continues to borrow immutable Blob inputs, construct results in
initialized 72-byte scratch, and write the unchanged operation-specific output
capacity. Invalid input handling remains in the existing typed-result adapter.

Final execution evidence and source hashes are recorded in `evidence.json`.

Fixture sources and logs are retained as gzip files; the hashes in execution
evidence refer to their decompressed contents. `retained-files.json` identifies
both compressed and decompressed hashes. `benchmark-review.json` independently
checks all 63 screening observations, common fixture/compiler/RTS identity and
exact output hashes. Integration owns the broader final benchmark gate.

`wasm-inspection.json` records a disassembly sanity check: the public helper's
stack frame is 5,392 bytes, the maximum summed direct-call frame chain is
8,656 bytes, and no indirect calls, recursive edges, runtime function imports
or memory-growth instructions were found. This is not a formal stack bound.
