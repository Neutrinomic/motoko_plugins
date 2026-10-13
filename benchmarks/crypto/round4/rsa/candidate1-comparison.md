# Plugin revision comparison

Target: `rsa`. Baseline: `prepared-round4-rsa-c1-baseline`; candidate: `prepared-round4-rsa-c1-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one factory, and cold includes one factory plus N calls. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| rsa3072-sign-prehash-openssl3072-direct-1 | direct/1 | 447,476,438 [447,476,438–447,476,438] | 447,113,202 [447,113,202–447,113,202] | 0.08% | 1.001× |
| rsa3072-sign-prehash-openssl3072-prepared-1 | prepared/1 | 443,550,622 [443,550,622–443,550,622] | 443,187,190 [443,187,190–443,187,190] | 0.08% | 1.001× |
| rsa3072-verify-prehash-openssl3072-direct-1 | direct/1 | 9,822,608 [9,822,608–9,822,608] | 9,819,276 [9,819,276–9,819,276] | 0.03% | 1.000× |
| rsa3072-verify-prehash-openssl3072-prepared-1 | prepared/1 | 8,421,716 [8,421,716–8,421,716] | 8,418,188 [8,418,188–8,418,188] | 0.04% | 1.000× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| rsa3072-sign-prehash-openssl3072-direct-1 | 440 [440–440] → 440 [440–440] | 0 → 0 | 278,818 → 278,823 | 30264 → 30269 |
| rsa3072-sign-prehash-openssl3072-prepared-1 | 440 [440–440] → 440 [440–440] | 1,840 → 1,840 | 280,214 → 280,219 | 30264 → 30269 |
| rsa3072-verify-prehash-openssl3072-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 278,775 → 278,780 | 30264 → 30269 |
| rsa3072-verify-prehash-openssl3072-prepared-1 | 32 [32–32] → 32 [32–32] | 824 → 824 | 280,171 → 280,176 | 30264 → 30269 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
