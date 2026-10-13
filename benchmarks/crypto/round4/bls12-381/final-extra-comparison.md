# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-round4-bls12-381-final-extra-baseline`; candidate: `prepared-round4-bls12-381-final-extra-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-repeated-n8-direct | direct/1 | 565,078,557 [565,078,557–565,078,557] | 542,281,614 [542,281,614–542,281,614] | 4.03% | 1.042× |
| bls12-381-aggregate-ethereum-repeated-n8-prepared | prepared/1 | 278,645,699 [278,645,699–278,645,699] | 267,280,333 [267,280,333–267,280,333] | 4.08% | 1.043× |
| bls12-381-aggregate-ic-distinct-n2-direct | direct/1 | 310,532,835 [310,532,835–310,532,835] | 291,392,273 [291,392,273–291,392,273] | 6.16% | 1.066× |
| bls12-381-aggregate-ic-distinct-n2-prepared | prepared/1 | 210,626,139 [210,626,139–210,626,139] | 204,848,489 [204,848,489–204,848,489] | 2.74% | 1.028× |
| bls12-381-fast-aggregate-ethereum-distinct-n2-direct | direct/1 | 850,994,532 [850,994,532–850,994,532] | 816,711,191 [816,711,191–816,711,191] | 4.03% | 1.042× |
| bls12-381-fast-aggregate-ethereum-distinct-n2-prepared | prepared/1 | 278,183,952 [278,183,952–278,183,952] | 266,763,765 [266,763,765–266,763,765] | 4.11% | 1.043× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-repeated-n8-direct | 82,680 [82,680–82,680] → 43,464 [43,464–43,464] | 0 → 0 | 851,197 → 896,818 | 608575 → 655629 |
| bls12-381-aggregate-ethereum-repeated-n8-prepared | 43,904 [43,904–43,904] → 43,904 [43,904–43,904] | 144 → 144 | 853,269 → 898,890 | 608575 → 655629 |
| bls12-381-aggregate-ic-distinct-n2-direct | 40,552 [40,552–40,552] → 40,552 [40,552–40,552] | 0 → 0 | 850,664 → 896,285 | 608575 → 655629 |
| bls12-381-aggregate-ic-distinct-n2-prepared | 544 [544–544] → 544 [544–544] | 39,360 → 39,360 | 854,709 → 900,330 | 608575 → 655629 |
| bls12-381-fast-aggregate-ethereum-distinct-n2-direct | 118,064 [118,064–118,064] → 416 [416–416] | 0 → 0 | 850,942 → 896,563 | 608575 → 655629 |
| bls12-381-fast-aggregate-ethereum-distinct-n2-prepared | 39,840 [39,840–39,840] → 624 [624–624] | 288 → 288 | 854,985 → 900,606 | 608575 → 655629 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
