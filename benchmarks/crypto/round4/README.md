# Signature optimization round four

Compare a candidate with a freshly compiled and measured baseline using the same actors, fixtures, compiler, RTS and dependencies. Historical prepared results remain unchanged under [`../prepared/`](../prepared/README.md).

Build both stages with [`../prepared/build.py`](../prepared/build.py), selecting this directory with `--evidence-root benchmarks/crypto/round4` and distinct `prepared-round4-*` stage names. Point baseline `--plugin-roots` at the frozen baseline plugin build and candidate roots at the candidate. Use the same `--case-root`, `--fast-root`, manifest workload and locked dependencies for both. Run each complete cohort with [`../prepared/run.mjs`](../prepared/run.mjs), three fresh canisters per case.

Only one PocketIC counter runner runs at a time. Capped builds may overlap deterministic instruction measurements; wall-clock timings are not compared.

```sh
python3 benchmarks/crypto/round4/compare.py \
  --baseline benchmarks/crypto/round4/results/prepared-round4-ed25519-c1-baseline \
  --candidate benchmarks/crypto/round4/results/prepared-round4-ed25519-c1-candidate \
  --target-plugin ed25519 \
  --json benchmarks/crypto/round4/comparisons/ed25519-c1.json \
  --markdown benchmarks/crypto/round4/comparisons/ed25519-c1.md
```

The comparator reuses the prepared evidence validator and statistics. It rejects failures, incomplete trials, duplicate or missing cases, changed actors or source-local imports, fixture/oracle differences, different compiler/RTS/runner/PocketIC/dependency fingerprints, changed `mo:fast` sources, builder changes and different compiler flags. Only recorded compiler/stage paths are normalized. The selected plugin's source/artifact pins and declared payload size may differ; other plugin pins must match. Every original artifact is validated independently. Output files are never overwritten.

Reports show instruction and allocation medians/ranges, exact prepared payload, canister Wasm size and plugin runtime Wasm size. JSON also retains source/artifact metadata, reclaimed bytes and all sampled memory counters. Occupied heap snapshots are neither peak nor retained live memory. Payload is declared layout size, not a heap measurement. Each row measures the entire timed interval: `prepare` is one factory; `direct`/`prepared` are N calls; `cold` includes preparation and N calls. There is no modeled cold cost or batch division. Use the existing prepared summarizer separately within each revision for complete triplets and break-even models.

Pack only finalized round-four stages using the prepared pack/restore/verify tools with this same `--evidence-root`. Packing replaces that root's source-store index/archive; include the entire intended cohort. Never repack the historical prepared store. Source archive integrity verification and successful measurement validation are separate checks.

Focused tests (standard library only):

```sh
python3 -m unittest discover -s benchmarks/crypto/round4 -p 'test_compare.py'
```
