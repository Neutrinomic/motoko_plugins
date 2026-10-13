# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-bls6-screen-baseline`; candidate: `prepared-bls6-screen-pairing`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-verify-ic-certificate-direct | direct/1 | 210,673,356 [210,673,356–210,673,356] | 205,184,551 [205,184,551–205,184,551] | 2.61% | 1.027× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 167,427,790 [167,427,790–167,427,790] | 161,938,985 [161,938,985–161,938,985] | 3.28% | 1.034× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-verify-ic-certificate-direct | 64 [64–64] → 64 [64–64] | 0 → 0 | 893,829 → 853,796 | 655629 → 615596 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 896,323 → 856,290 | 655629 → 615596 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
