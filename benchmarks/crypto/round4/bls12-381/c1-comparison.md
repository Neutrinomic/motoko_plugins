# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-round4-bls12-381-c1-baseline`; candidate: `prepared-round4-bls12-381-c1-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | direct/1 | 3,285,303,573 [3,285,303,573–3,285,303,573] | 3,189,323,677 [3,189,323,677–3,189,323,677] | 2.92% | 1.030× |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | prepare/1 | 2,291,247,278 [2,291,247,278–2,291,247,278] | 2,211,702,686 [2,211,702,686–2,211,702,686] | 3.47% | 1.036× |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | prepared/1 | 994,060,838 [994,060,838–994,060,838] | 977,625,534 [977,625,534–977,625,534] | 1.65% | 1.017× |
| bls12-381-verify-ethereum-official-direct | direct/1 | 286,405,944 [286,405,944–286,405,944] | 276,462,870 [276,462,870–276,462,870] | 3.47% | 1.036× |
| bls12-381-verify-ethereum-official-prepare | prepare/1 | 12,239,690 [12,239,690–12,239,690] | 11,144,375 [11,144,375–11,144,375] | 8.95% | 1.098× |
| bls12-381-verify-ethereum-official-prepared | prepared/1 | 274,167,416 [274,167,416–274,167,416] | 265,319,657 [265,319,657–265,319,657] | 3.23% | 1.033× |
| bls12-381-verify-ic-certificate-direct | direct/1 | 222,072,725 [222,072,725–222,072,725] | 212,129,661 [212,129,661–212,129,661] | 4.48% | 1.047× |
| bls12-381-verify-ic-certificate-prepare | prepare/1 | 49,992,831 [49,992,831–49,992,831] | 43,312,942 [43,312,942–43,312,942] | 13.36% | 1.154× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 172,121,515 [172,121,515–172,121,515] | 168,858,340 [168,858,340–168,858,340] | 1.90% | 1.019× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | 494,840 [494,840–494,840] → 494,840 [494,840–494,840] | 0 → 0 | 854,312 → 929,444 | 608575 → 685243 |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | 315,416 [315,416–315,416] → 315,416 [315,416–315,416] | 1,152 → 1,152 | 871,566 → 946,698 | 608575 → 685243 |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | 181,552 [181,552–181,552] → 181,552 [181,552–181,552] | 1,152 → 1,152 | 871,878 → 947,010 | 608575 → 685243 |
| bls12-381-verify-ethereum-official-direct | 39,280 [39,280–39,280] → 39,280 [39,280–39,280] | 0 → 0 | 848,194 → 923,326 | 608575 → 685243 |
| bls12-381-verify-ethereum-official-prepare | 200 [200–200] → 200 [200–200] | 144 → 144 | 850,316 → 925,448 | 608575 → 685243 |
| bls12-381-verify-ethereum-official-prepared | 39,280 [39,280–39,280] → 39,280 [39,280–39,280] | 144 → 144 | 850,687 → 925,819 | 608575 → 685243 |
| bls12-381-verify-ic-certificate-direct | 19,672 [19,672–19,672] → 19,672 [19,672–19,672] | 0 → 0 | 848,208 → 923,340 | 608575 → 685243 |
| bls12-381-verify-ic-certificate-prepare | 19,736 [19,736–19,736] → 19,736 [19,736–19,736] | 19,680 → 19,680 | 850,331 → 925,463 | 608575 → 685243 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 850,702 → 925,834 | 608575 → 685243 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
