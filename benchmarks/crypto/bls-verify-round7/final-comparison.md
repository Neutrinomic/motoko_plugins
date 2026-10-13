# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-bls7-final-baseline`; candidate: `prepared-bls7-final-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n2-direct | direct/1 | 559,152,229 [559,152,229–559,152,229] | 472,864,770 [472,864,770–472,864,770] | 15.43% | 1.182× |
| bls12-381-aggregate-ethereum-distinct-n2-prepare | prepare/1 | 335,089,942 [335,089,942–335,089,942] | 283,329,926 [283,329,926–283,329,926] | 15.45% | 1.183× |
| bls12-381-aggregate-ethereum-distinct-n2-prepared | prepared/1 | 224,063,799 [224,063,799–224,063,799] | 189,536,356 [189,536,356–189,536,356] | 15.41% | 1.182× |
| bls12-381-aggregate-ethereum-distinct-n8-direct | direct/1 | 1,941,213,088 [1,941,213,088–1,941,213,088] | 1,643,095,683 [1,643,095,683–1,643,095,683] | 15.36% | 1.181× |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | prepare/1 | 1,340,358,670 [1,340,358,670–1,340,358,670] | 1,133,318,606 [1,133,318,606–1,133,318,606] | 15.45% | 1.183× |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | prepared/1 | 600,858,961 [600,858,961–600,858,961] | 509,781,620 [509,781,620–509,781,620] | 15.16% | 1.179× |
| bls12-381-aggregate-ic-distinct-n2-direct | direct/1 | 176,889,136 [176,889,136–176,889,136] | 150,133,148 [150,133,148–150,133,148] | 15.13% | 1.178× |
| bls12-381-aggregate-ic-distinct-n2-prepare | prepare/1 | 52,842,944 [52,842,944–52,842,944] | 45,147,598 [45,147,598–45,147,598] | 14.56% | 1.170× |
| bls12-381-aggregate-ic-distinct-n2-prepared | prepared/1 | 124,128,212 [124,128,212–124,128,212] | 105,067,570 [105,067,570–105,067,570] | 15.36% | 1.181× |
| bls12-381-verify-ethereum-official-direct | direct/1 | 167,544,868 [167,544,868–167,544,868] | 141,664,860 [141,664,860–141,664,860] | 15.45% | 1.183× |
| bls12-381-verify-ethereum-official-prepare | prepare/1 | 6,341,823 [6,341,823–6,341,823] | 5,564,301 [5,564,301–5,564,301] | 12.26% | 1.140× |
| bls12-381-verify-ethereum-official-prepared | prepared/1 | 161,204,207 [161,204,207–161,204,207] | 136,101,721 [136,101,721–136,101,721] | 15.57% | 1.184× |
| bls12-381-verify-ic-certificate-direct | direct/1 | 127,630,963 [127,630,963–127,630,963] | 107,949,293 [107,949,293–107,949,293] | 15.42% | 1.182× |
| bls12-381-verify-ic-certificate-prepare | prepare/1 | 26,421,512 [26,421,512–26,421,512] | 22,573,839 [22,573,839–22,573,839] | 14.56% | 1.170× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 101,276,827 [101,276,827–101,276,827] | 85,442,830 [85,442,830–85,442,830] | 15.63% | 1.185× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n2-direct | 60,392 [60,392–60,392] → 60,392 [60,392–60,392] | 0 → 0 | 860,564 → 585,511 | 617967 → 342359 |
| bls12-381-aggregate-ethereum-distinct-n2-prepare | 440 [440–440] → 440 [440–440] | 288 → 288 | 864,309 → 589,256 | 617967 → 342359 |
| bls12-381-aggregate-ethereum-distinct-n2-prepared | 60,600 [60,600–60,600] → 60,600 [60,600–60,600] | 288 → 288 | 864,606 → 589,553 | 617967 → 342359 |
| bls12-381-aggregate-ethereum-distinct-n8-direct | 181,112 [181,112–181,112] → 181,112 [181,112–181,112] | 0 → 0 | 863,414 → 588,361 | 617967 → 342359 |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | 1,688 [1,688–1,688] → 1,688 [1,688–1,688] | 1,152 → 1,152 | 880,668 → 605,615 | 617967 → 342359 |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | 181,552 [181,552–181,552] → 181,552 [181,552–181,552] | 1,152 → 1,152 | 880,980 → 605,927 | 617967 → 342359 |
| bls12-381-aggregate-ic-distinct-n2-direct | 40,552 [40,552–40,552] → 40,552 [40,552–40,552] | 0 → 0 | 859,766 → 584,713 | 617967 → 342359 |
| bls12-381-aggregate-ic-distinct-n2-prepare | 39,512 [39,512–39,512] → 39,512 [39,512–39,512] | 39,360 → 39,360 | 863,490 → 588,437 | 617967 → 342359 |
| bls12-381-aggregate-ic-distinct-n2-prepared | 544 [544–544] → 544 [544–544] | 39,360 → 39,360 | 863,811 → 588,758 | 617967 → 342359 |
| bls12-381-verify-ethereum-official-direct | 64 [64–64] → 64 [64–64] | 0 → 0 | 857,296 → 582,243 | 617967 → 342359 |
| bls12-381-verify-ethereum-official-prepare | 200 [200–200] → 200 [200–200] | 144 → 144 | 859,418 → 584,365 | 617967 → 342359 |
| bls12-381-verify-ethereum-official-prepared | 64 [64–64] → 64 [64–64] | 144 → 144 | 859,789 → 584,736 | 617967 → 342359 |
| bls12-381-verify-ic-certificate-direct | 64 [64–64] → 64 [64–64] | 0 → 0 | 857,310 → 582,257 | 617967 → 342359 |
| bls12-381-verify-ic-certificate-prepare | 19,736 [19,736–19,736] → 19,736 [19,736–19,736] | 19,680 → 19,680 | 859,433 → 584,380 | 617967 → 342359 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 859,804 → 584,751 | 617967 → 342359 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
