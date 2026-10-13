# Plugin revision comparison

Target: `rsa`. Baseline: `prepared-round4-rsa-final-extra-baseline`; candidate: `prepared-round4-rsa-final-extra-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| rsa3072-sign-message-openssl3072-direct-1 | direct/1 | 447,485,855 [447,485,855–447,485,855] | 400,514,450 [400,514,450–400,514,450] | 10.50% | 1.117× |
| rsa3072-sign-message-openssl3072-prepared-1 | prepared/1 | 443,560,039 [443,560,039–443,560,039] | 396,549,810 [396,549,810–396,549,810] | 10.60% | 1.119× |
| rsa3072-sign-prehash-openssl3072-direct-10 | direct/10 | 4,474,763,608 [4,474,763,608–4,474,763,608] | 4,005,049,558 [4,005,049,558–4,005,049,558] | 10.50% | 1.117× |
| rsa3072-sign-prehash-openssl3072-prepare-1 | prepare/1 | 6,138,602 [6,138,602–6,138,602] | 6,138,602 [6,138,602–6,138,602] | 0.00% | 1.000× |
| rsa3072-sign-prehash-openssl3072-prepared-10 | prepared/10 | 4,435,505,448 [4,435,505,448–4,435,505,448] | 3,965,403,158 [3,965,403,158–3,965,403,158] | 10.60% | 1.119× |
| rsa3072-verify-message-openssl3072-direct-1 | direct/1 | 9,832,026 [9,832,026–9,832,026] | 9,172,018 [9,172,018–9,172,018] | 6.71% | 1.072× |
| rsa3072-verify-message-openssl3072-prepared-1 | prepared/1 | 8,431,134 [8,431,134–8,431,134] | 7,732,302 [7,732,302–7,732,302] | 8.29% | 1.090× |
| rsa3072-verify-prehash-openssl3072-direct-10 | direct/10 | 98,225,558 [98,225,558–98,225,558] | 91,625,478 [91,625,478–91,625,478] | 6.72% | 1.072× |
| rsa3072-verify-prehash-openssl3072-prepare-1 | prepare/1 | 3,642,309 [3,642,309–3,642,309] | 3,642,309 [3,642,309–3,642,309] | 0.00% | 1.000× |
| rsa3072-verify-prehash-openssl3072-prepared-10 | prepared/10 | 84,216,638 [84,216,638–84,216,638] | 77,228,318 [77,228,318–77,228,318] | 8.30% | 1.090× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| rsa3072-sign-message-openssl3072-direct-1 | 440 [440–440] → 440 [440–440] | 0 → 0 | 278,833 → 279,775 | 30264 → 31212 |
| rsa3072-sign-message-openssl3072-prepared-1 | 440 [440–440] → 440 [440–440] | 1,840 → 1,840 | 280,229 → 281,171 | 30264 → 31212 |
| rsa3072-sign-prehash-openssl3072-direct-10 | 4,400 [4,400–4,400] → 4,400 [4,400–4,400] | 0 → 0 | 278,867 → 279,809 | 30264 → 31212 |
| rsa3072-sign-prehash-openssl3072-prepare-1 | 1,896 [1,896–1,896] → 1,896 [1,896–1,896] | 1,840 → 1,840 | 280,074 → 281,016 | 30264 → 31212 |
| rsa3072-sign-prehash-openssl3072-prepared-10 | 4,400 [4,400–4,400] → 4,400 [4,400–4,400] | 1,840 → 1,840 | 280,263 → 281,205 | 30264 → 31212 |
| rsa3072-verify-message-openssl3072-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 278,790 → 279,732 | 30264 → 31212 |
| rsa3072-verify-message-openssl3072-prepared-1 | 32 [32–32] → 32 [32–32] | 824 → 824 | 280,186 → 281,128 | 30264 → 31212 |
| rsa3072-verify-prehash-openssl3072-direct-10 | 320 [320–320] → 320 [320–320] | 0 → 0 | 278,824 → 279,766 | 30264 → 31212 |
| rsa3072-verify-prehash-openssl3072-prepare-1 | 880 [880–880] → 880 [880–880] | 824 → 824 | 280,029 → 280,971 | 30264 → 31212 |
| rsa3072-verify-prehash-openssl3072-prepared-10 | 320 [320–320] → 320 [320–320] | 824 → 824 | 280,220 → 281,162 | 30264 → 31212 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
