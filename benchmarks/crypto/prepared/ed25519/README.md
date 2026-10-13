# Prepared Ed25519

Prepared keys reuse validated public-key tables and expanded signing state. These
benchmarks compare direct, preparation and prepared calls from the same plugin
build and prepared-capable compiler. Earlier round-three results are unchanged.

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
