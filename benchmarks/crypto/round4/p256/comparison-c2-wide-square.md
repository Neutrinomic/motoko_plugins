# Plugin revision comparison

Target: `p256`. Baseline: `prepared-round4-p256-c1-candidate`; candidate: `prepared-round4-p256-c2-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| p256-r4-convert-compressed-to-uncompressed | control/1 | 581,934 [581,934–581,934] | 581,934 [581,934–581,934] | 0.00% | 1.000× |
| p256-r4-derivePublicKey-rfc6979-sample | control/1 | 4,996,581 [4,996,581–4,996,581] | 4,996,581 [4,996,581–4,996,581] | 0.00% | 1.000× |
| p256-r4-rfc-sample-direct-1 | direct/1 | 12,541,922 [12,541,922–12,541,922] | 12,542,112 [12,542,112–12,542,112] | -0.00% | 1.000× |
| p256-r4-rfc-sample-prepare-1 | prepare/1 | 19,688,675 [19,688,675–19,688,675] | 19,688,675 [19,688,675–19,688,675] | 0.00% | 1.000× |
| p256-r4-rfc-sample-prepared-1 | prepared/1 | 3,802,871 [3,802,871–3,802,871] | 3,803,061 [3,803,061–3,803,061] | -0.00% | 1.000× |
| p256-r4-signPrehash-rfc6979-sample | control/1 | 6,603,023 [6,603,023–6,603,023] | 6,490,242 [6,490,242–6,490,242] | 1.71% | 1.017× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| p256-r4-convert-compressed-to-uncompressed | 128 [128–128] → 128 [128–128] | 0 → 0 | 384,520 → 375,644 | 139176 → 130004 |
| p256-r4-derivePublicKey-rfc6979-sample | 96 [96–96] → 96 [96–96] | 0 → 0 | 384,535 → 375,659 | 139176 → 130004 |
| p256-r4-rfc-sample-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 384,924 → 376,048 | 139176 → 130004 |
| p256-r4-rfc-sample-prepare-1 | 16,376 [16,376–16,376] → 16,376 [16,376–16,376] | 16,320 → 16,320 | 386,472 → 377,596 | 139176 → 130004 |
| p256-r4-rfc-sample-prepared-1 | 32 [32–32] → 32 [32–32] | 16,320 → 16,320 | 386,665 → 377,789 | 139176 → 130004 |
| p256-r4-signPrehash-rfc6979-sample | 120 [120–120] → 120 [120–120] | 0 → 0 | 384,642 → 375,766 | 139176 → 130004 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
