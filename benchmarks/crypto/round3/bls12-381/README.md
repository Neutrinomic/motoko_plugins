# Fused BLS aggregate verification

Validated candidate: `fa74cad5cb259f869e23dcfb12b0c828c7e7410b` (production), with independent audit `d3b0893`. All **102 PocketIC trials passed**: 17 workloads, baseline and candidate, three fresh canisters each. [Complete comparison](comparison.json).

| Operation | Before instructions | After instructions | Reduction | Allocated bytes, before → after |
|---|---:|---:|---:|---:|
| Ethereum repeated key/message, 2 entries | 708,658,473 | 564,480,101 | 20.35% | 85,488 → 79,928 |
| Ethereum distinct keys/messages, 2 entries | 1,093,955,874 | 949,761,405 | 13.18% | 144,576 → 138,800 |
| Ethereum fast aggregate, distinct keys, 2 entries | 887,685,951 | 850,936,989 | 4.14% | 119,160 → 118,064 |
| IC distinct messages, 2 entries | 468,894,403 | 324,691,228 | 30.75% | 66,240 → 60,136 |
| Ethereum repeated key/message, 8 entries | 997,512,481 | 565,040,193 | 43.36% | 97,104 → 82,664 |
| Ethereum distinct keys/messages, 8 entries | 3,717,682,205 | 3,285,090,641 | 11.64% | 510,720 → 494,768 |
| Ethereum fast aggregate, distinct keys, 8 entries | 2,680,034,928 | 2,569,760,937 | 4.11% | 358,344 → 354,272 |
| IC distinct messages, 8 entries | 1,288,036,398 | 855,389,985 | 33.59% | 197,520 → 180,184 |

Single IC verification remains **236,236,649 instructions / 39,280 allocated bytes**; Ethereum remains **286,386,819 / 39,280**. Valid and wrong-message controls are unchanged. Raw pairing controls differ by only 19 or 28 instructions, with identical allocations. Total canister Wasm grows by **11,042–23,669 bytes** across this cohort.

The early-error regressions are retained:

| IC duplicate-message rejection | Before instructions | After instructions | Allocated bytes, before → after |
|---|---:|---:|---:|
| 2 entries | 1,896 | 7,891 | 0 → 216 |
| 8 entries | 8,175 | 10,886 | 0 → 504 |
| 127 entries | 306,828 | 300,301 | 2,120 → 6,216 |

The descriptor bridge allocates before native duplicate rejection. This adds a small bounded cost to invalid-input calls; successful aggregates save 1,096–17,336 allocated bytes. All messages, signatures and PoPs remain checked.

For eight-entry IC aggregation, post-operation occupied heap falls from **5,521,632 to 5,503,440 bytes**; Ethereum distinct aggregation falls from **5,835,528 to 5,818,808 bytes**. Every measured Wasm memory capacity remains **128 MiB**. All snapshots report **zero reclaimed bytes**, including after the four extra GC increments: these are occupied-heap observations, **not retained-live-heap or true-peak claims**. The initial heap also differs slightly between compiled modules, so occupied-heap deltas must not be equated with operation allocation.

The three aggregate profiles now execute in one plugin call. The previous Motoko wrappers checked points, encoded hash results, packed pairing terms, and asked the pairing primitive to decode and check those points again. The fused implementation borrows original input Blobs through SDK-generated descriptors and retains validated points only for that synchronous call.

Every external key, proof and signature still receives canonical, curve, subgroup and identity checks. Ethereum proofs are verified individually; only an exact key/proof pair already verified in this call is reused. Different proofs are checked again. The IC profile still rejects equal messages before cryptography. Three thin ordinary Motoko functions retain higher-order use. Public shapes, size limits and error precedence remain intact, including malformed signatures when a valid fast-aggregate key sum cancels to identity.

The single-signature verifier, field arithmetic, MSM algorithms and pairing backend are unchanged. No Motoko compiler, SDK, RTS, dependency or retained plugin state changed.

[The cohort](cohort.json) retains existing independent fixtures and expected results. [Its generator](generate-cohort.py) adds only an untimed memory query. The paired immutable stages are [baseline](../../results/round3-bls-baseline/results.json) and [final wrappers](../../results/round3-bls-fused-wrappers/results.json); the comparison records their source/build/result/toolchain hashes. Setup, queries and post-operation GC calls are outside the measured interval; each trial starts on a fresh canister.

[Native/build validation](validation/validation.json) records 24 passing kernel tests. [Independent audit](../../../../tests/crypto-audit/round3/bls12-381/README.md) records 246 guarded profile cases plus eight bounds checks, 270 public assertions on both interpreter and validated memory64 Wasm, retained message-cache boundary tests, and ordinary typed callback calls. The final replay passed all 21 commands.

Initial failures remain recorded: the Nix shell was first invoked from the wrong directory; the independent Wasm audit then caught two generated comparisons using the wrong SDK condition representation. Both now use the SDK comparison helper. The initial intrinsic aliases were also replaced by ordinary wrappers before final measurement to preserve callable-function capability. No failed or alias-only exploratory build is used as the final measured candidate.
