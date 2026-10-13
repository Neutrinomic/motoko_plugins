# Plugin revision comparison

Target: `p256`. Baseline: `prepared-round4-p256-final-baseline`; candidate: `prepared-round4-p256-final-candidate`.

Three fresh canisters per case and revision; values are median [min–max]. Positive savings mean fewer instructions. Every row measures the whole timed interval: direct/prepared batches contain N calls, prepare measures one preparation interval, and cold includes preparation plus N calls. Preparation intervals may construct multiple keys, as recorded in workload metadata. No modeled costs or per-call division are used.

| Case | Mode/reuse | Baseline instructions | Candidate instructions | Saving | Speedup |
|---|---|---:|---:|---:|---:|
| p256-r4-convert-compressed-to-uncompressed | control/1 | 581,934 [581,934–581,934] | 581,887 [581,887–581,887] | 0.01% | 1.000× |
| p256-r4-derivePublicKey-high-bit-order-plus-one | control/1 | 4,996,581 [4,996,581–4,996,581] | 3,297,998 [3,297,998–3,297,998] | 33.99% | 1.515× |
| p256-r4-derivePublicKey-rfc6979-sample | control/1 | 4,996,581 [4,996,581–4,996,581] | 3,297,998 [3,297,998–3,297,998] | 33.99% | 1.515× |
| p256-r4-rare-n-plus-3-direct-1 | direct/1 | 9,617,368 [9,617,368–9,617,368] | 9,041,875 [9,041,875–9,041,875] | 5.98% | 1.064× |
| p256-r4-rare-n-plus-3-prepare-1 | prepare/1 | 19,688,675 [19,688,675–19,688,675] | 19,688,627 [19,688,627–19,688,627] | 0.00% | 1.000× |
| p256-r4-rare-n-plus-3-prepared-1 | prepared/1 | 1,754,864 [1,754,864–1,754,864] | 1,179,938 [1,179,938–1,179,938] | 32.76% | 1.487× |
| p256-r4-reject-field-wrap-direct-1 | direct/1 | 10,402,972 [10,402,972–10,402,972] | 9,825,272 [9,825,272–9,825,272] | 5.55% | 1.059× |
| p256-r4-reject-field-wrap-prepare-1 | prepare/1 | 19,688,675 [19,688,675–19,688,675] | 19,688,627 [19,688,627–19,688,627] | 0.00% | 1.000× |
| p256-r4-reject-field-wrap-prepared-1 | prepared/1 | 2,642,968 [2,642,968–2,642,968] | 2,065,835 [2,065,835–2,065,835] | 21.84% | 1.279× |
| p256-r4-rfc-low-s-direct-1 | direct/1 | 12,407,046 [12,407,046–12,407,046] | 11,827,032 [11,827,032–11,827,032] | 4.67% | 1.049× |
| p256-r4-rfc-low-s-prepare-1 | prepare/1 | 19,688,675 [19,688,675–19,688,675] | 19,688,627 [19,688,627–19,688,627] | 0.00% | 1.000× |
| p256-r4-rfc-low-s-prepared-1 | prepared/1 | 3,766,970 [3,766,970–3,766,970] | 3,187,523 [3,187,523–3,187,523] | 15.38% | 1.182× |
| p256-r4-rfc-sample-cold-1 | cold/1 | 23,491,346 [23,491,346–23,491,346] | 22,911,851 [22,911,851–22,911,851] | 2.47% | 1.025× |
| p256-r4-rfc-sample-cold-10 | cold/10 | 57,714,287 [57,714,287–57,714,287] | 51,919,769 [51,919,769–51,919,769] | 10.04% | 1.112× |
| p256-r4-rfc-sample-cold-100 | cold/100 | 399,943,697 [399,943,697–399,943,697] | 341,998,949 [341,998,949–341,998,949] | 14.49% | 1.169× |
| p256-r4-rfc-sample-direct-1 | direct/1 | 12,541,922 [12,541,922–12,541,922] | 11,961,908 [11,961,908–11,961,908] | 4.62% | 1.048× |
| p256-r4-rfc-sample-direct-10 | direct/10 | 125,416,988 [125,416,988–125,416,988] | 119,616,848 [119,616,848–119,616,848] | 4.62% | 1.048× |
| p256-r4-rfc-sample-direct-100 | direct/100 | 1,254,167,648 [1,254,167,648–1,254,167,648] | 1,196,166,248 [1,196,166,248–1,196,166,248] | 4.62% | 1.048× |
| p256-r4-rfc-sample-prepare-1 | prepare/1 | 19,688,675 [19,688,675–19,688,675] | 19,688,627 [19,688,627–19,688,627] | 0.00% | 1.000× |
| p256-r4-rfc-sample-prepared-1 | prepared/1 | 3,802,871 [3,802,871–3,802,871] | 3,223,424 [3,223,424–3,223,424] | 15.24% | 1.180× |
| p256-r4-rfc-sample-prepared-10 | prepared/10 | 38,025,812 [38,025,812–38,025,812] | 32,231,342 [32,231,342–32,231,342] | 15.24% | 1.180× |
| p256-r4-rfc-sample-prepared-100 | prepared/100 | 380,255,222 [380,255,222–380,255,222] | 322,310,522 [322,310,522–322,310,522] | 15.24% | 1.180× |
| p256-r4-rfc-wrong-digest-direct-1 | direct/1 | 11,201,185 [11,201,185–11,201,185] | 10,621,239 [10,621,239–10,621,239] | 5.18% | 1.055× |
| p256-r4-rfc-wrong-digest-prepare-1 | prepare/1 | 19,688,675 [19,688,675–19,688,675] | 19,688,627 [19,688,627–19,688,627] | 0.00% | 1.000× |
| p256-r4-rfc-wrong-digest-prepared-1 | prepared/1 | 2,787,831 [2,787,831–2,787,831] | 2,208,452 [2,208,452–2,208,452] | 20.78% | 1.262× |
| p256-r4-signPrehash-one-order | control/1 | 7,252,878 [7,252,878–7,252,878] | 4,791,659 [4,791,659–4,791,659] | 33.93% | 1.514× |
| p256-r4-signPrehash-order-minus-one-max | control/1 | 7,252,878 [7,252,878–7,252,878] | 4,791,659 [4,791,659–4,791,659] | 33.93% | 1.514× |
| p256-r4-signPrehash-rfc6979-sample | control/1 | 7,252,878 [7,252,878–7,252,878] | 4,791,659 [4,791,659–4,791,659] | 33.93% | 1.514× |

Bytes below show baseline → candidate. Prepared payload is declared layout size, distinct from timed allocation. Canister Wasm is the compiled actor; runtime Wasm is the selected plugin artifact before linking.

| Case | Allocated bytes | Prepared payload | Canister Wasm | Target runtime Wasm |
|---|---:|---:|---:|---:|
| p256-r4-convert-compressed-to-uncompressed | 128 [128–128] → 128 [128–128] | 0 → 0 | 371,436 → 385,861 | 125436 → 140006 |
| p256-r4-derivePublicKey-high-bit-order-plus-one | 96 [96–96] → 96 [96–96] | 0 → 0 | 371,451 → 385,876 | 125436 → 140006 |
| p256-r4-derivePublicKey-rfc6979-sample | 96 [96–96] → 96 [96–96] | 0 → 0 | 371,451 → 385,876 | 125436 → 140006 |
| p256-r4-rare-n-plus-3-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 371,840 → 386,265 | 125436 → 140006 |
| p256-r4-rare-n-plus-3-prepare-1 | 16,376 [16,376–16,376] → 16,376 [16,376–16,376] | 16,320 → 16,320 | 373,388 → 387,813 | 125436 → 140006 |
| p256-r4-rare-n-plus-3-prepared-1 | 32 [32–32] → 32 [32–32] | 16,320 → 16,320 | 373,581 → 388,006 | 125436 → 140006 |
| p256-r4-reject-field-wrap-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 371,838 → 386,263 | 125436 → 140006 |
| p256-r4-reject-field-wrap-prepare-1 | 16,376 [16,376–16,376] → 16,376 [16,376–16,376] | 16,320 → 16,320 | 373,386 → 387,811 | 125436 → 140006 |
| p256-r4-reject-field-wrap-prepared-1 | 32 [32–32] → 32 [32–32] | 16,320 → 16,320 | 373,579 → 388,004 | 125436 → 140006 |
| p256-r4-rfc-low-s-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 371,840 → 386,265 | 125436 → 140006 |
| p256-r4-rfc-low-s-prepare-1 | 16,376 [16,376–16,376] → 16,376 [16,376–16,376] | 16,320 → 16,320 | 373,388 → 387,813 | 125436 → 140006 |
| p256-r4-rfc-low-s-prepared-1 | 32 [32–32] → 32 [32–32] | 16,320 → 16,320 | 373,581 → 388,006 | 125436 → 140006 |
| p256-r4-rfc-sample-cold-1 | 16,408 [16,408–16,408] → 16,408 [16,408–16,408] | 16,320 → 16,320 | 373,581 → 388,006 | 125436 → 140006 |
| p256-r4-rfc-sample-cold-10 | 16,696 [16,696–16,696] → 16,696 [16,696–16,696] | 16,320 → 16,320 | 373,581 → 388,006 | 125436 → 140006 |
| p256-r4-rfc-sample-cold-100 | 19,576 [19,576–19,576] → 19,576 [19,576–19,576] | 16,320 → 16,320 | 373,582 → 388,007 | 125436 → 140006 |
| p256-r4-rfc-sample-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 371,840 → 386,265 | 125436 → 140006 |
| p256-r4-rfc-sample-direct-10 | 320 [320–320] → 320 [320–320] | 0 → 0 | 371,840 → 386,265 | 125436 → 140006 |
| p256-r4-rfc-sample-direct-100 | 3,200 [3,200–3,200] → 3,200 [3,200–3,200] | 0 → 0 | 371,841 → 386,266 | 125436 → 140006 |
| p256-r4-rfc-sample-prepare-1 | 16,376 [16,376–16,376] → 16,376 [16,376–16,376] | 16,320 → 16,320 | 373,388 → 387,813 | 125436 → 140006 |
| p256-r4-rfc-sample-prepared-1 | 32 [32–32] → 32 [32–32] | 16,320 → 16,320 | 373,581 → 388,006 | 125436 → 140006 |
| p256-r4-rfc-sample-prepared-10 | 320 [320–320] → 320 [320–320] | 16,320 → 16,320 | 373,581 → 388,006 | 125436 → 140006 |
| p256-r4-rfc-sample-prepared-100 | 3,200 [3,200–3,200] → 3,200 [3,200–3,200] | 16,320 → 16,320 | 373,582 → 388,007 | 125436 → 140006 |
| p256-r4-rfc-wrong-digest-direct-1 | 32 [32–32] → 32 [32–32] | 0 → 0 | 371,838 → 386,263 | 125436 → 140006 |
| p256-r4-rfc-wrong-digest-prepare-1 | 16,376 [16,376–16,376] → 16,376 [16,376–16,376] | 16,320 → 16,320 | 373,386 → 387,811 | 125436 → 140006 |
| p256-r4-rfc-wrong-digest-prepared-1 | 32 [32–32] → 32 [32–32] | 16,320 → 16,320 | 373,579 → 388,004 | 125436 → 140006 |
| p256-r4-signPrehash-one-order | 120 [120–120] → 120 [120–120] | 0 → 0 | 371,558 → 385,983 | 125436 → 140006 |
| p256-r4-signPrehash-order-minus-one-max | 120 [120–120] → 120 [120–120] | 0 → 0 | 371,558 → 385,983 | 125436 → 140006 |
| p256-r4-signPrehash-rfc6979-sample | 120 [120–120] → 120 [120–120] | 0 → 0 | 371,558 → 385,983 | 125436 → 140006 |

JSON retains artifact/source pins, exact oracle and workload metadata, shared environment, compiler flags, all three memory snapshots, and reclaimed counters. Sampled occupancy and capacity are neither peak memory nor retained live data.
