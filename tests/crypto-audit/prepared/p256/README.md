# Independent prepared P256 audit

Status: independent source, correctness and final benchmark audit approved for
the selected width-8 artifact below. No blocking defect was found. The final
benchmark uses the same audited source and binaries, unchanged from source
checkpoint `6b174d7becd596a80665f7e42a032f54c65070c6`.

Tested SDK compiler: `9f6ebeedc547e389a0529b4c91442e46b88fcbe0`, SHA-256
`24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`.
Tested runtime: 125,436 bytes, SHA-256
`0d2fa29baa9ab136ba5bd8a0cb55da5478ff6459fe1e8c02fecdc3e25dde3972`.
Tested compiler plugin: SHA-256
`966ed674806198030a1c3572b6a1eeb80934c606d6d77f90cf7946a172789b23`.
Every phase verifies all 199 build-source pins and rechecks source/artifact
identity after execution; `execution-*.json` contains the complete provenance.

Scope: `preparePublicKey`, `verifyPrehashPrepared`, their compiler/reference
bindings, narrow vendored field/point accessors, generated tables, and the shared
fixed-generator improvement in ordinary verification. Secret signing and
public-key derivation retain the previously audited constant-time comb.

The 16,320-byte prepared value is an immutable, caller-owned, GC-managed Blob protected by
the SDK's nominal `P256PreparedPublicKey` type. Its bytes are not an input format:
only this exact build's successful constructor may supply the unsafe native
prepared-verification export. Compiler ownership/type checks reject forged
Blobs and unrelated prepared types; a borrowed payload pointer is resolved
afresh on each call. No pointer or handle registry survives a native call.

Each point occupies 64 explicitly initialized bytes: four little-endian u64
Montgomery words for x followed by four for y. There is no Rust object layout,
padding, identity tag, or pointer in the representation. Canonical field
residues come from unchanged upstream arithmetic. Every nonempty comb subset
has a positive coefficient below 2^225, below the prime group order; consequently a valid
nonidentity P256 public key cannot produce an identity table entry. This is
the precondition for the narrowly unchecked affine restoration.

The new direct table indexing, zero-digit branches, and variable-time scalar
inversion operate only on public verification inputs. Prepared verification
retains digest reduction, strict r/s bounds, high-S acceptance, final identity
rejection, and x-coordinate reduction modulo the scalar order.

Passing evidence:

- `field-hooks/`: independent upstream-diff review, inversion-trait forwarding,
  canonical residue and batch-normalization invariants, with source hashes.
- `generate.py`: separate Python integer curve arithmetic; exact encoded table
  expectations, field/scalar boundaries, high-S, reduced digests, point
  cancellation, and deliberately constructed valid signatures with x >= n.
  The corpus contains 17 keys and 180 verification equations; it also checks
  every generated fixed-G/odd-G constant independently.
- `native/`: compares public and prepared verification against that oracle,
  checks every prepared byte, unaligned pointers, canaries, input immutability,
  malformed keys, scalar bounds and error precedence. Debug and release each
  passed all 14 tests, including the implementation's 10 tests and full 484-case
  Wycheproof corpus.
- `render.py`: renders the oracle into public Motoko tests for source, IR,
  lowered and compiled execution. It also checks local aliases, record/array
  storage, closures, and left-to-right single argument evaluation. All four
  execution engines passed the same generated test, with Wasm validation.
- `Retained.mo`: an independent Ash actor keeps prepared aliases in transient
  actor state, an async frame, a nested option/array and a closure across real
  self-call message boundaries. It requires >4 MiB actually reclaimed before
  accepting the retention check. Its final empty `Test.test` metrics are not a
  benchmark of the preceding asynchronous work. The actual PocketIC execution
  passed; the helper `tick` is correctly skipped as a test by Ash.
- `stack.py`/`stack.log`: all 43 runtime functions are covered, with no native
  function imports, indirect calls or recursive call graph. Conservative
  additional native stack is 88,000 bytes for preparation and 1,344 bytes for
  prepared verification. This is temporary stack, separate from retained
  managed payload. The initial generic analyzer rejected LLVM's two fixed leaf
  red-zone forms; the audit-only adapter recognizes these explicit forms,
  forbids nested calls/global mutation, and counts their full reservations.
  The original rejection log is retained rather than concealed.
- `benchmark.py`/`benchmark-acceptance.json`: independently verifies all 688
  frozen inputs, all 37 actor source/Wasm hashes, exact audited compiler/plugin
  parity, and all 111 output hashes. It recomputes every instruction,
  allocation and memory summary from the raw three-trial results and checks
  the seven groups' break-even arithmetic. Every metric is identical across
  each case's three trials. Only the corrected final stage contributes
  counters; the preceding cold-fixture compile failure has no results file.

For the RFC6979 sample, direct verification costs 12,541,922 instructions and
prepared verification 3,802,871, a 69.68% reduction. Preparation costs
19,688,675 instructions and allocates 16,376 bytes, including the 16,320-byte
payload and managed overhead. Direct and hot prepared calls both allocate
32 bytes per check. Actual cold batches include preparation: ten checks cost
57,714,287 versus direct 125,416,988 (53.98% lower), and 100 cost 399,943,697
versus 1,254,167,648 (68.11% lower). Cold one- and two-check batches are slower
than direct; the reported three-check break-even is explicitly a model from
single-operation counters, not a measured three-check batch. Occupied heap
samples are not peak memory or proof of completed collection.

One fixture-only issue found during review was fixed by the public-test owner:
raw intrinsic aliases cannot populate ordinary function arrays. The tests now
use normal wrapper closures while retaining direct intrinsic-alias coverage.
No production correctness defect was identified. The shared direct-verification
fixed-G table uses the same restored point representation; signing, secret
generator multiplication, derivation, conversion, DER and normalization were
independently checked byte-for-byte unchanged from `f43a81e`.

Native logs retain upstream vendored lint warnings (trait-implementation
`must_use` annotations and unnecessary qualification with this Rust toolchain).
They are not a warning-free-build claim; the narrow vendor diff and unchanged
arithmetic are recorded in `field-hooks/`.

The supported targets are Wasm64 and 64-bit native. Prepared values are not a
portable external serialization or upgrade format. Direct shared/stable use is
rejected; callers rebuild them from canonical public keys after upgrades.
