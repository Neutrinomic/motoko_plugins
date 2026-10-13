# RSA signing and verification: round four

Selected change: retain the existing BearSSL i31 Montgomery arithmetic and
five-bit private exponentiation, but let Clang specialize its two public limb
counts (50 for 1536-bit factors, 100 for 3072-bit moduli). The generic path remains
available. A destination-only `restrict` annotation expresses the upstream
non-overlap contract; input operands may still alias for squaring.

The [four-case screen](candidate2-comparison.md) compares against the previous
best direct and prepared implementation, with the same compiler, RTS, inputs
and independent exact-signature oracle. Each count repeated identically in
three fresh PocketIC canisters:

| Prehashed operation | Previous instructions | Selected instructions | Reduction |
|---|---:|---:|---:|
| Direct sign |447,476,438|400,505,033|10.50%|
| Prepared sign |443,550,622|396,540,393|10.60%|
| Direct verify |9,822,608|9,162,600|6.72%|
| Prepared verify |8,421,716|7,722,884|8.30%|

The [first screen](candidate1-comparison.md), using only `restrict`, saved a
negligible 0.08% for signing. The [incremental comparison](candidate2-incremental.md)
isolates the substantive fixed-length specialization. No new multiplication or
reduction algorithm, larger window, skipped validation or omitted fault check
is involved. The independent review verifies the arithmetic body matches the
upstream body after moving only its public length calculation.

Allocation stays 440 bytes per sign and 32 bytes per verification. Prepared
payloads remain 1,840 bytes (secret) and 824 bytes (public). Runtime Wasm grows
from 30,264 to 31,212 bytes (+948B). The [native stack bound](candidate2-stack.json)
remains 11,664 bytes for the maximum direct chain, within the 4 MiB reserve;
Motoko caller frames and engine value-stack space are outside this bound.
There is no new native allocation, key cache or retained pointer.

The [independent audit](../../../../tests/crypto-audit/round4/rsa/README.md)
covers original-upstream/Python Montgomery oracles across 19 announced widths,
including specialization boundaries, four adjacent/separate destination
layouts, intentional squaring aliasing, and instrumented non-overlap assertions
through the full signature corpus. Native O3 ASan/UBSan, portable OCaml,
compiled Wasm, malformed keys/PSS and signature fault checks all pass.

[Research and source links](RESEARCH.md) explain the scoped candidates and why
an i62 or HACL* backend replacement was not adopted in this pass. Existing
prepared layout, API and GC integration are unchanged.

The [final comparison](final-extra-comparison.md) adds ten matched preparation,
message and actual reuse-10 workloads. Together with the four selected screen
rows, this is 14 workloads and 84 fresh baseline/candidate observations. The
[evidence index](final-index.json) verifies identical plugin source/artifact,
compiler, RTS and builder identities across both cohorts. Every exact-output
oracle passed; no modeled costs replace measurements.

| Additional workload | Previous instructions | Selected instructions | Allocation |
|---|---:|---:|---:|
| Prepare secret key |6,138,602|6,138,602|1,896 B|
| Prepare public key |3,642,309|3,642,309|880 B|
| Direct sign, message |447,485,855|400,514,450|440 B|
| Prepared sign, message |443,560,039|396,549,810|440 B|
| Direct verify, message |9,832,026|9,172,018|32 B|
| Prepared verify, message |8,431,134|7,732,302|32 B|
| Direct sign, prehash ×10 |4,474,763,608|4,005,049,558|4,400 B|
| Prepared sign, prehash ×10 |4,435,505,448|3,965,403,158|4,400 B|
| Direct verify, prehash ×10 |98,225,558|91,625,478|320 B|
| Prepared verify, prehash ×10 |84,216,638|77,228,318|320 B|

Preparation controls remain exactly unchanged. Allocation and occupied-heap
observations match their paired baseline; the runtime adds 948 bytes and each
compiled benchmark canister adds 942 bytes. The prepared signing stack bound
remains 9,568 bytes.

The audit also corrected earlier workspace explanations. Upstream header
definitions override the existing command-line capacity macros: the actual
direct allocation unit is `U = 70`, and its 2,591-word temporary occupies
10,364 bytes. Actual factor slots remain 52 words; prepared exponentiation uses
1,716 words (6,864 bytes). Both current paths use a five-bit window. Earlier
8U/9U direct configurations selected q/p windows 2/2 and 3/2, respectively;
prior prose calling both 9U windows two-bit was incorrect. Historical measured
results and artifacts are preserved. This correction supersedes those old
capacity explanations; the actual Wasm stack bounds above remain authoritative.
Removing the ineffective build flags is outside this frozen performance change.
