# Plugin revision comparison

Target: `ml-dsa`. Baseline: `prepared-round4-mldsa-finalextra-baseline`; candidate: `prepared-round4-mldsa-finalextra-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| mldsa-sign-acvp-11-direct-n1 | direct/1 | 8,757,856 [8,757,856–8,757,856] | 8,603,411 [8,603,411–8,603,411] | 1.76% | 1.018× |
| mldsa-sign-acvp-11-prepare-n1 | prepare/1 | 5,005,869 [5,005,869–5,005,869] | 4,851,424 [4,851,424–4,851,424] | 3.09% | 1.032× |
| mldsa-sign-acvp-11-prepared-n1 | prepared/1 | 4,652,024 [4,652,024–4,652,024] | 4,465,353 [4,465,353–4,465,353] | 4.01% | 1.042× |
| mldsa-sign-randomized-acvp-362-direct-n1 | direct/1 | 18,343,541 [18,343,541–18,343,541] | 18,189,172 [18,189,172–18,189,172] | 0.84% | 1.008× |
| mldsa-sign-randomized-acvp-362-prepare-n1 | prepare/1 | 5,017,319 [5,017,319–5,017,319] | 4,862,950 [4,862,950–4,862,950] | 3.08% | 1.032× |
| mldsa-sign-randomized-acvp-362-prepared-n1 | prepared/1 | 14,226,247 [14,226,247–14,226,247] | 14,039,576 [14,039,576–14,039,576] | 1.31% | 1.013× |
| mldsa-verify-acvp-11-direct-n1 | direct/1 | 4,471,060 [4,471,060–4,471,060] | 4,316,615 [4,316,615–4,316,615] | 3.45% | 1.036× |
| mldsa-verify-acvp-11-prepare-n1 | prepare/1 | 2,525,559 [2,525,559–2,525,559] | 2,371,114 [2,371,114–2,371,114] | 6.12% | 1.065× |
| mldsa-verify-acvp-11-prepared-n1 | prepared/1 | 2,581,202 [2,581,202–2,581,202] | 2,447,852 [2,447,852–2,447,852] | 5.17% | 1.054× |
| mldsa-verify-acvp-362-direct-n1 | direct/1 | 3,874,229 [3,874,229–3,874,229] | 3,719,860 [3,719,860–3,719,860] | 3.98% | 1.041× |
| mldsa-verify-acvp-362-prepare-n1 | prepare/1 | 2,525,407 [2,525,407–2,525,407] | 2,371,038 [2,371,038–2,371,038] | 6.11% | 1.065× |
| mldsa-verify-acvp-362-prepared-n1 | prepared/1 | 1,984,523 [1,984,523–1,984,523] | 1,851,173 [1,851,173–1,851,173] | 6.72% | 1.072× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| mldsa-sign-acvp-11-direct-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 0 → 0 | 380,725 → 381,346 | 123026 → 123611 |
| mldsa-sign-acvp-11-prepare-n1 | 28,856 [28,856–28,856] → 28,856 [28,856–28,856] | 28,800 → 28,800 | 382,109 → 382,730 | 123026 → 123611 |
| mldsa-sign-acvp-11-prepared-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 28,800 → 28,800 | 382,253 → 382,874 | 123026 → 123611 |
| mldsa-sign-randomized-acvp-362-direct-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 0 → 0 | 373,234 → 373,855 | 123026 → 123611 |
| mldsa-sign-randomized-acvp-362-prepare-n1 | 28,856 [28,856–28,856] → 28,856 [28,856–28,856] | 28,800 → 28,800 | 374,618 → 375,239 | 123026 → 123611 |
| mldsa-sign-randomized-acvp-362-prepared-n1 | 2,480 [2,480–2,480] → 2,480 [2,480–2,480] | 28,800 → 28,800 | 374,762 → 375,383 | 123026 → 123611 |
| mldsa-verify-acvp-11-direct-n1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 384,766 → 385,387 | 123026 → 123611 |
| mldsa-verify-acvp-11-prepare-n1 | 20,632 [20,632–20,632] → 20,632 [20,632–20,632] | 20,576 → 20,576 | 386,139 → 386,760 | 123026 → 123611 |
| mldsa-verify-acvp-11-prepared-n1 | 32 [32–32] → 32 [32–32] | 20,576 → 20,576 | 386,295 → 386,916 | 123026 → 123611 |
| mldsa-verify-acvp-362-direct-n1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 377,096 → 377,717 | 123026 → 123611 |
| mldsa-verify-acvp-362-prepare-n1 | 20,632 [20,632–20,632] → 20,632 [20,632–20,632] | 20,576 → 20,576 | 378,469 → 379,090 | 123026 → 123611 |
| mldsa-verify-acvp-362-prepared-n1 | 32 [32–32] → 32 [32–32] | 20,576 → 20,576 | 378,625 → 379,246 | 123026 → 123611 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
