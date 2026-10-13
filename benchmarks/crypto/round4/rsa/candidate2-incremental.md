# Plugin revision comparison

Target: `rsa`. Baseline: `prepared-round4-rsa-c1-candidate`; candidate: `prepared-round4-rsa-c2-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one factory, and cold includes one factory plus N calls. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| rsa3072-sign-prehash-openssl3072-direct-1 | direct/1 | 447,113,202 [447,113,202–447,113,202] | 400,505,033 [400,505,033–400,505,033] | 10.42% | 1.116× |
| rsa3072-sign-prehash-openssl3072-prepared-1 | prepared/1 | 443,187,190 [443,187,190–443,187,190] | 396,540,393 [396,540,393–396,540,393] | 10.53% | 1.118× |
| rsa3072-verify-prehash-openssl3072-direct-1 | direct/1 | 9,819,276 [9,819,276–9,819,276] | 9,162,600 [9,162,600–9,162,600] | 6.69% | 1.072× |
| rsa3072-verify-prehash-openssl3072-prepared-1 | prepared/1 | 8,418,188 [8,418,188–8,418,188] | 7,722,884 [7,722,884–7,722,884] | 8.26% | 1.090× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| rsa3072-sign-prehash-openssl3072-direct-1 | 440 [440–440] → 440 [440–440] | 0 → 0 | 278,823 → 279,760 | 30269 → 31212 |
| rsa3072-sign-prehash-openssl3072-prepared-1 | 440 [440–440] → 440 [440–440] | 1,840 → 1,840 | 280,219 → 281,156 | 30269 → 31212 |
| rsa3072-verify-prehash-openssl3072-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 278,780 → 279,717 | 30269 → 31212 |
| rsa3072-verify-prehash-openssl3072-prepared-1 | 32 [32–32] → 32 [32–32] | 824 → 824 | 280,176 → 281,113 | 30269 → 31212 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
