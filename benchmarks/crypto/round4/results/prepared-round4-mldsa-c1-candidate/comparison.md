# Plugin revision comparison

Target: `ml-dsa`. Baseline: `prepared-round4-mldsa-c1-baseline`; candidate: `prepared-round4-mldsa-c1-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one factory, and cold includes one factory plus N calls. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| mldsa-public-key-acvp-4-control-n1 | control/1 | 5,107,151 [5,107,151–5,107,151] | 4,952,706 [4,952,706–4,952,706] | 3.02% | 1.031× |
| mldsa-sign-acvp-4-direct-n1 | direct/1 | 13,193,656 [13,193,656–13,193,656] | 13,039,211 [13,039,211–13,039,211] | 1.17% | 1.012× |
| mldsa-sign-acvp-4-prepare-n1 | prepare/1 | 5,016,889 [5,016,889–5,016,889] | 4,862,444 [4,862,444–4,862,444] | 3.08% | 1.032× |
| mldsa-sign-acvp-4-prepared-n1 | prepared/1 | 9,076,804 [9,076,804–9,076,804] | 9,076,804 [9,076,804–9,076,804] | 0.00% | 1.000× |
| mldsa-sign-acvp-6-direct-n1 | direct/1 | 25,979,729 [25,979,729–25,979,729] | 25,825,284 [25,825,284–25,825,284] | 0.59% | 1.006× |
| mldsa-sign-acvp-6-prepare-n1 | prepare/1 | 4,994,195 [4,994,195–4,994,195] | 4,839,750 [4,839,750–4,839,750] | 3.09% | 1.032× |
| mldsa-sign-acvp-6-prepared-n1 | prepared/1 | 21,885,571 [21,885,571–21,885,571] | 21,885,571 [21,885,571–21,885,571] | 0.00% | 1.000× |
| mldsa-verify-acvp-4-direct-n1 | direct/1 | 3,810,844 [3,810,844–3,810,844] | 3,656,399 [3,656,399–3,656,399] | 4.05% | 1.042× |
| mldsa-verify-acvp-4-prepare-n1 | prepare/1 | 2,525,559 [2,525,559–2,525,559] | 2,371,114 [2,371,114–2,371,114] | 6.12% | 1.065× |
| mldsa-verify-acvp-4-prepared-n1 | prepared/1 | 1,920,986 [1,920,986–1,920,986] | 1,920,986 [1,920,986–1,920,986] | 0.00% | 1.000× |
| mldsa-verify-acvp-6-direct-n1 | direct/1 | 3,905,985 [3,905,985–3,905,985] | 3,751,540 [3,751,540–3,751,540] | 3.95% | 1.041× |
| mldsa-verify-acvp-6-prepare-n1 | prepare/1 | 2,525,559 [2,525,559–2,525,559] | 2,371,114 [2,371,114–2,371,114] | 6.12% | 1.065× |
| mldsa-verify-acvp-6-prepared-n1 | prepared/1 | 2,016,127 [2,016,127–2,016,127] | 2,016,127 [2,016,127–2,016,127] | 0.00% | 1.000× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| mldsa-public-key-acvp-4-control-n1 | 1,368 [1,368–1,368] → 1,368 [1,368–1,368] | 0 → 0 | 371,976 → 371,807 | 123026 → 122860 |
| mldsa-sign-acvp-4-direct-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 0 → 0 | 372,330 → 372,161 | 123026 → 122860 |
| mldsa-sign-acvp-4-prepare-n1 | 28,856 [28,856–28,856] → 28,856 [28,856–28,856] | 28,800 → 28,800 | 373,714 → 373,545 | 123026 → 122860 |
| mldsa-sign-acvp-4-prepared-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 28,800 → 28,800 | 373,858 → 373,689 | 123026 → 122860 |
| mldsa-sign-acvp-6-direct-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 0 → 0 | 373,372 → 373,203 | 123026 → 122860 |
| mldsa-sign-acvp-6-prepare-n1 | 28,856 [28,856–28,856] → 28,856 [28,856–28,856] | 28,800 → 28,800 | 374,756 → 374,587 | 123026 → 122860 |
| mldsa-sign-acvp-6-prepared-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 28,800 → 28,800 | 374,900 → 374,731 | 123026 → 122860 |
| mldsa-verify-acvp-4-direct-n1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 376,371 → 376,202 | 123026 → 122860 |
| mldsa-verify-acvp-4-prepare-n1 | 20,632 [20,632–20,632] → 20,632 [20,632–20,632] | 20,576 → 20,576 | 377,744 → 377,575 | 123026 → 122860 |
| mldsa-verify-acvp-4-prepared-n1 | 32 [32–32] → 32 [32–32] | 20,576 → 20,576 | 377,900 → 377,731 | 123026 → 122860 |
| mldsa-verify-acvp-6-direct-n1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 377,413 → 377,244 | 123026 → 122860 |
| mldsa-verify-acvp-6-prepare-n1 | 20,632 [20,632–20,632] → 20,632 [20,632–20,632] | 20,576 → 20,576 | 378,786 → 378,617 | 123026 → 122860 |
| mldsa-verify-acvp-6-prepared-n1 | 32 [32–32] → 32 [32–32] | 20,576 → 20,576 | 378,942 → 378,773 | 123026 → 122860 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
