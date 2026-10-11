# Independent CandidX audit

Reviewed the complete compiler generator, interpreter reference, Rust shape
runtime, ABI registration, and the optimization delta against `093957a`.
No correctness defect or blocking finding was identified. The audited source
hashes are recorded in [candidate-build.json](candidate-build.json).

The new proof accepts only supported primitives and finite records/tuples.
Options, vectors, blobs, variants, functions, and recursive records retain
their existing dynamic paths. A nonempty fixed-record vector traverses its
first element normally, preserving full depth validation and its shape; later
elements have the same shape and visit count. Empty vectors retain the empty
element type. The length and proof limits bound the batched product below
4 trillion, safely inside the generated 64-bit arithmetic.

Reusing existing static payload helpers is valid inside dynamic enclosing
options, records, and variants: these proven children cannot acquire missing
fields or value-dependent payload shapes. Text and integer length checks,
output sizing, NaN normalization, case selection, and genuinely dynamic child
lookups remain. Fixed-size multiplication is bounded by the shape traversal
and width limits; the final output limit is checked before allocation. The
reference diagnostic correction agrees with the runtime's exhausted visit
budget. Boundary fixtures cover empty/singleton/repeated records, depth 256
and overflow, visit exhaustion, and subsequent successful calls.

ABI 1 and the Rust runtime are unchanged. Generated traversal introduces no
callback, suspension, or GC safepoint. Existing forwarding barriers protect
input loads, and scratch remains unreachable Motoko Blob storage reclaimed
after the synchronous call. Early error returns retain no persistent context.
The optimization adds one bounded type proof and reuses existing writers;
it introduces no new runtime API or framework.

Validation evidence was independently inspected, including the generated
probe translations and their hashes; the expensive suites were not rerun:

- All 14 Motoko fixtures and 29 Rust tests passed in the implementer's logs.
- [Conformance](conformance.json) passed 93 directed typed cases, including
  61 frozen goldens, against independent source-value expectations. It also
  exercises Rust/TypeScript original-value decoding.
- Both 500-record fuzz seeds, [0xcad1d](fuzz-0xcad1d.json) and
  [0x5eedc0de](fuzz-0x5eedc0de.json), passed 1,130 typed record cases each,
  including schema-extension pairs, exact canonical bytes/hashes, and original
  value recovery. The standalone `cx.wasm` backend was disabled.
- Frozen compiler `f1ccbba5e445df9db03bbc35be557187ade9b436` and upstream CandidX
  remained clean. Actual compiler/artifact hashes match the records. Baseline
  build metadata predates `093957a`, but all 21 recorded package source hashes
  were independently checked against that baseline commit and match it.

The four paired PocketIC suites use identical source, cases, runner, protocol,
and output hashes. All 108 phases have three deterministic trials and zero
synchronous reclamation. Across 52 canonical workload entries plus four
controls, 34 improve and 22 are unchanged; there are no instruction or
allocation regressions. Optional arrays of 1,024 fixed records improve
2,044,436 to 367,561 instructions (82.02%); text records improve 1,613,331 to
515,407 (68.05%). Allocation is unchanged throughout. Final Wasm shrinks by
333, 32, 333, and 784 bytes for main, static, repeated, and nested suites.
Every phase, including unchanged ordinary-Candid controls, remains visible in
[summary.csv](summary.csv). These measurements exclude later message-end GC.
