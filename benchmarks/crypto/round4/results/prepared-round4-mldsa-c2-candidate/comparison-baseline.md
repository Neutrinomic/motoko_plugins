# Plugin revision comparison

Target: `ml-dsa`. Baseline: `prepared-round4-mldsa-c1-baseline`; candidate: `prepared-round4-mldsa-c2-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| mldsa-public-key-acvp-4-control-n1 | control/1 | 5,107,151 [5,107,151–5,107,151] | 4,952,706 [4,952,706–4,952,706] | 3.02% | 1.031× |
| mldsa-sign-acvp-4-direct-n1 | direct/1 | 13,193,656 [13,193,656–13,193,656] | 13,039,211 [13,039,211–13,039,211] | 1.17% | 1.012× |
| mldsa-sign-acvp-4-prepare-n1 | prepare/1 | 5,016,889 [5,016,889–5,016,889] | 4,862,444 [4,862,444–4,862,444] | 3.08% | 1.032× |
| mldsa-sign-acvp-4-prepared-n1 | prepared/1 | 9,076,804 [9,076,804–9,076,804] | 8,890,133 [8,890,133–8,890,133] | 2.06% | 1.021× |
| mldsa-sign-acvp-6-direct-n1 | direct/1 | 25,979,729 [25,979,729–25,979,729] | 25,825,284 [25,825,284–25,825,284] | 0.59% | 1.006× |
| mldsa-sign-acvp-6-prepare-n1 | prepare/1 | 4,994,195 [4,994,195–4,994,195] | 4,839,750 [4,839,750–4,839,750] | 3.09% | 1.032× |
| mldsa-sign-acvp-6-prepared-n1 | prepared/1 | 21,885,571 [21,885,571–21,885,571] | 21,698,900 [21,698,900–21,698,900] | 0.85% | 1.009× |
| mldsa-verify-acvp-4-direct-n1 | direct/1 | 3,810,844 [3,810,844–3,810,844] | 3,656,399 [3,656,399–3,656,399] | 4.05% | 1.042× |
| mldsa-verify-acvp-4-prepare-n1 | prepare/1 | 2,525,559 [2,525,559–2,525,559] | 2,371,114 [2,371,114–2,371,114] | 6.12% | 1.065× |
| mldsa-verify-acvp-4-prepared-n1 | prepared/1 | 1,920,986 [1,920,986–1,920,986] | 1,787,636 [1,787,636–1,787,636] | 6.94% | 1.075× |
| mldsa-verify-acvp-6-direct-n1 | direct/1 | 3,905,985 [3,905,985–3,905,985] | 3,751,540 [3,751,540–3,751,540] | 3.95% | 1.041× |
| mldsa-verify-acvp-6-prepare-n1 | prepare/1 | 2,525,559 [2,525,559–2,525,559] | 2,371,114 [2,371,114–2,371,114] | 6.12% | 1.065× |
| mldsa-verify-acvp-6-prepared-n1 | prepared/1 | 2,016,127 [2,016,127–2,016,127] | 1,882,777 [1,882,777–1,882,777] | 6.61% | 1.071× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| mldsa-public-key-acvp-4-control-n1 | 1,368 [1,368–1,368] → 1,368 [1,368–1,368] | 0 → 0 | 371,976 → 372,597 | 123026 → 123611 |
| mldsa-sign-acvp-4-direct-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 0 → 0 | 372,330 → 372,951 | 123026 → 123611 |
| mldsa-sign-acvp-4-prepare-n1 | 28,856 [28,856–28,856] → 28,856 [28,856–28,856] | 28,800 → 28,800 | 373,714 → 374,335 | 123026 → 123611 |
| mldsa-sign-acvp-4-prepared-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 28,800 → 28,800 | 373,858 → 374,479 | 123026 → 123611 |
| mldsa-sign-acvp-6-direct-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 0 → 0 | 373,372 → 373,993 | 123026 → 123611 |
| mldsa-sign-acvp-6-prepare-n1 | 28,856 [28,856–28,856] → 28,856 [28,856–28,856] | 28,800 → 28,800 | 374,756 → 375,377 | 123026 → 123611 |
| mldsa-sign-acvp-6-prepared-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 28,800 → 28,800 | 374,900 → 375,521 | 123026 → 123611 |
| mldsa-verify-acvp-4-direct-n1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 376,371 → 376,992 | 123026 → 123611 |
| mldsa-verify-acvp-4-prepare-n1 | 20,632 [20,632–20,632] → 20,632 [20,632–20,632] | 20,576 → 20,576 | 377,744 → 378,365 | 123026 → 123611 |
| mldsa-verify-acvp-4-prepared-n1 | 32 [32–32] → 32 [32–32] | 20,576 → 20,576 | 377,900 → 378,521 | 123026 → 123611 |
| mldsa-verify-acvp-6-direct-n1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 377,413 → 378,034 | 123026 → 123611 |
| mldsa-verify-acvp-6-prepare-n1 | 20,632 [20,632–20,632] → 20,632 [20,632–20,632] | 20,576 → 20,576 | 378,786 → 379,407 | 123026 → 123611 |
| mldsa-verify-acvp-6-prepared-n1 | 32 [32–32] → 32 [32–32] | 20,576 → 20,576 | 378,942 → 379,563 | 123026 → 123611 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
