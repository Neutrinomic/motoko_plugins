# Plugin revision comparison

Target: `ed25519`. Baseline: `prepared-round4-ed25519-c1-baseline`; candidate: `prepared-round4-ed25519-c2-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one factory, and cold includes one factory plus N calls. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| ed25519-sign-openssl-32-direct-1 | direct/1 | 1,803,963 [1,803,963–1,803,963] | 1,982,917 [1,982,917–1,982,917] | -9.92% | 0.910× |
| ed25519-sign-openssl-32-prepare-1 | prepare/1 | 887,929 [887,929–887,929] | 977,406 [977,406–977,406] | -10.08% | 0.908× |
| ed25519-sign-openssl-32-prepared-1 | prepared/1 | 907,801 [907,801–907,801] | 997,278 [997,278–997,278] | -9.86% | 0.910× |
| ed25519-verify-openssl-32-direct-1 | direct/1 | 2,308,542 [2,308,542–2,308,542] | 2,363,482 [2,363,482–2,363,482] | -2.38% | 0.977× |
| ed25519-verify-openssl-32-prepare-1 | prepare/1 | 266,520 [266,520–266,520] | 284,217 [284,217–284,217] | -6.64% | 0.938× |
| ed25519-verify-openssl-32-prepared-1 | prepared/1 | 2,071,444 [2,071,444–2,071,444] | 2,110,375 [2,110,375–2,110,375] | -1.88% | 0.982× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| ed25519-sign-openssl-32-direct-1 | 120 [120–120] → 120 [120–120] | 0 → 0 | 369,229 → 375,619 | 121439 → 127914 |
| ed25519-sign-openssl-32-prepare-1 | 152 [152–152] → 152 [152–152] | 96 → 96 | 369,457 → 375,847 | 121439 → 127914 |
| ed25519-sign-openssl-32-prepared-1 | 88 [88–88] → 88 [88–88] | 96 → 96 | 369,880 → 376,270 | 121439 → 127914 |
| ed25519-verify-openssl-32-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 369,464 → 375,854 | 121439 → 127914 |
| ed25519-verify-openssl-32-prepare-1 | 1,112 [1,112–1,112] → 1,112 [1,112–1,112] | 1,056 → 1,056 | 370,088 → 376,478 | 121439 → 127914 |
| ed25519-verify-openssl-32-prepared-1 | 32 [32–32] → 32 [32–32] | 1,056 → 1,056 | 370,738 → 377,128 | 121439 → 127914 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
