# Independent round-4 ML-DSA audit

**Approved:** the frozen implementation passes the executed correctness and stack gates.
Production source is `f4da0c8`; runtime SHA-256 is
`d2ad769ca27e92e62d74f9e3a185fc5d4459964b5f0525cc817ab64c102af869`.
No unresolved correctness, layout, lifetime or stack finding was identified.
The [benchmark provenance review](benchmark-review.json) also passes.

| Executed gate | Result |
|---|---|
| Independent private-function harness | 3 tests pass in debug and release; 13 Python SHAKE oracle cases plus signed Reader boundaries |
| Native plugin tests | All 10 groups pass in debug and release: official keygen/sign/verify answers, prepared parity, malformed inputs, output initialization and canaries |
| Public Motoko tests | Three fixtures pass Motoko, IR, lowered IR and Wasm; exact official deterministic/hedged cases include 4, 6, 11 and 362 |
| Static Wasm stack | All 38 functions and 159 calls covered; maximum additional native shadow stack 137,984 B |

[Provenance](provenance.json) verifies the actual compiler executable, all 383
build source pins and 292 SDK source pins. [Validation](validation.json) checks
those artifacts again after execution and records the original RTS hashes,
logs and generated interpreter/Wasm outputs. Production and audit builds use
the frozen SDK; no global tools were changed.

## Reviewed changes

The sampler reads SHAKE128 in 168-byte blocks. Since 168 is divisible by three,
every coefficient candidate keeps its original bytes and order. Rejected
candidates advance the input but not the output index. The final accepted
coefficient immediately exits the loop; unused bytes belong to a discarded
local XOF. This changes read batching, not cryptographic framing or arithmetic.

The Reader checks one 4,096-byte span and fills exactly 1,024 initialized signed
little-endian coefficients. Both zipped iterators have that exact length.
Offsets, polynomial ordering, immutable input and normal zeroizing drops remain
unchanged. It introduces no native casts or pointers in cache bytes. The
debug-only `sample_in_ball` conversion annotation retains the original check;
its `tau` binding has already been converted to `usize`.

[The harness](prepare-harness.py) appends tests to an isolated copy whose
production source prefix is unchanged. Python/OpenSSL SHAKE generates the
expected coefficients independently of the Rust sampler and conversion helper.
Fixtures force rejections at candidate indices 55/56, 111/112, 223/224 and 255;
they also cover nonce ordering, zero/all-ones rho and CTEST. Reader tests check
unaligned nonzero offsets, signed extremes, all matrix rows, a following vector,
canaries and checked short input. [Crypto dependency pins](harness-dependency-pins.json)
match production. An initial audit-only lint failure is retained in the logs;
the test now explicitly drops its expected-to-panic result.

## Stack and copies

| Operation | Baseline bound | Final bound |
|---|---:|---:|
| Direct sign | 137,984 B | 137,984 B |
| Prepared sign | 121,312 B | 104,960 B |
| Prepared verify | 138,624 B | 114,048 B |

The [strict analyzer](../../round3/ml-dsa/stack/analyze.py) rejects unresolved,
indirect, recursive and unfamiliar stack operations. [Final evidence](stack-candidate2.json)
covers the entire runtime; these are conservative native shadow-stack bounds,
not heap or host-stack measurements. All fit the existing 4 MiB reservation.

[Disassembly review](codegen-candidate2.json) confirms the old per-vector copy
chain is removed and unaligned i32 loads preserve the byte representation.
Matrix assembly still contains copies; this is not a claim of copy-free decoding.
Final runtime size is 123,611 B, versus the original 123,026 B.

## Benchmark review

Independently checked all frozen source/toolchain pins, compiled actors, exact
output hashes and raw arithmetic across 189 observations: 150 final-versus-original
observations plus 39 intermediate sampler-only observations. Every case has
three fresh-canister trials. Instructions repeat exactly across the three
trials; matched allocation and reclamation counters are unchanged.

| Change | Observed instruction saving per measured operation |
|---|---:|
| Sampler on operations expanding A | 154,369–154,445 |
| Reader on prepared signing | 186,671 |
| Reader on prepared verification | 133,350 |

These are fixed-input results for the covered official fixtures, not universal
rejection-loop costs. No signing attempt counts were instrumented. The
[owner's report](../../../../benchmarks/crypto/round4/ml-dsa/README.md)
contains the full before/after tables; [this audit's review](benchmark-review.json)
pins all five raw stages and verifies matched sources, inputs and oracles.

The SDK, compiler binding source, public module, cache layout and allocation /
forwarding boundaries are unchanged. The prior [nominal-type and actual-GC
evidence](../../prepared/ml-dsa/README.md) remains pinned to its original
artifact and was not rerun. There is no new absolute live-heap study, separate
wasm32 execution, secure-erasure guarantee or strict bound on the inherited
signing rejection loop.
