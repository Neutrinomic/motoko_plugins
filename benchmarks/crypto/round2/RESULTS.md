# Crypto optimization round two

Every comparison uses the delivered implementation frozen before this round and the identical public API, input, output oracle, compiler, RTS and PocketIC version. Each variant has three fresh-canister trials. Input setup and byte checking are outside the measured interval. Values are median IC instructions, cumulative allocation and whole-canister Wasm bytes. This report compares the previous plugin implementation with the optimized plugin; the [public API table](../../../benchmark_crypto.md) separately compares pure Motoko with plugins.

| Family | Representative workload | Before instructions | After instructions | Reduction | Allocation delta B | Wasm delta B |
|---|---|---:|---:|---:|---:|---:|
| sha256 | `sha256-33` | 5,802 | 5,018 | 13.51% | +0 | +103 |
| blake3 | `blake3-stream-1024-chunks256` | 333,237 | 112,934 | 66.11% | +0 | -1,750 |
| sha512 | `sha512-stream-64-chunks1` | 332,610 | 212,291 | 36.17% | +0 | -968 |
| ripemd160 | `ripemd160-stream-64-chunks1` | 205,155 | 113,255 | 44.80% | +0 | -38 |
| hmac-sha2 | `hmac-sha512-stream-k32-n1024-c1` | 5,210,815 | 3,168,562 | 39.19% | +0 | +1,563 |
| base58 | `base58-encode-4096-pattern` | 53,842,476 | 19,001,036 | 64.71% | +0 | +1,640 |
| bech32 | `bech32-convert-8to5-n4096` | 388,179 | 106,461 | 72.57% | +0 | +319 |
| secp256k1 | `r2-secp256k1-schnorr-sign-message-32` | 25,455,441 | 12,762,901 | 49.86% | +0 | -1,618 |
| p256 | `p256_verify_ecdsa_fast` | 22,609,363 | 12,873,756 | 43.06% | +0 | +4,768 |
| bls12-381 | `bls12_381_pairing_identity_fast` | 268,416,688 | 99,939,097 | 62.77% | -39,360 | +11,834 |
| Bitcoin composition | `api-bitcoin-transaction-serialize` | 402,453 | 144,609 | 64.07% | -13,944 | +3,385 |

- **sha256:** Fixed 32/33-byte padding path. 38 workload variants; 37 instruction regressions. Whole-canister Wasm change +103 to +103 bytes. Largest relative regression: `sha256-32`, 0.97% (+48 instructions).
- **blake3:** Direct output and borrowed streaming state. 28 workload variants; 0 instruction regressions. Whole-canister Wasm change -1,918 to -1,750 bytes.
- **sha512:** Batched upstream compression and state copies. 40 workload variants; 0 instruction regressions. Whole-canister Wasm change -968 to -968 bytes.
- **ripemd160:** Canonical state validation and short updates. 20 workload variants; 0 instruction regressions. Whole-canister Wasm change -38 to -38 bytes.
- **hmac-sha2:** Pad/context reuse and direct state output. 32 workload variants; 0 instruction regressions. Whole-canister Wasm change +1,563 to +1,563 bytes.
- **base58:** Grouped-radix limb conversion. 68 workload variants; 2 instruction regressions. Whole-canister Wasm change +1,640 to +1,640 bytes. Largest relative regression: `base58-decode-12-pattern`, 4.38% (+110 instructions).
- **bech32:** Checksum table and grouped bit conversion. 48 workload variants; 0 instruction regressions. Whole-canister Wasm change +319 to +319 bytes.
- **secp256k1:** Reuse Schnorr constructor results and secret-tweak public point. 51 workload variants; 3 instruction regressions. Whole-canister Wasm change -1,618 to -1,618 bytes. Largest relative regression: `r2-secp256k1-convert-uncompressed-to-compressed`, 0.08% (+10 instructions).
- **p256:** Fixed-base key multiplication and public-input verifier. 25 workload variants; 6 instruction regressions. Whole-canister Wasm change +4,768 to +4,780 bytes. Largest relative regression: `r2-p256-convert-uncompressed-to-compressed`, 0.28% (+54 instructions).
- **bls12-381:** Pairing/MSM and aggregation reuse. 67 workload variants; 28 instruction regressions. Whole-canister Wasm change +11,834 to +14,467 bytes. Largest relative regression: `round2_bls12_381_aggregate_ic_late_duplicate_n2`, 3.10% (+57 instructions).
- **Bitcoin composition:** Contiguous writers, direct copies and prepared data reuse. 99 workload variants; 0 instruction regressions. Whole-canister Wasm change -9,376 to +3,897 bytes.

The retained [complete comparisons](experiment-review.json) include all measured sizes and regressions. No speedup is inferred from an unmeasured case. Improvements are workload-specific; prepared APIs and streaming boundaries are labelled in the fixture manifests. Source and artifact fingerprints are retained with every build.

Rejected experiments remain in the evidence: custom SHA512 and RIPEMD compression kernels did not justify their maintenance/code-size cost; the SHA512 SIMD runtime was rejected by the compiler importer; BLAKE3 short-output shortcuts increased code size and regressed long XOF; secp256k1 mixed-add specializations added about 18 KiB for small arithmetic gains. Earlier Base58 and Bech32 candidates were superseded after small-input measurements exposed dispatch overhead.

Round-one files remain unchanged. Nested oracle generators and fixture inputs are retained in the round-two source store; early stages have an explicitly labelled supplemental oracle snapshot, while their compiled actors, expected bytes and build/run protocol were frozen before measurement. Recovered early launcher bodies are accepted only when their SHA256 matches recorded metadata.

## Combined final build

All 30 composed workloads passed three fresh-canister exact-output trials against the final shared plugins and final Bitcoin modules. These numbers include the combined changes; the family experiments above isolate their respective candidate changes.

| Workflow | Variant | Before instructions | Final instructions | Reduction | Allocation delta B |
|---|---|---:|---:|---:|---:|
| `bitcoin-hash160-pubkey` | plugin | 9,410 | 8,626 | 8.33% | +0 |
| `bitcoin-p2pkh` | plugin prevalidated | 40,172 | 34,963 | 12.97% | -304 |
| `bitcoin-bip32-child0` | plugin | 8,265,639 | 8,232,185 | 0.40% | -608 |
| `bitcoin-bip86-receive-address` | plugin | 22,870,034 | 22,833,737 | 0.16% | -608 |
| `bitcoin-serialize-100-inputs` | plugin | 3,683,665 | 1,209,481 | 67.17% | -137,784 |
| `bitcoin-legacy-all-sign-all-100-inputs` | plugin | 400,819,144 | 152,994,644 | 61.83% | -13,800,800 |
| `bitcoin-taproot-default-sign-all-100-inputs` | plugin | 600,914,344 | 299,917,144 | 50.09% | -13,824,800 |
| `bitcoin-bip143-all-cache-100-inputs` | plugin prepared | 14,840,351 | 8,117,745 | 45.30% | -293,544 |
| `bitcoin-taproot-default-cache-100-inputs` | plugin prepared | 16,982,261 | 11,005,457 | 35.19% | -231,704 |

The BLS repeated-message cache is limited to messages of at most 1,024 bytes. Three additional 16-key workloads with independently generated proofs/signatures cover shared-prefix 4 KiB and 64 KiB distinct messages and a repeated 64 KiB message. Distinct long-message workloads add only 206,645 instructions (about 0.0028%) versus the delivered baseline; the repeated 64 KiB workload still improves 7.51% through other retained changes. All nine trials match independent outputs.
