# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-round4-bls12-381-c2-candidate`; candidate: `prepared-round4-bls12-381-c3-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | direct/1 | 3,176,407,705 [3,176,407,705–3,176,407,705] | 3,175,970,967 [3,175,970,967–3,175,970,967] | 0.01% | 1.000× |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | prepare/1 | 2,200,221,822 [2,200,221,822–2,200,221,822] | 2,199,794,662 [2,199,794,662–2,199,794,662] | 0.02% | 1.000× |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | prepared/1 | 976,190,426 [976,190,426–976,190,426] | 976,180,848 [976,180,848–976,180,848] | 0.00% | 1.000× |
| bls12-381-verify-ethereum-official-direct | direct/1 | 275,027,762 [275,027,762–275,027,762] | 274,974,367 [274,974,367–274,974,367] | 0.02% | 1.000× |
| bls12-381-verify-ethereum-official-prepare | prepare/1 | 11,144,375 [11,144,375–11,144,375] | 11,144,375 [11,144,375–11,144,375] | 0.00% | 1.000× |
| bls12-381-verify-ethereum-official-prepared | prepared/1 | 263,884,549 [263,884,549–263,884,549] | 263,831,154 [263,831,154–263,831,154] | 0.02% | 1.000× |
| bls12-381-verify-ic-certificate-direct | direct/1 | 210,694,553 [210,694,553–210,694,553] | 210,673,356 [210,673,356–210,673,356] | 0.01% | 1.000× |
| bls12-381-verify-ic-certificate-prepare | prepare/1 | 43,312,942 [43,312,942–43,312,942] | 43,312,942 [43,312,942–43,312,942] | 0.00% | 1.000× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 167,423,232 [167,423,232–167,423,232] | 167,427,790 [167,427,790–167,427,790] | -0.00% | 1.000× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | 494,840 [494,840–494,840] → 181,112 [181,112–181,112] | 0 → 0 | 895,107 → 899,933 | 650746 → 655629 |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | 315,416 [315,416–315,416] → 1,688 [1,688–1,688] | 1,152 → 1,152 | 912,361 → 917,187 | 650746 → 655629 |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | 181,552 [181,552–181,552] → 181,552 [181,552–181,552] | 1,152 → 1,152 | 912,673 → 917,499 | 650746 → 655629 |
| bls12-381-verify-ethereum-official-direct | 39,280 [39,280–39,280] → 64 [64–64] | 0 → 0 | 888,989 → 893,815 | 650746 → 655629 |
| bls12-381-verify-ethereum-official-prepare | 200 [200–200] → 200 [200–200] | 144 → 144 | 891,111 → 895,937 | 650746 → 655629 |
| bls12-381-verify-ethereum-official-prepared | 39,280 [39,280–39,280] → 64 [64–64] | 144 → 144 | 891,482 → 896,308 | 650746 → 655629 |
| bls12-381-verify-ic-certificate-direct | 19,672 [19,672–19,672] → 64 [64–64] | 0 → 0 | 889,003 → 893,829 | 650746 → 655629 |
| bls12-381-verify-ic-certificate-prepare | 19,736 [19,736–19,736] → 19,736 [19,736–19,736] | 19,680 → 19,680 | 891,126 → 895,952 | 650746 → 655629 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 891,497 → 896,323 | 650746 → 655629 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
