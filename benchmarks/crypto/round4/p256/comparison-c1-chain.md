# Plugin revision comparison

Target: `p256`. Baseline: `prepared-round4-p256-c1-baseline`; candidate: `prepared-round4-p256-c1-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one factory, and cold includes one factory plus N calls. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| p256-r4-convert-compressed-to-uncompressed | control/1 | 581,934 [581,934–581,934] | 581,934 [581,934–581,934] | 0.00% | 1.000× |
| p256-r4-derivePublicKey-rfc6979-sample | control/1 | 4,996,581 [4,996,581–4,996,581] | 4,996,581 [4,996,581–4,996,581] | 0.00% | 1.000× |
| p256-r4-rfc-sample-direct-1 | direct/1 | 12,541,922 [12,541,922–12,541,922] | 12,541,922 [12,541,922–12,541,922] | 0.00% | 1.000× |
| p256-r4-rfc-sample-prepare-1 | prepare/1 | 19,688,675 [19,688,675–19,688,675] | 19,688,675 [19,688,675–19,688,675] | 0.00% | 1.000× |
| p256-r4-rfc-sample-prepared-1 | prepared/1 | 3,802,871 [3,802,871–3,802,871] | 3,802,871 [3,802,871–3,802,871] | 0.00% | 1.000× |
| p256-r4-signPrehash-rfc6979-sample | control/1 | 7,252,878 [7,252,878–7,252,878] | 6,603,023 [6,603,023–6,603,023] | 8.96% | 1.098× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| p256-r4-convert-compressed-to-uncompressed | 128 [128–128] → 128 [128–128] | 0 → 0 | 371,436 → 384,520 | 125436 → 139176 |
| p256-r4-derivePublicKey-rfc6979-sample | 96 [96–96] → 96 [96–96] | 0 → 0 | 371,451 → 384,535 | 125436 → 139176 |
| p256-r4-rfc-sample-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 371,840 → 384,924 | 125436 → 139176 |
| p256-r4-rfc-sample-prepare-1 | 16,376 [16,376–16,376] → 16,376 [16,376–16,376] | 16,320 → 16,320 | 373,388 → 386,472 | 125436 → 139176 |
| p256-r4-rfc-sample-prepared-1 | 32 [32–32] → 32 [32–32] | 16,320 → 16,320 | 373,581 → 386,665 | 125436 → 139176 |
| p256-r4-signPrehash-rfc6979-sample | 120 [120–120] → 120 [120–120] | 0 → 0 | 371,558 → 384,642 | 125436 → 139176 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
