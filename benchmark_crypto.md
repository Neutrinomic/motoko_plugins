# Crypto public API benchmarks

## BLAKE3 keyed MAC

| Plugin | Input | Sign instructions | Verify instructions | Allocated B, sign / verify |
| --- | --- | ---: | ---: | ---: |
| BLAKE3 keyed (shared-secret MAC) | 1,024-byte message; 32-byte secret key | 35,935 | 40,819 | 88 / 88 |

Measured on 2026-10-13 with PocketIC 10.0.0 and compiler `9f6ebeedc`.
Generation and verification were both measured fresh, with three identical
trials each. Verification composes the plugin's `keyedHash` with a Motoko loop
that compares all 32 tag bytes using XOR/OR, without an early exit on mismatch.
First- and last-byte mismatches also cost 40,819 instructions and 88 B.
This is shared-secret authentication, not public-key signing.
[Measurements and reproduction](benchmarks/crypto/blake3-mac/summary.json).

## Current signatures — round three

The current signature plugins were measured on 2026-10-13 with PocketIC 10.0.0,
compiler `92b1bde` and the unchanged RTS/SDK. Each value is the median of three
fresh-canister trials; every measured result matched its independent oracle.
The table contains **plugins**, including RSA and ML-DSA. Some earlier raw
screen manifests call those implementations `native`; that historical label
means their compiled plugin kernel, not a pure Motoko library.

| Plugin | Input | Sign instructions | Verify instructions | Allocated B, sign / verify |
| --- | --- | ---: | ---: | ---: |
| Ed25519 | 32-byte message | 1,802,738 | 2,306,648 | 120 / 32 |
| Secp256k1 ECDSA | 32-byte SHA-256 digest | 3,618,817 | 2,735,020 | 120 / 32 |
| Secp256k1 BIP340 | 32-byte message | 5,099,055 | 2,519,140 | 120 / 32 |
| P256 ECDSA | 32-byte SHA-256 digest | 7,225,034 | 12,873,707 | 120 / 32 |
| RSA-3072 PSS | 32-byte SHA-256 digest; 32-byte signing salt | 550,857,988 | 9,822,506 | 440 / 32 |
| ML-DSA-44 | 1-byte message; 59-byte context | 14,753,165 | 3,806,359 | 2,480 / 32 |

Inputs and reusable setup are prepared before the measured call. ECDSA and
RSA prehash rows exclude message hashing; RSA uses exponent 65537,
PSS/MGF1-SHA256 and exactly 32 salt bytes. Its message API costs 550,867,405
instructions to sign and 9,831,924 to verify the tested 47-byte message.
Ed25519 is pure Ed25519 over message bytes. ML-DSA-44 uses official NIST case 4;
its signing cost includes full seed expansion, not a prepared secret key.
Other ML-DSA fixtures sign in 10,296,367–27,591,733 instructions; rejection
sampling, key and context make signing cost nonmonotonic in message length.

The algorithms use different key/signature sizes and security profiles,
including ML-DSA's post-quantum design. Cross-algorithm instruction counts do
not establish interchangeable security or a universal fastest verifier. RSA
key generation is external; the plugin includes a tested OpenSSL import helper,
CRT consistency validation and a post-signature public-operation fault check.

### Fresh Motoko verification controls

| Verification | Motoko `ecdsa@8.0.1` instructions | Current plugin instructions | Instruction ratio | Allocated B, Motoko / plugin |
| --- | ---: | ---: | ---: | ---: |
| Secp256k1 ECDSA | 135,628,126 | 2,735,020 | **49.59×** | 10,763,472 / 32 |
| P256 ECDSA | 341,837,259 | 12,873,707 | **26.55×** | 25,290,680 / 32 |

These two controls are fresh measurements against the pinned Motoko library,
not reused historical timings. Both sides include byte decoding and validation
for the same valid compact low-S signature and compressed public key; reusable
Motoko curve construction is excluded. Error semantics and all malformed-input
behavior are not asserted equivalent. No fresh Motoko counterpart was measured
for Ed25519, RSA, ML-DSA or the BLS aggregate profiles.

### Changes to existing plugins

Secp256k1 combines 10×26-bit field arithmetic with public-only GLV/NAF
verification and removes an unused predicate output buffer: ECDSA verification
falls from 10,093,580 to 2,735,020 instructions, Schnorr from 9,920,568 to
2,519,140, and each now allocates 32 rather than 56 B. P256 reuses its existing
constant-time comb for signing: 13,458,880 → 7,225,034 instructions;
verification arithmetic and its matched counts are unchanged.

BLS valid aggregate workloads save 4.11–43.36% of instructions. For example,
eight distinct IC messages fall from 1,288,036,398 to 855,389,985 instructions
and 197,520 to 180,184 allocated bytes. Small duplicate-message rejection gets
more expensive: two entries rise from 1,896 / 0 B to 7,891 / 216 B.
Whole-canister Wasm changes are −68,732 to −68,691 B for Secp256k1,
+8,416 B for P256, +10,499 B for Ed25519 versus its initial serial64 backend,
and +11,042 to +23,669 B for BLS. These are canister sizes, not runtime-only sizes.

Allocation is cumulative managed-heap allocation, including returned values
and garbage. It excludes native stack scratch. Every final measured operation
reported zero synchronous reclamation. Separate heap/capacity snapshots are
neither true peaks nor retained-live-memory measurements; four GC increments
may not finish a collection. The dedicated GC tests separately establish
retained-value correctness during actual reclamation.

[Full results and key derivation](benchmarks/crypto/round3/RESULTS.md) ·
[98-case final measurements](benchmarks/crypto/results/round3-final-direct/results.json) ·
[Fresh Motoko controls](benchmarks/crypto/results/round3-motoko-verification-controls/results.json) ·
[Measurement/reproduction protocol](benchmarks/crypto/round3/README.md).

## Historical round-two API results

The **155-callable tables below are the earlier round-two measurements**.
They remain unchanged for provenance, including their previous Secp256k1,
P256 and BLS values. Use the current signature results above for the current implementation;
no new measurements of the other crypto modules are claimed here.

<details>
<summary>Show historical 155-callable benchmark tables and their original methodology</summary>

155 public callables. **Native** means pure Motoko from pinned Mops packages; **Plugin** means the optimized `mo:fast` implementation. `Native/plugin` is the measured instruction ratio (larger favors the plugin). Empty native cells mean no correct counterpart for the listed operation in the pinned packages. Marked rows use the closest available code with the contract differences explained below.

Each value is the median of three fresh-canister trials. Inputs and reusable setup are prepared before measurement; only the named operation and result assignment are timed. Exact independent output checks run afterward. Instructions are IC instructions/op, including measured call overhead; allocated bytes are cumulative allocation/op, not live heap. Whole-canister Wasm sizes, all workload sizes, hashes and individual trials are retained in the [machine-readable evidence](benchmarks/crypto/round2/api-measurements.json).

Measured with Motoko compiler (source 2.0.0-14-g92b1bdecb), pocket-ic-server 10.0.0, and release RTS SHA256 `8456e47e527bbd58…` (full hash in evidence).

Pinned packages: `sha2@0.1.14`, `blake3@0.1.2`, `ecdsa@8.0.1`, `bitcoin@0.2.1`, `bls12-381@0.2.0`. Byte-oriented curve adapters include parsing, validation and serialization except where marked; reusable curve construction is outside timing. Prepared and streaming rows exclude construction unless construction is the named operation. Every counterpart and any contract differences are recorded per row in the evidence file.

## SHA256

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `digest` | one-shot | 1024 B | 348,657 | 81,954 | 3,712 | 56 | 4.25× |

## BLAKE3

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `deriveKey` [B] | isolated deriveKey | 1024 bytes | 3,875,001 | 38,805 | 176,104 | 56 | 99.86× |
| `digest` | unkeyed digest | 1024 bytes | 3,485,872 | 35,745 | 135,536 | 56 | 97.52× |
| `finalize` | isolated finalize | 1024 bytes | 265,269 | 41,754 | 24,304 | 88 | 6.35× |
| `finalizeXof` | short seeked XOF within one output block | 1024-byte input; seek 13; output 32 bytes | 267,446 | 41,750 | 24,312 | 88 | 6.41× |
| `keyedHash` | keyed digest | 32-byte key; 1024 bytes | 3,492,129 | 35,935 | 135,944 | 88 | 97.18× |
| `new` | isolated new | empty state | 92,375 | 6,406 | 14,768 | 2,840 | 14.42× |
| `newDeriveKey` [B] | isolated newDeriveKey | empty state | 481,567 | 9,579 | 55,336 | 2,840 | 50.27× |
| `newKeyed` | isolated newKeyed | 32-byte key; empty state | 98,592 | 6,691 | 15,176 | 2,872 | 14.74× |
| `update` | isolated update | 1024 bytes | 3,128,677 | 19,584 | 96,464 | 2,872 | 159.76× |
| `xof` | short seeked XOF within one output block | 1024-byte input; seek 13; output 32 bytes | 3,487,986 | 36,678 | 135,544 | 88 | 95.10× |

[B] Native composes published state/flag operations for correct domain-separated derivation. Extra long-XOF workloads compose output-block calls. These bounded cases match official vectors; the package’s high-level derive function ignores context, and its multi-chunk hashing remains incorrect.

## SHA512

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `Digest` | constructor | 0 B | 9,529 | 1,430 | 3,256 | 432 | 6.66× |
| `Digest.reset` | reset | 1024 B | 1,194 | 718 | 0 | 240 | 1.66× |
| `Digest.sum` | sum | 1024 B | 61,335 | 9,451 | 5,736 | 88 | 6.49× |
| `Digest.write` | write | 1024 B | 154,080 | 56,112 | 256 | 240 | 2.75× |
| `Digest384` | constructor | 0 B | 9,274 | 1,430 | 3,128 | 432 | 6.49× |
| `Digest384.reset` | reset | 1024 B | 1,194 | 718 | 0 | 240 | 1.66× |
| `Digest384.sum` | sum | 1024 B | 56,677 | 9,348 | 5,304 | 72 | 6.06× |
| `Digest384.write` | write | 1024 B | 154,080 | 56,114 | 256 | 240 | 2.75× |
| `digest` | one-shot | 1024 B | 182,086 | 61,018 | 4,544 | 88 | 2.98× |
| `digest384` | one-shot | 1024 B | 180,772 | 60,917 | 4,240 | 72 | 2.97× |

## RIPEMD160

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `Digest` | constructor | 0 B | 2,807 | 1,322 | 704 | 320 | 2.12× |
| `Digest.reset` | reset | 1024 B | 542 | 610 | 0 | 128 | 0.89× |
| `Digest.sum` [M] | sum | 1024 B | 40,253 | 5,738 | 232 | 48 | 7.02× |
| `Digest.write` | write | 1024 B | 527,428 | 55,496 | 8,216 | 128 | 9.50× |
| `digest` | one-shot | 1024 B | 570,076 | 57,247 | 9,152 | 48 | 9.96× |
| `finalize` [M] | immutable-state-finalize | 1024 B | 40,253 | 5,678 | 232 | 48 | 7.09× |
| `init` [M] | immutable-state-init | 0 B | 2,807 | 577 | 704 | 128 | 4.86× |
| `update` [M] | immutable-state-update | 1024 B | 541,428 | 55,634 | 8,216 | 128 | 9.73× |

[M] Native constructs or mutates an object and consumes it on finalization. Plugin state is an immutable serialized snapshot, and finalization preserves it. Ratios include these different state contracts.

## HMAC

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `SHA256` | constructor | 32-byte key; empty stream | 118,338 | 12,527 | 13,808 | 408 | 9.45× |
| `SHA256.reset` | reset | 32-byte key; 1024-byte message | 9,658 | 273 | 0 | 0 | 35.38× |
| `SHA256.sum` | sum | 32-byte key; 1024-byte message | 92,529 | 11,332 | 8,328 | 56 | 8.17× |
| `SHA256.write` | write | 32-byte key; 1024-byte message | 318,024 | 79,174 | 0 | 160 | 4.02× |
| `SHA512` | constructor | 32-byte key; empty stream | 159,435 | 17,349 | 16,288 | 544 | 9.19× |
| `SHA512.reset` | reset | 32-byte key; 1024-byte message | 18,934 | 273 | 0 | 0 | 69.36× |
| `SHA512.sum` | sum | 32-byte key; 1024-byte message | 116,629 | 16,384 | 10,536 | 88 | 7.12× |
| `SHA512.write` | write | 32-byte key; 1024-byte message | 154,145 | 56,141 | 256 | 296 | 2.75× |
| `prepareSha256` | prepare | 32-byte key | 98,915 | 11,948 | 10,264 | 280 | 8.28× |
| `prepareSha256.digest` | prepared digest | 32-byte key; 1024-byte message | 402,905 | 89,322 | 7,424 | 56 | 4.51× |
| `prepareSha256.stream` | prepared stream | 32-byte key; empty stream | 19,679 | 1,045 | 3,544 | 200 | 18.83× |
| `prepareSha256.stream.reset` | prepared reset | 32-byte key; 1024-byte message | 9,658 | 273 | 0 | 0 | 35.38× |
| `prepareSha256.stream.sum` | prepared sum | 32-byte key; 1024-byte message | 92,529 | 11,332 | 8,328 | 56 | 8.17× |
| `prepareSha256.stream.write` | prepared write | 32-byte key; 1024-byte message | 318,024 | 79,174 | 0 | 160 | 4.02× |
| `prepareSha512` | prepare | 32-byte key | 130,659 | 16,770 | 12,824 | 416 | 7.79× |
| `prepareSha512.digest` | prepared digest | 32-byte key; 1024-byte message | 256,072 | 69,813 | 9,344 | 88 | 3.67× |
| `prepareSha512.stream` | prepared stream | 32-byte key; empty stream | 29,032 | 1,045 | 3,464 | 200 | 27.78× |
| `prepareSha512.stream.reset` | prepared reset | 32-byte key; 1024-byte message | 18,934 | 273 | 0 | 0 | 69.36× |
| `prepareSha512.stream.sum` | prepared sum | 32-byte key; 1024-byte message | 116,629 | 16,384 | 10,536 | 88 | 7.12× |
| `prepareSha512.stream.write` | prepared write | 32-byte key; 1024-byte message | 154,145 | 56,141 | 256 | 296 | 2.75× |
| `sha256` | authenticate one message | 32-byte key; 1024-byte message | 492,476 | 99,364 | 18,112 | 56 | 4.96× |
| `sha512` | authenticate one message | 32-byte key; 1024-byte message | 350,173 | 83,009 | 22,304 | 88 | 4.22× |

## Base58

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `decode` | Bitcoin Base58 decode | 111-character input → 82-byte output | 187,866 | 13,747 | 1,544 | 280 | 13.67× |
| `encode` | Bitcoin Base58 encode | 82-byte input → 111-character output | 228,644 | 16,662 | 2,864 | 280 | 13.72× |

## Base58Check

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `decode` | checksummed Bitcoin extended-key sized payload | 78-byte payload; 4-byte checksum | 287,170 | 40,525 | 10,032 | 1,216 | 7.09× |
| `encode` | checksummed Bitcoin extended-key sized payload | 78-byte payload; 4-byte checksum | 346,092 | 46,716 | 12,040 | 1,240 | 7.41× |

## Bech32

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `convertBits` [E] | 8-bit to padded 5-bit groups | 32 input bytes; 52 output groups | 23,292 | 1,656 | 1,312 | 112 | 14.07× |
| `decode` | Bech32m decode | 2-byte HRP; 53 groups | 78,834 | 9,769 | 3,688 | 344 | 8.07× |
| `encode` | Bech32m encode | 2-byte HRP; 53 groups | 69,729 | 5,214 | 3,088 | 240 | 13.37× |

[E] Native uses the exact attributed private `bitcoin/Segwit.convertBits` function, extracted into the benchmark. It assumes valid bit widths; the plugin validates widths and enforces size limits. Both perform the same valid conversion.

## Segwit

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `decode` | Taproot v1 witness program decode | 32-byte program; 62-character address | 95,596 | 24,445 | 4,400 | 1,560 | 3.91× |
| `encode` | Taproot v1 witness program encode | 32-byte program; 62-character address | 201,151 | 21,175 | 8,968 | 1,408 | 9.50× |

## Secp256k1

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `baseMultiply` | Generator times full-width scalar | 32 bytes | 124,175,848 | 6,351,461 | 5,444,616 | 96 | 19.55× |
| `compressPublicKey` | Valid uncompressed SEC1 input | 65 bytes | 9,341,246 | 12,736 | 470,584 | 96 | 733.45× |
| `convertPublicKey` | Valid compressed SEC1 to uncompressed | 33 bytes | 39,574,794 | 575,531 | 1,664,968 | 128 | 68.76× |
| `decompressPublicKey` | Valid compressed SEC1 input | 33 bytes | 39,574,794 | 575,516 | 1,664,968 | 128 | 68.76× |
| `derivePublicKey` | 32-byte secret; compressed SEC1 output | 32 bytes | 63,224,878 | 6,351,398 | 5,278,944 | 96 | 9.95× |
| `normalizeSignature` | Compact high-S to low-S signature | 64 bytes | 14,488,926 | 2,584 | 666,624 | 120 | 5607.17× |
| `pointAdd` | Compressed and uncompressed distinct points | 33 + 65 bytes | 28,485,267 | 1,197,611 | 1,248,456 | 96 | 23.79× |
| `pointMultiply` | Compressed point and full-width scalar | 33 + 32 bytes | 148,898,913 | 6,922,349 | 6,414,664 | 96 | 21.51× |
| `publicKey` | Full-width secret; uncompressed SEC1 output | 32 bytes | 70,236,803 | 6,926,708 | 5,596,840 | 224 | 10.14× |
| `schnorrSign` | Official BIP340 vector 1, supplied auxiliary bytes | 32-byte message |  | 12,762,901 |  | 120 |  |
| `schnorrVerify` | Official BIP340 vector 1, valid signature | 32-byte message + 64-byte signature |  | 9,920,568 |  | 56 |  |
| `signPrehash` [N] | RFC6979 deterministic ECDSA of a SHA-256 digest | 32-byte secret + 32-byte digest | 76,010,180 | 7,452,214 | 6,002,504 | 120 | 10.20× |
| `signatureFromDer` | Minimal DER to compact signature | 71 bytes | 16,972,885 | 4,530 | 822,160 | 120 | 3746.77× |
| `signatureToDer` | Compact low-S signature to minimal DER | 64 bytes | 14,826,684 | 6,606 | 677,040 | 224 | 2244.43× |
| `tweakPublicKey` | Compressed point plus full-width scalar times generator | 33 + 32 bytes | 149,275,314 | 6,957,310 | 6,440,800 | 96 | 21.46× |
| `tweakXOnlyPublicKey` | Even-Y lift of X-only key plus full-width tweak | 32 + 32 bytes | 152,652,841 | 6,957,132 | 6,684,456 | 96 | 21.94× |
| `tweakXOnlySecretKey` | Full-width even-Y secret and tweak | 32 + 32 bytes | 124,045,300 | 6,349,356 | 5,446,472 | 88 | 19.54× |
| `verifyPrehash` | Valid compact low-S signature and compressed public key | 33 + 32 + 64 bytes | 135,628,126 | 10,093,580 | 10,763,472 | 56 | 13.44× |
| `xOnlyPublicKey` | Validate compressed SEC1 and extract X | 33 bytes | 24,765,721 | 571,759 | 980,168 | 88 | 43.31× |

[N] Native signs with an independently prepared RFC6979 nonce; plugin derives that nonce inside the measured call. Native secret arithmetic is variable-time. This is a closest-operation comparison, not equal API or side-channel guarantees.

## P256

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `convertPublicKey` | Valid compressed SEC1 to uncompressed | 33 bytes | 31,098,672 | 581,934 | 1,397,304 | 128 | 53.44× |
| `derivePublicKey` | 32-byte secret; compressed SEC1 output | 32 bytes | 168,233,483 | 5,207,095 | 12,489,816 | 96 | 32.31× |
| `normalizeSignature` | Compact high-S to low-S signature | 64 bytes | 14,437,561 | 2,138 | 664,552 | 120 | 6752.83× |
| `publicKey` | Full-width secret; uncompressed SEC1 output | 32 bytes | 175,332,443 | 5,207,302 | 12,810,992 | 128 | 33.67× |
| `signPrehash` [N] | RFC6979 deterministic ECDSA of a SHA-256 digest | 32-byte secret + 32-byte digest | 182,163,354 | 13,458,880 | 13,290,216 | 120 | 13.53× |
| `signatureFromDer` | Minimal DER to compact signature | 70 bytes | 16,875,526 | 4,196 | 817,952 | 120 | 4021.81× |
| `signatureToDer` | Compact low-S signature to minimal DER | 64 bytes | 14,518,740 | 6,299 | 667,264 | 224 | 2304.93× |
| `verifyPrehash` | Valid compact low-S signature and compressed public key | 33 + 32 + 64 bytes | 341,837,259 | 12,873,707 | 25,290,680 | 32 | 26.55× |

[N] Native signs with an independently prepared RFC6979 nonce; plugin derives that nonce inside the measured call. Native secret arithmetic is variable-time. This is a closest-operation comparison, not equal API or side-channel guarantees.

## BLS12381

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `aggregateVerifyEthereum` | Verify Ethereum aggregate, two distinct messages | 2 x 48-byte keys + 2 x 96-byte proofs + 2 x 32-byte messages + 96-byte signature |  | 1,093,955,874 |  | 144,576 |  |
| `aggregateVerifyIC` | Verify IC aggregate, two distinct messages | 2 x 96-byte keys + 2 x 32-byte messages + 48-byte signature |  | 468,894,403 |  | 66,240 |  |
| `fastAggregateVerifyEthereum` | Verify Ethereum aggregate, two keys and one message | 2 x 48-byte keys + 2 x 96-byte proofs + 32-byte message + 96-byte signature |  | 887,685,951 |  | 119,160 |  |
| `g1Add` | Add two validated points | 2 x 48-byte points | 328,864,468 | 28,411,996 | 12,622,968 | 104 | 11.57× |
| `g1Aggregate` | Sum four validated points | 4 points (192 bytes) | 654,545,677 | 53,140,794 | 25,008,784 | 104 | 12.32× |
| `g1Msm` | 8-term multi-scalar multiplication | 8 points (384 bytes) + 8 scalars (256 bytes) | 3,105,266,039 | 251,337,606 | 118,021,536 | 1,280 | 12.35× |
| `g1Mul` | Multiply point by scalar | 48-byte point + 32-byte scalar | 393,866,023 | 54,272,206 | 15,095,720 | 104 | 7.26× |
| `g2Add` [U] | Add two validated points | 2 x 96-byte points | 168,180,323 | 75,738,386 | 7,255,832 | 152 | 2.22× |
| `g2Aggregate` [U] | Sum four validated points | 4 points (384 bytes) | 329,778,612 | 148,143,245 | 14,141,336 | 152 | 2.23× |
| `g2Msm` [P] | 8-term multi-scalar multiplication, repeated point | 8 points (768 bytes) + 8 scalars (256 bytes) | 4,617,878,655 | 805,297,631 | 186,921,344 | 2,096 | 5.73× |
| `g2Mul` [P] | Multiply point by scalar | 96-byte point + 32-byte scalar | 572,985,181 | 168,868,760 | 23,188,592 | 152 | 3.39× |
| `hashToG1` | RFC 9380 hash-to-curve | 3-byte message + 50-byte DST |  | 15,834,345 |  | 104 |  |
| `hashToG2` | RFC 9380 hash-to-curve | 3-byte message + 50-byte DST |  | 65,993,104 |  | 152 |  |
| `mapToG1` | Map field element to curve | 48-byte field element | 87,018,850 | 11,894,066 | 3,721,672 | 104 | 7.32× |
| `mapToG2` | Map extension-field element to curve | 96-byte field element (2 x 48 bytes) | 504,926,422 | 49,488,495 | 19,800,200 | 152 | 10.20× |
| `pairingCheck` [P] | Pairing product, two cancelling terms | 2 pairs (288 bytes: 2 x (48 + 96)) | 676,099,164 | 99,939,097 | 31,422,544 | 696 | 6.77× |
| `validateG1` | Validate compressed subgroup point | 48-byte point | 163,459,310 | 12,247,316 | 6,204,312 | 104 | 13.35× |
| `validateG2` [U] | Validate subgroup point | 96-byte point | 82,316,657 | 35,782,534 | 3,492,640 | 152 | 2.30× |
| `verifyEthereum` | Verify Ethereum POP-profile signature | 48-byte key + 32-byte message + 96-byte signature |  | 286,386,819 |  | 39,280 |  |
| `verifyEthereumProof` | Verify proof of possession | 48-byte key + 96-byte proof |  | 286,386,744 |  | 39,280 |  |
| `verifyIC` | Verify IC NUL signature | 96-byte key + 46-byte message + 48-byte signature |  | 236,236,649 |  | 39,280 |  |

[U] Native decodes and subgroup-validates 256-byte EIP-2537 uncompressed points; plugin accepts 96-byte compressed points and also recovers coordinates. Both encode compressed outputs. [P] Native starts from trusted predecoded points/scalars; arithmetic result encoding is outside timing. Plugin includes byte decoding, validation and encoding. Pairing returns a Boolean. These rows compare the same mathematical inputs and outputs with different API work, so their ratios are not equivalent-contract speedups.

## Bitcoin/Hash

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `digest256` | Double SHA256 compatibility alias | 32-byte message | 72,334 | 9,792 | 7,704 | 112 | 7.39× |
| `hash160` | SHA256 followed by RIPEMD160 | 32-byte message | 81,797 | 8,622 | 4,880 | 104 | 9.49× |
| `sha256d` | Double SHA256 | 32-byte message | 72,334 | 9,792 | 7,704 | 112 | 7.39× |
| `taggedHash` | Compute BIP340 tagged SHA256 | 8-byte TapTweak tag + 32-byte message | 120,329 | 35,855 | 8,928 | 1,024 | 3.36× |
| `taggedHasher` | Construct cached-tag hash closure | 8-byte TapTweak tag; 32-byte check message outside timing | 33,410 | 5,956 | 3,752 | 96 | 5.61× |
| `taggedHasher.call` | Invoke cached-tag hash closure | 32-byte message; 8-byte tag prepared outside timing | 64,028 | 30,309 | 3,712 | 968 | 2.11× |

## Bitcoin/Address

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `decode` | Decode mainnet witness-v0 address and check network | 42-character address / 20-byte program | 67,238 | 17,802 | 3,408 | 1,296 | 3.78× |
| `encode` | Encode mainnet witness-v0 address | 20-byte program | 139,514 | 14,624 | 6,712 | 1,064 | 9.54× |
| `hrp` | Select regtest human-readable address prefix | 1 regtest network variant | 324 | 324 | 0 | 0 | 1.00× |
| `p2pkh` | Validate compressed key and derive mainnet P2PKH address | 33-byte compressed SEC1 public key | 24,993,652 | 607,053 | 995,792 | 1,224 | 41.17× |
| `p2sh` | HASH160 redeem script and encode mainnet P2SH address | 34-byte redeem script | 204,638 | 36,021 | 14,232 | 1,128 | 5.68× |
| `p2tr` | Tweak empty-tree internal key and encode mainnet Taproot address | 32-byte internal x-only key | 152,356,558 | 7,021,150 | 6,677,888 | 3,120 | 21.70× |
| `p2trOutput` | Validate and encode tweaked mainnet Taproot output key | 32-byte tweaked x-only key | 25,068,336 | 602,921 | 990,584 | 2,000 | 41.58× |
| `p2wpkh` | Validate compressed key and derive mainnet P2WPKH address | 33-byte compressed SEC1 public key | 25,011,677 | 595,337 | 993,128 | 1,336 | 42.01× |
| `p2wsh` | SHA256 witness script and encode mainnet P2WSH address | 34-byte witness script | 236,505 | 27,390 | 12,680 | 1,568 | 8.63× |
| `scriptPubKey` | Decode and network-check P2PKH address, build locking script | 34-character address / 25-byte output script | 292,855 | 33,655 | 20,504 | 1,536 | 8.70× |
| `signTaprootKeyPath` | Tweak internal secret and BIP340-sign supplied key-path digest | 32-byte secret + 32-byte digest + 32-byte auxiliary randomness |  | 25,505,611 |  | 1,808 |  |
| `taprootOutputKey` | Compute empty-tree Taproot output key and parity | 32-byte internal x-only key | 152,156,951 | 6,999,561 | 6,669,200 | 1,608 | 21.74× |
| `taprootSecretKey` [S] | Derive empty-tree Taproot signing scalar | 32-byte full-width internal secret | 248,262,603 | 12,742,701 | 10,899,648 | 1,656 | 19.48× |

[S] Native composes published curve/scalar arithmetic and tagged hashing for the same BIP341 secret tweak. Its secret arithmetic is variable-time.

## Bitcoin/Bip32

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `deriveChild` | Derive nonhardened child zero from official BIP32 vector-2 root | 78-byte parent payload / 1 child index / depth 1 | 171,779,710 | 7,592,952 | 7,319,408 | 1,776 | 22.62× |
| `derivePath` | Derive two nonhardened children from official BIP32 vector-2 root | 78-byte parent payload / indices [0,1] / depth 2 | 321,348,873 | 14,612,141 | 13,764,984 | 3,488 | 21.99× |
| `deriveTextPath` | Parse textual path and derive two nonhardened children | 78-byte parent payload + m/0/1 (5 bytes) / depth 2 | 321,409,635 | 14,615,878 | 13,771,120 | 3,800 | 21.99× |
| `fingerprint` | Validate compressed key and compute HASH160 fingerprint | 33-byte compressed SEC1 public key / 4-byte result | 24,822,041 | 582,025 | 980,408 | 368 | 42.65× |
| `fromPublicKey` | Validate and construct depth-zero mainnet extended public key | 33-byte compressed key + 32-byte chain code | 24,740,381 | 572,681 | 975,720 | 200 | 43.20× |
| `parse` | Parse and validate official BIP32 vector-2 root xpub | 111-character xpub / 78-byte payload | 25,098,210 | 629,946 | 992,480 | 2,336 | 39.84× |
| `parsePath` | Parse strict nonhardened textual path | m/0/1 (5 UTF-8 bytes) / 2 indices | 59,842 | 2,994 | 5,944 | 152 | 19.99× |
| `serialize` | Serialize official BIP32 vector-2 root xpub | 78-byte node payload / depth zero | 25,120,503 | 639,777 | 988,384 | 2,120 | 39.26× |

## Bitcoin/Script

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `p2pkh` | Build P2PKH locking script | 20-byte public-key hash / 25-byte script | 47,742 | 6,683 | 1,952 | 280 | 7.14× |
| `p2sh` | Build P2SH locking script | 20-byte script hash / 23-byte script | 43,840 | 6,373 | 1,848 | 256 | 6.88× |
| `p2tr` | Build witness-v1 Taproot locking script | 32-byte output key / 34-byte script | 59,396 | 9,471 | 2,392 | 400 | 6.27× |
| `p2wpkh` | Build witness-v0 P2WPKH locking script | 20-byte key hash / 22-byte script | 41,761 | 6,483 | 1,824 | 288 | 6.44× |
| `p2wsh` | Build witness-v0 P2WSH locking script | 32-byte script hash / 34-byte script | 59,351 | 9,481 | 2,392 | 400 | 6.26× |
| `pushData` | Build minimally encoded PUSHDATA1 | 80-byte data / 82-byte script | 115,933 | 21,327 | 3,936 | 832 | 5.44× |
| `tapBranchHash` | Sort child commitments and compute BIP341 TapBranch hash | 2 x 32-byte child hashes | 160,077 | 39,753 | 10,376 | 1,256 | 4.03× |
| `tapLeafHash` | Compute BIP341 current-version TapLeaf commitment | 34-byte tapscript / leaf version 0xc0 | 137,278 | 32,200 | 9,864 | 1,112 | 4.26× |
| `witnessProgram` | Build future witness-v2 locking script | 32-byte program / 34-byte script | 59,673 | 9,429 | 2,424 | 400 | 6.33× |

## Bitcoin/Transaction

| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |
|---|---|---|---:|---:|---:|---:|---:|
| `SegwitV0Hasher.signatureHash` | Compute first cold BIP143 digest from prepared hasher | 10 inputs / 2 outputs / input index 0 / ALL / 25-byte scriptCode |  | 245,557 |  | 9,056 |  |
| `TaprootHasher.signatureHash` [C] | Compute first cold BIP341 digest from prepared hasher | 10 inputs / 2 outputs / input index 0 / DEFAULT / 34-byte spent scripts | 1,323,009 | 400,300 | 60,408 | 14,624 | 3.31× |
| `parse` | Parse complete legacy transaction | 494 wire bytes / 10 inputs / 2 outputs | 261,824 | 131,979 | 14,728 | 6,984 | 1.98× |
| `prepareSegwitV0` | Validate transaction and construct lazy BIP143 hasher | 10 inputs / 2 outputs; check digest outside timing |  | 21,213 |  | 1,968 |  |
| `prepareTaproot` | Validate transaction and prevouts, construct lazy BIP341 hasher | 10 inputs / 2 outputs / 10 spent outputs; check digest outside timing |  | 30,389 |  | 2,928 |  |
| `serialize` | Serialize complete legacy transaction | 10 inputs / 2 outputs / 494 wire bytes | 552,769 | 144,609 | 30,880 | 6,760 | 3.82× |
| `signatureHashLegacy` | Compute one complete legacy SIGHASH_ALL digest | 10 inputs / 2 outputs / input index 0 / 25-byte scriptCode | 1,076,205 | 200,447 | 50,592 | 7,136 | 5.37× |
| `signatureHashSegwitV0` | Compute one complete BIP143 SIGHASH_ALL digest | 10 inputs / 2 outputs / input index 0 / 25-byte scriptCode |  | 266,530 |  | 11,024 |  |
| `signatureHashTaproot` | Compute one complete BIP341 key-path DEFAULT digest | 10 inputs / 2 outputs / input index 0 / equal 34-byte spent scripts | 1,323,009 | 430,460 | 60,408 | 17,552 | 3.07× |
| `txid` | Serialize without witness and compute display-order transaction ID | 10 inputs / 2 outputs / 494 wire bytes | 770,490 | 196,503 | 38,904 | 7,248 | 3.92× |
| `wtxid` | Serialize with witness option and compute display-order transaction ID | 10 inputs / 2 outputs / empty witness stacks / 494 wire bytes | 776,045 | 197,444 | 39,568 | 7,248 | 3.93× |

[C] Native computes an uncached one-shot Taproot hash; plugin measures the first cold call on a prepared hasher. Preparation is excluded, lazy common hashes are included. Native returns an array with oracle conversion outside timing; plugin returns a Blob.

Pure Motoko secret-key arithmetic can be variable-time; ratios compare mathematical outputs, not side-channel guarantees. The pinned packages lack BIP340, complete RFC 9380/BLS signature profiles, BIP143, and retained Taproot-hasher construction counterparts; those cells remain empty. Per-row explanations and all adapter sources are in the evidence file.

See [optimization results](benchmarks/crypto/round2/RESULTS.md) for before/after changes, regressions and Wasm-size tradeoffs; the [original Mops comparison report](benchmarks/crypto/RESULTS.md) remains unchanged.

</details>

## BLS verification optimization — round six

The BLS plugin now uses fixed-width partial products for widening multiplication,
simpler modular subtraction and a shorter final-exponentiation schedule. The
compiler, SDK, validation rules, public API and prepared-key layouts are unchanged.

| Verification | Before: instructions | Current: instructions | Reduction | Allocated B, before / current |
| --- | ---: | ---: | ---: | ---: |
| IC, direct | 210,673,356 | 127,630,963 | 39.42% | 64 / 64 |
| IC, prepared key | 167,427,790 | 101,276,827 | 39.51% | 64 / 64 |
| Ethereum, direct | 274,974,367 | 167,544,868 | 39.07% | 64 / 64 |
| Ethereum, prepared key | 263,831,154 | 161,204,207 | 38.90% | 64 / 64 |
| IC aggregate, 2 distinct keys, prepared | 204,848,489 | 124,128,212 | 39.40% | 544 / 544 |
| Ethereum aggregate, 8 distinct keys, prepared | 976,180,848 | 600,858,961 | 38.45% | 181,552 / 181,552 |

Prepared verification excludes key setup, measured separately in the report.
Three identical fresh-canister trials per workload and revision on PocketIC
10.0.0, compiler `9f6ebeedc`. Runtime Wasm shrank from 655,629 to 617,967 B.
[Full 15-workload comparison and reproduction](benchmarks/crypto/bls-verify-round6/README.md) ·
[Independent arithmetic review and validation](tests/crypto-audit/round6/bls12-381/README.md).

## IC certified-data relay verification

An untrusted client can carry A's certificate and Merkle witness to B. Caching
A's authenticated certified root lets every client proving a record against
that root skip repeated BLS verification.

| Verification path | Instructions, 1,000 entries | Instructions, 100,000 entries | Allocated B, 1,000 / 100,000 entries |
| --- | ---: | ---: | ---: |
| Cold: root delegation and subnet signatures | 257,292,031 | 257,631,383 | 102,320 / 117,552 |
| Cached verified delegation and prepared subnet key | 102,586,047 | 102,925,399 | 65,408 / 80,640 |
| Cached authenticated A root; application proof only | **565,546** | **904,898** | **26,176 / 41,408** |

Remeasured after the BLS optimization on 2026-10-13 with PocketIC 10.0.0,
compiler `9f6ebeedc`, our BLS/SHA plugins and the unchanged bounded Motoko
certificate decoder. Authentic NNS-delegated
certificates; 32-byte values and 8-byte labels; three identical trials per case.
Cache setup, incoming Candid decoding, replay tracking and business logic are
excluded. Allocation is cumulative, not retained heap. Snapshots retain their
signed-time expiry; previously unseen roots still require signature checks.
This is a research prototype, not a production certificate verifier.
[Cache design and initial measurements](benchmarks/crypto/ic-certified-relay/README.md) ·
[Current comparison and reproduction](benchmarks/crypto/bls-verify-round6/README.md) ·
[45 current observations and 12 rejection controls](benchmarks/crypto/bls-verify-round6/relay-results.json).
