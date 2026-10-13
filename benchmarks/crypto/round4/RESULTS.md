# Signature optimization round four

Selected implementations: Ed25519 C1, Secp256k1 C3, P256 C5, RSA C2, ML-DSA C2 and BLS C3. Baseline is the previously delivered plugin revision `0e1e96a`, including its prepared-key and direct-path optimizations. The SDK is unchanged: `9f6ebeedc547e389a0529b4c91442e46b88fcbe0`, actual compiler ELF SHA-256 `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`, with its original RTS and ABI 1.

All **111 matched workloads / 666 fresh-canister observations** passed exact-output checks. All six independent scheme audits and the combined integration gates pass.

## Direct-call gains

Instruction medians from three fresh canisters per side, matched actors, fixtures, exact expected output, compiler/RTS, runner and locked dependencies. Comparisons use the selected plugin against the delivered plugin, not an earlier candidate or a library baseline. Positive reductions mean fewer instructions.

| Direct operation / fixture | Delivered | Selected | Fewer instructions |
|---|---:|---:|---:|
| Ed25519 sign / 32-byte message | 1,803,963 | 1,803,963 | 0.00% |
| Ed25519 verify / same message | 2,308,542 | 2,169,138 | 6.04% |
| Secp256k1 ECDSA sign / digest | 3,618,719 | 2,295,959 | 36.55% |
| Secp256k1 ECDSA verify / digest | 2,618,931 | 2,454,026 | 6.30% |
| Secp256k1 BIP340 sign / vector 0 | 5,099,447 | 2,681,364 | 47.42% |
| Secp256k1 BIP340 verify / vector 0 | 2,413,083 | 2,413,617 | -0.02% |
| P256 ECDSA sign / digest | 7,252,878 | 4,791,659 | 33.93% |
| P256 ECDSA verify / digest | 12,541,922 | 11,961,908 | 4.62% |
| RSA-3072 PSS sign / digest + salt32 | 447,476,438 | 400,505,033 | 10.50% |
| RSA-3072 PSS verify / same digest | 9,822,608 | 9,162,600 | 6.72% |
| ML-DSA-44 sign / ACVP 4 | 13,193,656 | 13,039,211 | 1.17% |
| ML-DSA-44 verify / ACVP 4 | 3,810,844 | 3,656,399 | 4.05% |
| BLS IC single verify | 222,072,725 | 210,673,356 | 5.13% |
| BLS Ethereum single verify | 286,405,944 | 274,974,367 | 3.99% |
| BLS Ethereum aggregate / 8 distinct keys | 3,285,303,573 | 3,175,970,967 | 3.33% |

Additional public-key controls improve **48.02%** for Secp256k1 (2,517,895 → 1,308,861), **33.99%** for P256 (4,996,581 → 3,297,998), and **3.02%** for ML-DSA ACVP 4 (5,107,151 → 4,952,706). Full matrices retain other inputs and modes.

## Current direct, setup and prepared costs

| Operation / input | Direct instructions | Preparation instructions | Prepared instructions | Payload B | Allocated B: direct / preparation / prepared |
|---|---:|---:|---:|---:|---:|
| Ed25519 sign / 32-byte message | 1,803,963 | 887,929 | 907,801 | 96 | 120 / 152 / 88 |
| Ed25519 verify / same message | 2,169,138 | 266,515 | 1,933,663 | 1,056 | 32 / 1,112 / 32 |
| Secp256k1 ECDSA sign / digest | 2,295,959 | — | — | — | 120 / — / — |
| Secp256k1 ECDSA verify / digest | 2,454,026 | 484,693 | 2,202,476 | 512 | 32 / 568 / 32 |
| Secp256k1 BIP340 sign / vector 0 | 2,681,364 | 1,308,308 | 1,375,272 | 64 | 120 / 120 / 120 |
| Secp256k1 BIP340 verify / vector 0 | 2,413,617 | 485,205 | 2,161,731 | 512 | 32 / 568 / 32 |
| P256 ECDSA sign / digest | 4,791,659 | — | — | — | 120 / — / — |
| P256 ECDSA verify / digest | 11,961,908 | 19,688,627 | 3,223,424 | 16,320 | 32 / 16,376 / 32 |
| RSA-3072 PSS sign / digest + salt32 | 400,505,033 | 6,138,602 | 396,540,393 | 1,840 | 440 / 1,896 / 440 |
| RSA-3072 PSS verify / same digest | 9,162,600 | 3,642,309 | 7,722,884 | 824 | 32 / 880 / 32 |
| ML-DSA-44 sign / ACVP 4 | 13,039,211 | 4,862,444 | 8,890,133 | 28,800 | 2,480 / 28,856 / 2,480 |
| ML-DSA-44 verify / ACVP 4 | 3,656,399 | 2,371,114 | 1,787,636 | 20,576 | 32 / 20,632 / 32 |
| BLS IC single verify | 210,673,356 | 43,312,942 | 167,427,790 | 19,680 | 64 / 19,736 / 64 |
| BLS Ethereum single verify | 274,974,367 | 11,144,375 | 263,831,154 | 144 | 64 / 200 / 64 |
| BLS Ethereum aggregate / 8 distinct keys | 3,175,970,967 | 2,199,794,662 | 976,180,848 | 1,152 | 181,112 / 1,688 / 181,552 |

Direct and hot columns measure one complete public operation. Preparation includes all required factories (eight PoP-checked keys for the BLS distinct-eight row), validation and result construction; hot calls exclude setup. Payload is the unchanged prepared layout without object headers, not total allocation. The ECDSA sign controls are newly reported existing direct APIs; no prepared ECDSA signer was measured. Digest operations exclude message hashing. ML-DSA ACVP 4 is a one-byte message with 59-byte context; across all four measured fixtures, direct signing improves 0.59–1.76% and prepared signing 0.85–4.01%. Ed25519 direct signing returns Result and prepared signing Blob.

## Actual reuse, including setup

These whole-batch observations use the selected artifact. Cold includes one factory and N calls in the timed interval. They are not modeled `P + N × H` totals; batches can differ from multiplying single-call counters. No new ML-DSA cold-batch measurements are claimed.

| Operation | Calls | Direct instructions | Preparation + calls | Allocated B: direct / cold |
|---|---:|---:|---:|---:|
| P256 ECDSA verify | 1 | 11,961,908 | 22,911,851 | 32 / 16,408 |
| P256 ECDSA verify | 10 | 119,616,848 | 51,919,769 | 320 / 16,696 |
| P256 ECDSA verify | 100 | 1,196,166,248 | 341,998,949 | 3,200 / 19,576 |
| Secp256k1 ECDSA verify | 10 | 24,539,878 | 22,508,855 | 320 / 888 |
| Secp256k1 Schnorr verify | 10 | 24,135,788 | 22,101,917 | 320 / 888 |
| Secp256k1 Schnorr sign | 10 | 26,812,948 | 15,060,120 | 1,200 / 1,320 |

Ed25519 and RSA also have actual ten-call direct/prepared batches excluding setup, retained in their detailed reports. Any break-even calculation from single-call setup/hot medians remains a model, separate from these observations.

## Allocation and code size

All prepared payloads remain unchanged. Non-BLS managed allocation is unchanged in matched rows. BLS reduces temporary heap allocation, including **19,672 → 64 B** for IC single direct verification, **39,280 → 64 B** for Ethereum single direct verification, **315,416 → 1,688 B** for eight-key proof-of-possession preparation, and **494,840 → 181,112 B** for direct verification of that aggregate. Its prepared aggregate still allocates **181,552 B**. Lower allocation does not imply lower code size:

| Plugin | Baseline runtime Wasm B | Selected runtime Wasm B | Runtime delta B | Linked benchmark canister delta B |
|---|---:|---:|---:|---:|
| Ed25519 | 121,439 | 120,398 | −1,041 | −1,042 |
| Secp256k1 | 154,876 | 180,910 | +26,034 | +25,896 |
| P256 | 125,436 | 140,006 | +14,570 | +14,425 |
| RSA | 30,264 | 31,212 | +948 | +942 |
| ML-DSA | 123,026 | 123,611 | +585 | +621 |
| BLS12-381 | 608,575 | 655,629 | +47,054 | +45,621 |

The linked-size deltas above are from the principal matched cohort for each scheme; raw manifests retain absolute sizes for every actor. Static arithmetic tables contribute to code/data size even when timed managed allocation is unchanged. Runtime Wasm size is measured before linking. Raw before/after/after-GC heap and capacity snapshots are neither peak memory nor retained live bytes. Existing [prepared-key lifecycle evidence](../prepared/RESULTS.md#memory-and-lifetime) concerns unchanged representations; this round makes no new universal retained-memory claim.

## Reused pure Motoko controls

These are the preceding run's [two `ecdsa@8.0.1` controls](../prepared/library-controls/README.md), **not fresh round-four measurements**. Compiler ELF `24d8d0b9…` and exact input bytes match the current verification rows. Their six observations are not counted in round four's totals.

| Verification | Reused pure Motoko instructions | Current direct / prepared | Motoko instruction ratio: direct / prepared | Allocated B: Motoko / direct / prepared |
|---|---:|---:|---:|---:|
| Secp256k1 ECDSA | 137,009,273 | 2,454,026 / 2,202,476 | **55.83× / 62.21×** | 10,903,256 / 32 / 32 |
| P256 ECDSA | 323,983,718 | 11,961,908 / 3,223,424 | **27.08× / 100.51×** | 23,927,448 / 32 / 32 |

Prepared ratios exclude setup. Byte parsing/validation are timed; curve construction is reused outside timing. P256's library internally normalizes the high-S signature. Comparisons cover these valid inputs, not identical malformed-input behavior. Algorithms and security profiles differ; ratios compare whole implementations, not isolated plugin-boundary overhead.

## Retained tradeoffs and evidence

- **Secp256k1:** the final square specialization saves another 113,666 instructions per ECDSA signature versus C2, while adding 712 per ECDSA verification, 534 per Schnorr verification and 89 per Schnorr signature, for both direct/hot controls. Compared with the delivered baseline, Schnorr verification is still +534 instructions (about 0.02%); the other headline operations improve.
- **BLS:** final C3 IC prepared verification is **4,558 instructions slower than C2**, although still 4,693,725 fewer than the delivered baseline. C3 improves IC direct verification and the measured Ethereum paths; both stages remain in evidence.
- **Ed25519:** the Fiat32 backend experiment was rejected: signing, verification and runtime size all regressed. The selected serial32 implementation remains C1.
- **Scope:** official vectors, negative fixtures, arithmetic comparisons, emitted-code checks and independent internal reviews provide correctness evidence; they are not security guarantees or an external cryptographic audit. No SDK, prepared-layout or ownership redesign is part of this round.

Final paired coverage uses only the selected cohorts below. Another **297 observations** retain intermediate and rejected candidates, giving **963 observations across 35 stages** in the complete archive; they do not inflate the 111-workload / 666-observation final total.

| Scheme | Selected matched workloads | Fresh observations, both revisions | Baseline / selected raw cohorts |
|---|---:|---:|---|
| Ed25519 | 12 | 72 | [C1 baseline](results/prepared-round4-ed25519-c1-baseline/results.json) / [C1](results/prepared-round4-ed25519-c1-candidate/results.json); [extra baseline](results/prepared-round4-ed25519-final-baseline/results.json) / [extra selected](results/prepared-round4-ed25519-final-candidate/results.json) |
| Secp256k1 | 17 | 102 | [baseline](results/prepared-round4-secp256k1-c1-baseline/results.json) / [C3](results/prepared-round4-secp256k1-c3-candidate/results.json); [extra baseline](results/prepared-round4-secp256k1-extra-baseline/results.json) / [extra selected](results/prepared-round4-secp256k1-extra-final/results.json) |
| P256 | 28 | 168 | [final baseline](results/prepared-round4-p256-final-baseline/results.json) / [final C5](results/prepared-round4-p256-final-candidate/results.json) |
| RSA | 14 | 84 | [baseline](results/prepared-round4-rsa-c1-baseline/results.json) / [C2](results/prepared-round4-rsa-c2-candidate/results.json); [extra baseline](results/prepared-round4-rsa-final-extra-baseline/results.json) / [extra selected](results/prepared-round4-rsa-final-extra-candidate/results.json) |
| ML-DSA | 25 | 150 | [baseline](results/prepared-round4-mldsa-c1-baseline/results.json) / [C2](results/prepared-round4-mldsa-c2-candidate/results.json); [extra baseline](results/prepared-round4-mldsa-finalextra-baseline/results.json) / [extra selected](results/prepared-round4-mldsa-finalextra-candidate/results.json) |
| BLS | 15 | 90 | [baseline](results/prepared-round4-bls12-381-c1-baseline/results.json) / [C3](results/prepared-round4-bls12-381-c3-candidate/results.json); [extra baseline](results/prepared-round4-bls12-381-final-extra-baseline/results.json) / [extra selected](results/prepared-round4-bls12-381-final-extra-candidate/results.json) |

[Protocol and reproduction](README.md); detailed reports: [Ed25519](ed25519/README.md), [Secp256k1](secp256k1/README.md), [P256](p256/README.md), [RSA](rsa/README.md), [ML-DSA](ml-dsa/README.md), [BLS](bls12-381/README.md). Independent reviews are under [`tests/crypto-audit/round4`](../../../tests/crypto-audit/round4/). Frozen baseline/candidate sources and manifests remain beside the raw evidence. The [prepared-key archive](../prepared/RESULTS.md) and [round-three archive](../round3/RESULTS.md) remain unchanged.

The [archive inventory](archive-inventory.json) records 35 stages and 1,304 deduplicated source contents. The [source store](source-store.tar.gz) and [index](source-store.json) pass [integrity verification](evidence-integrity.json) and [portable restore verification](evidence-integrity-portable.json). The [combined validation report](../../../tests/integration/round4-validation/integration.json) records all 23 plugin builds with audited-runtime parity, packaging, two composition fixtures across all engines, eight negative replays and one combined Ash GC test with both >4 MiB reclamation assertions passing.
