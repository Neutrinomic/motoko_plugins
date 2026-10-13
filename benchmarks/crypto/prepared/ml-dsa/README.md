# Prepared ML-DSA benchmark fixtures

These fixtures compare direct and prepared ML-DSA-44 calls using the **same new
compiler, RTS and plugin build**. They reuse exact official NIST ACVP answers
already pinned by the direct plugin tests. This directory contains source, not
measurement results.

| Corpus case | Message | Context | Signing mode | Purpose |
| --- | ---: | ---: | --- | --- |
| 4 | 1 B | 59 B | Deterministic | Small-message comparison and measured reuse batches. |
| 6 | 1,188 B | 0 B | Deterministic | The signing case with more rejection-sampling work in the preceding benchmark. |
| 11 | 8,192 B | 255 B | Deterministic | Larger message and maximum external context. |
| 362 | 871 B | 0 B | Explicit randomness | Exact hedged-signing answer. |

`generate.py` copies these four rows from the existing
[`acvp-ml-dsa-44.json`](../../../../../plugins/ml-dsa/tests/vectors/acvp-ml-dsa-44.json)
into `fixtures.json`, retaining the corpus hash and upstream source pins. No
expected answer is produced by the plugin. Regenerate from the repository root:

```sh
python3 benchmarks/crypto/prepared/ml-dsa/generate.py
```

The 45 independently compiled actors are split into three manifests:

- `cases.json`: 36 comparable cases. Each of four fixtures has direct call,
  preparation and hot prepared call for signing and verification. Case 4 also
  has measured direct/hot batches of 2, 10 and 100 operations.
- `end-to-end-cases.json`: one separately measured direct `publicKey` control and
  eight **cold** batches: prepare once, then sign or verify 1, 2, 10 or 100 times.
  Preparation executes inside these measured intervals.
- `all-cases.json`: all 45 cases for one build/run with identical toolchain and
  plugin provenance. The prepared harness's `cold` and `control` modes distinguish
  these rows from hot calls. Cold measurements validate reuse costs directly;
  they must not be mistaken for the separate `P + N × hot` model.

Hot cases prepare exactly one key in `configure()`, outside the measured
interval. Preparation cases construct only the handle inside `run()`; their
subsequent `bytesResult()` query signs or verifies against the same independent
oracle as the direct/hot rows. Opaque key contents are never serialized. Direct
cases declare no prepared-key field and perform no hidden preparation.

Every actor records instruction count, cumulative allocation and synchronous
reclamation around the complete public call and result unwrapping. Batch rows
measure the entire loop, without subtraction; only the final signature or Bool
is retained for the external exact-oracle check. Prepared handles remain rooted
in transient actor fields after the call, including cold batches. The prepared
payload metadata is 20,576 bytes for public keys and 28,800 bytes for secret
keys, excluding ordinary managed-object overhead.

The `memory()` interface enables the shared runner's untimed before-run,
after-run and after-four-GC-increment snapshots. These describe occupied heap and
Wasm capacity, **not retained live bytes or collection completion**. The separate
prepared-key lifetime/pressure measurements own retained/drop accounting. Do not
infer that cost from allocation totals or these snapshots.

Build and run `all-cases.json` with the
[prepared crypto harness](../README.md), using the prepared SDK's explicit
compiler path and matching plugin artifact. The installed pre-feature compiler
is incompatible with these opaque handle primitives. Actual execution and
results are owned by integration; no benchmark pass or speedup is claimed here.
