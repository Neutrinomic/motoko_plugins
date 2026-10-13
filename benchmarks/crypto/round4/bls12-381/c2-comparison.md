# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-round4-bls12-381-c1-baseline`; candidate: `prepared-round4-bls12-381-c2-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | direct/1 | 3,285,303,573 [3,285,303,573–3,285,303,573] | 3,176,407,705 [3,176,407,705–3,176,407,705] | 3.31% | 1.034× |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | prepare/1 | 2,291,247,278 [2,291,247,278–2,291,247,278] | 2,200,221,822 [2,200,221,822–2,200,221,822] | 3.97% | 1.041× |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | prepared/1 | 994,060,838 [994,060,838–994,060,838] | 976,190,426 [976,190,426–976,190,426] | 1.80% | 1.018× |
| bls12-381-verify-ethereum-official-direct | direct/1 | 286,405,944 [286,405,944–286,405,944] | 275,027,762 [275,027,762–275,027,762] | 3.97% | 1.041× |
| bls12-381-verify-ethereum-official-prepare | prepare/1 | 12,239,690 [12,239,690–12,239,690] | 11,144,375 [11,144,375–11,144,375] | 8.95% | 1.098× |
| bls12-381-verify-ethereum-official-prepared | prepared/1 | 274,167,416 [274,167,416–274,167,416] | 263,884,549 [263,884,549–263,884,549] | 3.75% | 1.039× |
| bls12-381-verify-ic-certificate-direct | direct/1 | 222,072,725 [222,072,725–222,072,725] | 210,694,553 [210,694,553–210,694,553] | 5.12% | 1.054× |
| bls12-381-verify-ic-certificate-prepare | prepare/1 | 49,992,831 [49,992,831–49,992,831] | 43,312,942 [43,312,942–43,312,942] | 13.36% | 1.154× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 172,121,515 [172,121,515–172,121,515] | 167,423,232 [167,423,232–167,423,232] | 2.73% | 1.028× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | 494,840 [494,840–494,840] → 494,840 [494,840–494,840] | 0 → 0 | 854,312 → 895,107 | 608575 → 650746 |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | 315,416 [315,416–315,416] → 315,416 [315,416–315,416] | 1,152 → 1,152 | 871,566 → 912,361 | 608575 → 650746 |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | 181,552 [181,552–181,552] → 181,552 [181,552–181,552] | 1,152 → 1,152 | 871,878 → 912,673 | 608575 → 650746 |
| bls12-381-verify-ethereum-official-direct | 39,280 [39,280–39,280] → 39,280 [39,280–39,280] | 0 → 0 | 848,194 → 888,989 | 608575 → 650746 |
| bls12-381-verify-ethereum-official-prepare | 200 [200–200] → 200 [200–200] | 144 → 144 | 850,316 → 891,111 | 608575 → 650746 |
| bls12-381-verify-ethereum-official-prepared | 39,280 [39,280–39,280] → 39,280 [39,280–39,280] | 144 → 144 | 850,687 → 891,482 | 608575 → 650746 |
| bls12-381-verify-ic-certificate-direct | 19,672 [19,672–19,672] → 19,672 [19,672–19,672] | 0 → 0 | 848,208 → 889,003 | 608575 → 650746 |
| bls12-381-verify-ic-certificate-prepare | 19,736 [19,736–19,736] → 19,736 [19,736–19,736] | 19,680 → 19,680 | 850,331 → 891,126 | 608575 → 650746 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 850,702 → 891,497 | 608575 → 650746 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
