# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-round4-bls12-381-c1-candidate`; candidate: `prepared-round4-bls12-381-c2-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | direct/1 | 3,189,323,677 [3,189,323,677–3,189,323,677] | 3,176,407,705 [3,176,407,705–3,176,407,705] | 0.40% | 1.004× |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | prepare/1 | 2,211,702,686 [2,211,702,686–2,211,702,686] | 2,200,221,822 [2,200,221,822–2,200,221,822] | 0.52% | 1.005× |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | prepared/1 | 977,625,534 [977,625,534–977,625,534] | 976,190,426 [976,190,426–976,190,426] | 0.15% | 1.001× |
| bls12-381-verify-ethereum-official-direct | direct/1 | 276,462,870 [276,462,870–276,462,870] | 275,027,762 [275,027,762–275,027,762] | 0.52% | 1.005× |
| bls12-381-verify-ethereum-official-prepare | prepare/1 | 11,144,375 [11,144,375–11,144,375] | 11,144,375 [11,144,375–11,144,375] | 0.00% | 1.000× |
| bls12-381-verify-ethereum-official-prepared | prepared/1 | 265,319,657 [265,319,657–265,319,657] | 263,884,549 [263,884,549–263,884,549] | 0.54% | 1.005× |
| bls12-381-verify-ic-certificate-direct | direct/1 | 212,129,661 [212,129,661–212,129,661] | 210,694,553 [210,694,553–210,694,553] | 0.68% | 1.007× |
| bls12-381-verify-ic-certificate-prepare | prepare/1 | 43,312,942 [43,312,942–43,312,942] | 43,312,942 [43,312,942–43,312,942] | 0.00% | 1.000× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 168,858,340 [168,858,340–168,858,340] | 167,423,232 [167,423,232–167,423,232] | 0.85% | 1.009× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-aggregate-ethereum-distinct-n8-direct | 494,840 [494,840–494,840] → 494,840 [494,840–494,840] | 0 → 0 | 929,444 → 895,107 | 685243 → 650746 |
| bls12-381-aggregate-ethereum-distinct-n8-prepare | 315,416 [315,416–315,416] → 315,416 [315,416–315,416] | 1,152 → 1,152 | 946,698 → 912,361 | 685243 → 650746 |
| bls12-381-aggregate-ethereum-distinct-n8-prepared | 181,552 [181,552–181,552] → 181,552 [181,552–181,552] | 1,152 → 1,152 | 947,010 → 912,673 | 685243 → 650746 |
| bls12-381-verify-ethereum-official-direct | 39,280 [39,280–39,280] → 39,280 [39,280–39,280] | 0 → 0 | 923,326 → 888,989 | 685243 → 650746 |
| bls12-381-verify-ethereum-official-prepare | 200 [200–200] → 200 [200–200] | 144 → 144 | 925,448 → 891,111 | 685243 → 650746 |
| bls12-381-verify-ethereum-official-prepared | 39,280 [39,280–39,280] → 39,280 [39,280–39,280] | 144 → 144 | 925,819 → 891,482 | 685243 → 650746 |
| bls12-381-verify-ic-certificate-direct | 19,672 [19,672–19,672] → 19,672 [19,672–19,672] | 0 → 0 | 923,340 → 889,003 | 685243 → 650746 |
| bls12-381-verify-ic-certificate-prepare | 19,736 [19,736–19,736] → 19,736 [19,736–19,736] | 19,680 → 19,680 | 925,463 → 891,126 | 685243 → 650746 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 925,834 → 891,497 | 685243 → 650746 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
