# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-round4-bls12-381-c1-baseline`; candidate: `prepared-round4-bls12-381-c3-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | direct/1 | 3,285,303,573 [3,285,303,573–3,285,303,573] | 3,175,970,967 [3,175,970,967–3,175,970,967] | 3.33% | 1.034× |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | prepare/1 | 2,291,247,278 [2,291,247,278–2,291,247,278] | 2,199,794,662 [2,199,794,662–2,199,794,662] | 3.99% | 1.042× |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | prepared/1 | 994,060,838 [994,060,838–994,060,838] | 976,180,848 [976,180,848–976,180,848] | 1.80% | 1.018× |
| bls12-381-verify-ethereum-official-direct | direct/1 | 286,405,944 [286,405,944–286,405,944] | 274,974,367 [274,974,367–274,974,367] | 3.99% | 1.042× |
| bls12-381-verify-ethereum-official-prepare | prepare/1 | 12,239,690 [12,239,690–12,239,690] | 11,144,375 [11,144,375–11,144,375] | 8.95% | 1.098× |
| bls12-381-verify-ethereum-official-prepared | prepared/1 | 274,167,416 [274,167,416–274,167,416] | 263,831,154 [263,831,154–263,831,154] | 3.77% | 1.039× |
| bls12-381-verify-ic-certificate-direct | direct/1 | 222,072,725 [222,072,725–222,072,725] | 210,673,356 [210,673,356–210,673,356] | 5.13% | 1.054× |
| bls12-381-verify-ic-certificate-prepare | prepare/1 | 49,992,831 [49,992,831–49,992,831] | 43,312,942 [43,312,942–43,312,942] | 13.36% | 1.154× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 172,121,515 [172,121,515–172,121,515] | 167,427,790 [167,427,790–167,427,790] | 2.73% | 1.028× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | 494,840 [494,840–494,840] → 181,112 [181,112–181,112] | 0 → 0 | 854,312 → 899,933 | 608575 → 655629 |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | 315,416 [315,416–315,416] → 1,688 [1,688–1,688] | 1,152 → 1,152 | 871,566 → 917,187 | 608575 → 655629 |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | 181,552 [181,552–181,552] → 181,552 [181,552–181,552] | 1,152 → 1,152 | 871,878 → 917,499 | 608575 → 655629 |
| bls12-381-verify-ethereum-official-direct | 39,280 [39,280–39,280] → 64 [64–64] | 0 → 0 | 848,194 → 893,815 | 608575 → 655629 |
| bls12-381-verify-ethereum-official-prepare | 200 [200–200] → 200 [200–200] | 144 → 144 | 850,316 → 895,937 | 608575 → 655629 |
| bls12-381-verify-ethereum-official-prepared | 39,280 [39,280–39,280] → 64 [64–64] | 144 → 144 | 850,687 → 896,308 | 608575 → 655629 |
| bls12-381-verify-ic-certificate-direct | 19,672 [19,672–19,672] → 64 [64–64] | 0 → 0 | 848,208 → 893,829 | 608575 → 655629 |
| bls12-381-verify-ic-certificate-prepare | 19,736 [19,736–19,736] → 19,736 [19,736–19,736] | 19,680 → 19,680 | 850,331 → 895,952 | 608575 → 655629 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 850,702 → 896,323 | 608575 → 655629 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
