# Prepared Secp256k1 keys

The selected public cache stores eight canonical affine odd multiples in **512 bytes**. ECDSA and BIP340 public handles are distinct opaque types. The Schnorr secret cache stores the normalized scalar and public X in **64 bytes**. Handles are immutable, local and nonstable; callers own their lifetime. Secret managed copies do not provide guaranteed erasure.

All direct and prepared verification calls share the same immutable generator table. Prepared signing shares the ordinary constant-time nonce/sign implementation and skips repeated long-term public-key derivation. No public-data variable-time table is used by signing.

## Format selection

Each cell below is the instruction count from three identical, independently checked PocketIC trials. All 81 screening observations passed. Each format's direct/prepare/hot comparison used exactly the same plugin artifact and SDK compiler. The [selection record](selection.json) pins the three immutable stage results and their full build manifests.

| Public format | Payload | ECDSA preparation | ECDSA hot verify | Schnorr preparation | Schnorr hot verify | Preparation allocation |
|---|---:|---:|---:|---:|---:|---:|
| Affine coordinates | 64 B | 168,497 | 2,455,885 | 169,007 | 2,249,521 | 120 B |
| Odd points and endomorphisms | 1,024 B | 562,935 | 2,366,800 | 563,447 | 2,160,616 | 1,080 B |
| **Odd points; derive endomorphisms** | **512 B** | **484,693** | **2,367,381** | **485,205** | **2,161,197** | **568 B** |

The selected cache halves the 1,024-byte representation while adding only 581 hot-call instructions (about 0.025%) and reducing preparation by about 14%. It saves roughly 89,000 instructions per verification relative to affine-only caching. Only the selected representation remains in production code.

With the selected artifact, direct ECDSA/Schnorr verification costs 2,618,931 / 2,413,083 instructions. All direct/prepared verifications allocate 32 bytes for their result. Preparation amortizes after two verifications for these fixtures.

Schnorr signing costs 5,099,447 instructions directly, 2,517,394 to prepare, and 2,584,269 with the prepared secret: **49.3% fewer hot-call instructions**, amortizing after two signatures. Each operation allocates 120 bytes. These are independent RFC6979/Python-ecdsa and official BIP340 fixtures, not universal costs for every input.

## Reproduction and scope

At this source checkpoint, native tests and the 81 screening observations pass. The independent executable audit and full 39-case reuse cohort are pending; their evidence is recorded separately when complete.

`generate.py` produces matched preparation, direct, prepared and actual preparation-plus-reuse cases for 1, 2, 10 and 100 operations. Use the shared [prepared benchmark protocol](../README.md) with the exact compiler executable `SDK/src/moc`; `SDK/bin/moc` is a shell wrapper and has a different hash. Historical format stages retain their own original generators and source snapshots.

Runtime validation includes independent signature oracles, canonical factory-byte checks, scalar-boundary arithmetic comparisons, nominal-type rejection and real GC retention/release tests. Evidence lives in [the independent prepared audit](../../../../tests/crypto-audit/prepared/secp256k1/). The compiler/runtime bridge borrows each Blob afresh; it never retains a native pointer or allocates managed memory during a native call.

The shared runner records allocation, heap occupancy and Wasm capacity separately. Its four follow-up GC increments are **not** proof of collection or a peak-memory measurement; retained/released handles require the independent pressure-test evidence. Payload sizes above exclude managed-object headers and result wrappers.
