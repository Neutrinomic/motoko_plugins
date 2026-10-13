# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-bls6-final-baseline`; candidate: `prepared-bls6-final-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n2-direct | direct/1 | 915,594,594 [915,594,594–915,594,594] | 559,152,229 [559,152,229–559,152,229] | 38.93% | 1.637× |
| bls12-381-aggregate-ethereum-distinct-n2-prepare | prepare/1 | 549,948,940 [549,948,940–549,948,940] | 335,089,942 [335,089,942–335,089,942] | 39.07% | 1.641× |
| bls12-381-aggregate-ethereum-distinct-n2-prepared | prepared/1 | 365,647,166 [365,647,166–365,647,166] | 224,063,799 [224,063,799–224,063,799] | 38.72% | 1.632× |
| bls12-381-aggregate-ic-distinct-n2-direct | direct/1 | 291,392,273 [291,392,273–291,392,273] | 176,889,136 [176,889,136–176,889,136] | 39.30% | 1.647× |
| bls12-381-aggregate-ic-distinct-n2-prepare | prepare/1 | 86,625,804 [86,625,804–86,625,804] | 52,842,944 [52,842,944–52,842,944] | 39.00% | 1.639× |
| bls12-381-aggregate-ic-distinct-n2-prepared | prepared/1 | 204,848,489 [204,848,489–204,848,489] | 124,128,212 [124,128,212–124,128,212] | 39.40% | 1.650× |
| bls12-381-verify-ethereum-official-direct | direct/1 | 274,974,367 [274,974,367–274,974,367] | 167,544,868 [167,544,868–167,544,868] | 39.07% | 1.641× |
| bls12-381-verify-ethereum-official-prepare | prepare/1 | 11,144,375 [11,144,375–11,144,375] | 6,341,823 [6,341,823–6,341,823] | 43.09% | 1.757× |
| bls12-381-verify-ethereum-official-prepared | prepared/1 | 263,831,154 [263,831,154–263,831,154] | 161,204,207 [161,204,207–161,204,207] | 38.90% | 1.637× |
| bls12-381-verify-ic-certificate-direct | direct/1 | 210,673,356 [210,673,356–210,673,356] | 127,630,963 [127,630,963–127,630,963] | 39.42% | 1.651× |
| bls12-381-verify-ic-certificate-prepare | prepare/1 | 43,312,942 [43,312,942–43,312,942] | 26,421,512 [26,421,512–26,421,512] | 39.00% | 1.639× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 167,427,790 [167,427,790–167,427,790] | 101,276,827 [101,276,827–101,276,827] | 39.51% | 1.653× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n2-direct | 60,392 [60,392–60,392] → 60,392 [60,392–60,392] | 0 → 0 | 897,083 → 860,564 | 655629 → 617967 |
| bls12-381-aggregate-ethereum-distinct-n2-prepare | 440 [440–440] → 440 [440–440] | 288 → 288 | 900,828 → 864,309 | 655629 → 617967 |
| bls12-381-aggregate-ethereum-distinct-n2-prepared | 60,600 [60,600–60,600] → 60,600 [60,600–60,600] | 288 → 288 | 901,125 → 864,606 | 655629 → 617967 |
| bls12-381-aggregate-ic-distinct-n2-direct | 40,552 [40,552–40,552] → 40,552 [40,552–40,552] | 0 → 0 | 896,285 → 859,766 | 655629 → 617967 |
| bls12-381-aggregate-ic-distinct-n2-prepare | 39,512 [39,512–39,512] → 39,512 [39,512–39,512] | 39,360 → 39,360 | 900,009 → 863,490 | 655629 → 617967 |
| bls12-381-aggregate-ic-distinct-n2-prepared | 544 [544–544] → 544 [544–544] | 39,360 → 39,360 | 900,330 → 863,811 | 655629 → 617967 |
| bls12-381-verify-ethereum-official-direct | 64 [64–64] → 64 [64–64] | 0 → 0 | 893,815 → 857,296 | 655629 → 617967 |
| bls12-381-verify-ethereum-official-prepare | 200 [200–200] → 200 [200–200] | 144 → 144 | 895,937 → 859,418 | 655629 → 617967 |
| bls12-381-verify-ethereum-official-prepared | 64 [64–64] → 64 [64–64] | 144 → 144 | 896,308 → 859,789 | 655629 → 617967 |
| bls12-381-verify-ic-certificate-direct | 64 [64–64] → 64 [64–64] | 0 → 0 | 893,829 → 857,310 | 655629 → 617967 |
| bls12-381-verify-ic-certificate-prepare | 19,736 [19,736–19,736] → 19,736 [19,736–19,736] | 19,680 → 19,680 | 895,952 → 859,433 | 655629 → 617967 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 896,323 → 859,804 | 655629 → 617967 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
