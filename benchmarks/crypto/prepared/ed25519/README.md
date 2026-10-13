# Prepared Ed25519

Prepared keys reuse validated public-key tables and expanded signing state. These
benchmarks compare direct, preparation and prepared calls from the same plugin
build and prepared-capable compiler. Earlier round-three results are unchanged.

All 90 PocketIC trials passed: 30 actors, each measured on three fresh canisters.
Instruction counts and allocation were identical across repetitions. Preparation
is measured separately; the prepared column reuses an existing handle.

| Operation | Message | Direct instructions | Preparation instructions | Prepared instructions | Prepared saving |
|---|---:|---:|---:|---:|---:|
| Sign | 32 B | 1,803,963 | 887,929 | 907,801 | 49.68% |
| Verify | 32 B | 2,308,542 | 266,520 | 2,071,444 | 10.27% |
| Sign | 1 KiB | 1,910,488 | 887,929 | 1,014,328 | 46.91% |
| Verify | 1 KiB | 2,379,349 | 266,520 | 2,142,252 | 9.96% |

| Key / operation | Handle payload | Preparation allocated | Direct call allocated | Prepared call allocated |
|---|---:|---:|---:|---:|
| Secret / sign | 96 B | 152 B | 120 B | 88 B |
| Public / verify | 1,056 B | 1,112 B | 32 B | 32 B |

Adding separately measured preparation and call costs predicts that verification
becomes cheaper at two uses. Signing's modeled first use is only 8,233 instructions
cheaper at 32 bytes; reuse is the substantial benefit. These are arithmetic
projections, not measured cold-call timings. Actual 100-call batches, excluding
preparation, used 180,386,148 versus 90,760,895 instructions for signing and
230,848,248 versus 207,125,195 for verification. Batches of two and ten also passed.

The [full report](../results/prepared-ed25519-final/summary.md) includes empty
messages, all batch sizes, allocation, qualified heap snapshots and canister
Wasm sizes. [Raw measurements](../results/prepared-ed25519-final/results.json)
and [build provenance](../results/prepared-ed25519-final/build.json) retain exact
inputs, source and artifact hashes.

`fixtures.json` copies independent RFC8032 and Node/OpenSSL answers with source
provenance. The generator emits 30 actors: sign/verify at empty, 32-byte and 1 KiB
messages in all three modes, plus direct/prepared batches of 2, 10 and 100 uses
for the 32-byte fixture. Every actor checks the exact signature or expected
verification result after measurement; preparation checks its resulting handle
by performing the operation outside the timed interval.

Prepared calls construct their handles in `configure`. They extract the handle
from a transient optional field once within the timed region, before any batch
loop. This small consumer overhead is included. Signing's prepared API returns a
Blob directly, so the benchmark does not add an artificial Result wrapper.
Factories retain their actual Result until result checking. No loop subtraction
or earlier-compiler comparison is used.

Payload sizes are 96 bytes for a secret key and 1,056 bytes for a public-key
table, excluding managed-object overhead. Allocated and reclaimed bytes and
heap/capacity snapshots use the shared prepared benchmark protocol. Snapshot
occupancy is not peak or retained-live memory; the separate Ash test forces
collection while keeping both handle types live across messages.

`reference-validation/` preserves the independent portable-reference checks.
[Validation evidence](validation/result.json) records five native tests, both
public direct/prepared fixtures across all execution engines, three nominal
rejections and five Ash methods, including actual collection with retained keys.
The [independent audit](../../../../tests/crypto-audit/prepared/ed25519/README.md)
covers all 290 adversarial verification cases and additional large-message,
nominal-type and initialized-payload tests. Matched PocketIC measurements are
archived by the shared prepared runner.
