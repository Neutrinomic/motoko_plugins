# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-bls6-eth8-baseline`; candidate: `prepared-bls6-eth8-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | direct/1 | 3,175,970,967 [3,175,970,967–3,175,970,967] | 1,941,213,088 [1,941,213,088–1,941,213,088] | 38.88% | 1.636× |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | prepare/1 | 2,199,794,662 [2,199,794,662–2,199,794,662] | 1,340,358,670 [1,340,358,670–1,340,358,670] | 39.07% | 1.641× |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | prepared/1 | 976,180,848 [976,180,848–976,180,848] | 600,858,961 [600,858,961–600,858,961] | 38.45% | 1.625× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | 181,112 [181,112–181,112] → 181,112 [181,112–181,112] | 0 → 0 | 899,933 → 863,414 | 655629 → 617967 |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | 1,688 [1,688–1,688] → 1,688 [1,688–1,688] | 1,152 → 1,152 | 917,187 → 880,668 | 655629 → 617967 |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | 181,552 [181,552–181,552] → 181,552 [181,552–181,552] | 1,152 → 1,152 | 917,499 → 880,980 | 655629 → 617967 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
