# Ed25519 round-four optimization

The retained change reuses the signature point and scalar already obtained
during validation. Verification compares Edwards points with Dalek's existing
projective equality, avoiding a final point encoding and field inversion.
Canonical encodings, small-order rejection, error precedence and the full
uncofactored equation remain unchanged. Signing and prepared-key layouts are
unchanged. See the [equivalence review](projective-equality-review.md).

The baseline is plugins `0e1e96a`, including the previously optimized serial32
backend and prepared keys. Both revisions use compiler `9f6ebeedc`, ELF SHA-256
`24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`,
and the original matching RTS. Each row uses three fresh PocketIC canisters;
all repetitions returned the exact expected result and identical counters.

| Operation, 32 B message | Baseline instructions | Selected instructions | Saving | Allocated bytes, unchanged |
|---|---:|---:|---:|---:|
| Direct verification | 2,308,542 | 2,169,138 | 6.04% | 32 |
| Prepared verification | 2,071,444 | 1,933,663 | 6.65% | 32 |
| Prepare public key | 266,520 | 266,515 | <0.01% | 1,112 |
| Direct signing | 1,803,963 | 1,803,963 | 0% | 120 |
| Prepared signing | 907,801 | 907,801 | 0% | 88 |
| Prepare secret key | 887,929 | 887,929 | 0% | 152 |

Public and secret handle payloads remain 1,056 B and 96 B. Runtime Wasm shrinks
from 121,439 B to 120,398 B; each of these six complete benchmark canisters
shrinks by 1,042 B. Allocation counts measure cumulative bytes during the timed
operation. Heap snapshots in the raw evidence are occupancy samples, not peak
or retained-live memory measurements.

[Strict paired comparison](candidate1/comparison.md),
[machine-readable comparison](candidate1/comparison.json),
[frozen baseline](../results/prepared-round4-ed25519-c1-baseline/results.json),
and [selected build measurements](../results/prepared-round4-ed25519-c1-candidate/results.json)
record the six matched cases and all 36 observations. Inputs, expected outputs,
compiler, plugin artifacts and workload metadata are checked before comparison.

## Rejected backend experiment

The configuration-only Fiat32 screen used upstream `fiat-crypto` 0.2.9 already
present in the dependency lock. All 18 observations passed, but direct/prepared
signing rose to 1,982,917 / 997,278 instructions and direct/prepared verification
rose to 2,363,482 / 2,110,375. Its runtime also grew to 127,914 B. Serial32 is
retained. [The rejected comparison](candidate2/comparison.md) and
[configuration patch](candidate2/backend.patch) preserve this result without
retaining experimental production code.

[Table research](table-research.md) records further upstream alternatives and
their arithmetic, lookup and memory costs. Larger generated tables were not
added in this round.

The selected artifact is byte-identical to candidate1:
`32d76fa35196fcce7933a7e3c21ea171366e3d2acfac156f8f857dead42c97ac`.
Restoration after the Fiat32 screen checked every source and artifact hash in
its build manifest, so the candidate1 observations apply to the final runtime.

The [independent audit](../../../../tests/crypto-audit/round4/ed25519/README.md)
passed nine native tests and four public fixtures across source, IR, lowered IR
and Wasm. It retains the 290-case verification corpus and 18 signing oracles,
adds 118 comparisons between the old and new equality predicates, and tests
96 native and 13 public R sign-bit flips. No source issue was found. Prepared
types, payload codecs, compiler bridge and ownership rules did not change.
