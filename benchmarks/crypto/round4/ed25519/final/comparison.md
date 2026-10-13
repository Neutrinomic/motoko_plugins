# Plugin revision comparison

Target: `ed25519`. Baseline: `prepared-round4-ed25519-final-baseline`; candidate: `prepared-round4-ed25519-final-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| ed25519-verify-openssl-1024-direct-1 | direct/1 | 2,379,349 [2,379,349–2,379,349] | 2,239,939 [2,239,939–2,239,939] | 5.86% | 1.062× |
| ed25519-verify-openssl-1024-prepared-1 | prepared/1 | 2,142,252 [2,142,252–2,142,252] | 2,004,464 [2,004,464–2,004,464] | 6.43% | 1.069× |
| ed25519-verify-openssl-32-direct-10 | direct/10 | 23,085,048 [23,085,048–23,085,048] | 21,691,008 [21,691,008–21,691,008] | 6.04% | 1.064× |
| ed25519-verify-openssl-32-prepared-10 | prepared/10 | 20,712,785 [20,712,785–20,712,785] | 19,334,975 [19,334,975–19,334,975] | 6.65% | 1.071× |
| ed25519-verify-rfc8032-1-direct-1 | direct/1 | 2,318,893 [2,318,893–2,318,893] | 2,179,487 [2,179,487–2,179,487] | 6.01% | 1.064× |
| ed25519-verify-rfc8032-1-prepared-1 | prepared/1 | 2,081,792 [2,081,792–2,081,792] | 1,944,012 [1,944,012–1,944,012] | 6.62% | 1.071× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| ed25519-verify-openssl-1024-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 370,459 → 369,417 | 121439 → 120398 |
| ed25519-verify-openssl-1024-prepared-1 | 32 [32–32] → 32 [32–32] | 1,056 → 1,056 | 371,733 → 370,691 | 121439 → 120398 |
| ed25519-verify-openssl-32-direct-10 | 320 [320–320] → 320 [320–320] | 0 → 0 | 369,517 → 368,475 | 121439 → 120398 |
| ed25519-verify-openssl-32-prepared-10 | 320 [320–320] → 320 [320–320] | 1,056 → 1,056 | 370,791 → 369,749 | 121439 → 120398 |
| ed25519-verify-rfc8032-1-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 369,343 → 368,301 | 121439 → 120398 |
| ed25519-verify-rfc8032-1-prepared-1 | 32 [32–32] → 32 [32–32] | 1,056 → 1,056 | 370,617 → 369,575 | 121439 → 120398 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
