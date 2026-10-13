# Plugin revision comparison

Target: `p256`. Baseline: `prepared-round4-p256-c3-candidate`; candidate: `prepared-round4-p256-c4-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| p256-r4-convert-compressed-to-uncompressed | control/1 | 581,887 [581,887–581,887] | 581,887 [581,887–581,887] | 0.00% | 1.000× |
| p256-r4-derivePublicKey-rfc6979-sample | control/1 | 3,788,208 [3,788,208–3,788,208] | 3,297,998 [3,297,998–3,297,998] | 12.94% | 1.149× |
| p256-r4-rfc-sample-direct-1 | direct/1 | 12,541,547 [12,541,547–12,541,547] | 12,541,547 [12,541,547–12,541,547] | 0.00% | 1.000× |
| p256-r4-rfc-sample-prepare-1 | prepare/1 | 19,688,627 [19,688,627–19,688,627] | 19,688,627 [19,688,627–19,688,627] | 0.00% | 1.000× |
| p256-r4-rfc-sample-prepared-1 | prepared/1 | 3,803,061 [3,803,061–3,803,061] | 3,803,061 [3,803,061–3,803,061] | 0.00% | 1.000× |
| p256-r4-signPrehash-rfc6979-sample | control/1 | 5,281,869 [5,281,869–5,281,869] | 4,791,659 [4,791,659–4,791,659] | 9.28% | 1.102× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| p256-r4-convert-compressed-to-uncompressed | 128 [128–128] → 128 [128–128] | 0 → 0 | 379,928 → 386,900 | 134104 → 141060 |
| p256-r4-derivePublicKey-rfc6979-sample | 96 [96–96] → 96 [96–96] | 0 → 0 | 379,943 → 386,915 | 134104 → 141060 |
| p256-r4-rfc-sample-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 380,332 → 387,304 | 134104 → 141060 |
| p256-r4-rfc-sample-prepare-1 | 16,376 [16,376–16,376] → 16,376 [16,376–16,376] | 16,320 → 16,320 | 381,880 → 388,852 | 134104 → 141060 |
| p256-r4-rfc-sample-prepared-1 | 32 [32–32] → 32 [32–32] | 16,320 → 16,320 | 382,073 → 389,045 | 134104 → 141060 |
| p256-r4-signPrehash-rfc6979-sample | 120 [120–120] → 120 [120–120] | 0 → 0 | 380,050 → 387,022 | 134104 → 141060 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
