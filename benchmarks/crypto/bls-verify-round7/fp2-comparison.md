# Plugin revision comparison

Target: `bls12-381`. Baseline: `prepared-bls7-screen-baseline`; candidate: `prepared-bls7-screen-fp2`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| bls12-381-verify-ic-certificate-direct | direct/1 | 127,630,963 [127,630,963–127,630,963] | 125,010,880 [125,010,880–125,010,880] | 2.05% | 1.021× |
| bls12-381-verify-ic-certificate-prepared | prepared/1 | 101,276,827 [101,276,827–101,276,827] | 99,524,479 [99,524,479–99,524,479] | 1.73% | 1.018× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| bls12-381-verify-ic-certificate-direct | 64 [64–64] → 64 [64–64] | 0 → 0 | 857,310 → 589,348 | 617967 → 349021 |
| bls12-381-verify-ic-certificate-prepared | 64 [64–64] → 64 [64–64] | 19,680 → 19,680 | 859,804 → 591,842 | 617967 → 349021 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
