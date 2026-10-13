# Plugin revision comparison

Target: `ml-dsa`. Baseline: `prepared-round4-mldsa-c1-candidate`; candidate: `prepared-round4-mldsa-c2-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| mldsa-public-key-acvp-4-control-n1 | control/1 | 4,952,706 [4,952,706–4,952,706] | 4,952,706 [4,952,706–4,952,706] | 0.00% | 1.000× |
| mldsa-sign-acvp-4-direct-n1 | direct/1 | 13,039,211 [13,039,211–13,039,211] | 13,039,211 [13,039,211–13,039,211] | 0.00% | 1.000× |
| mldsa-sign-acvp-4-prepare-n1 | prepare/1 | 4,862,444 [4,862,444–4,862,444] | 4,862,444 [4,862,444–4,862,444] | 0.00% | 1.000× |
| mldsa-sign-acvp-4-prepared-n1 | prepared/1 | 9,076,804 [9,076,804–9,076,804] | 8,890,133 [8,890,133–8,890,133] | 2.06% | 1.021× |
| mldsa-sign-acvp-6-direct-n1 | direct/1 | 25,825,284 [25,825,284–25,825,284] | 25,825,284 [25,825,284–25,825,284] | 0.00% | 1.000× |
| mldsa-sign-acvp-6-prepare-n1 | prepare/1 | 4,839,750 [4,839,750–4,839,750] | 4,839,750 [4,839,750–4,839,750] | 0.00% | 1.000× |
| mldsa-sign-acvp-6-prepared-n1 | prepared/1 | 21,885,571 [21,885,571–21,885,571] | 21,698,900 [21,698,900–21,698,900] | 0.85% | 1.009× |
| mldsa-verify-acvp-4-direct-n1 | direct/1 | 3,656,399 [3,656,399–3,656,399] | 3,656,399 [3,656,399–3,656,399] | 0.00% | 1.000× |
| mldsa-verify-acvp-4-prepare-n1 | prepare/1 | 2,371,114 [2,371,114–2,371,114] | 2,371,114 [2,371,114–2,371,114] | 0.00% | 1.000× |
| mldsa-verify-acvp-4-prepared-n1 | prepared/1 | 1,920,986 [1,920,986–1,920,986] | 1,787,636 [1,787,636–1,787,636] | 6.94% | 1.075× |
| mldsa-verify-acvp-6-direct-n1 | direct/1 | 3,751,540 [3,751,540–3,751,540] | 3,751,540 [3,751,540–3,751,540] | 0.00% | 1.000× |
| mldsa-verify-acvp-6-prepare-n1 | prepare/1 | 2,371,114 [2,371,114–2,371,114] | 2,371,114 [2,371,114–2,371,114] | 0.00% | 1.000× |
| mldsa-verify-acvp-6-prepared-n1 | prepared/1 | 2,016,127 [2,016,127–2,016,127] | 1,882,777 [1,882,777–1,882,777] | 6.61% | 1.071× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| mldsa-public-key-acvp-4-control-n1 | 1,368 [1,368–1,368] → 1,368 [1,368–1,368] | 0 → 0 | 371,807 → 372,597 | 122860 → 123611 |
| mldsa-sign-acvp-4-direct-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 0 → 0 | 372,161 → 372,951 | 122860 → 123611 |
| mldsa-sign-acvp-4-prepare-n1 | 28,856 [28,856–28,856] → 28,856 [28,856–28,856] | 28,800 → 28,800 | 373,545 → 374,335 | 122860 → 123611 |
| mldsa-sign-acvp-4-prepared-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 28,800 → 28,800 | 373,689 → 374,479 | 122860 → 123611 |
| mldsa-sign-acvp-6-direct-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 0 → 0 | 373,203 → 373,993 | 122860 → 123611 |
| mldsa-sign-acvp-6-prepare-n1 | 28,856 [28,856–28,856] → 28,856 [28,856–28,856] | 28,800 → 28,800 | 374,587 → 375,377 | 122860 → 123611 |
| mldsa-sign-acvp-6-prepared-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 28,800 → 28,800 | 374,731 → 375,521 | 122860 → 123611 |
| mldsa-verify-acvp-4-direct-n1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 376,202 → 376,992 | 122860 → 123611 |
| mldsa-verify-acvp-4-prepare-n1 | 20,632 [20,632–20,632] → 20,632 [20,632–20,632] | 20,576 → 20,576 | 377,575 → 378,365 | 122860 → 123611 |
| mldsa-verify-acvp-4-prepared-n1 | 32 [32–32] → 32 [32–32] | 20,576 → 20,576 | 377,731 → 378,521 | 122860 → 123611 |
| mldsa-verify-acvp-6-direct-n1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 377,244 → 378,034 | 122860 → 123611 |
| mldsa-verify-acvp-6-prepare-n1 | 20,632 [20,632–20,632] → 20,632 [20,632–20,632] | 20,576 → 20,576 | 378,617 → 379,407 | 122860 → 123611 |
| mldsa-verify-acvp-6-prepared-n1 | 32 [32–32] → 32 [32–32] | 20,576 → 20,576 | 378,773 → 379,563 | 122860 → 123611 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
