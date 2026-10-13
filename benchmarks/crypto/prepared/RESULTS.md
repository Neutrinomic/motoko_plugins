# Prepared cryptographic keys: measurements

All six final crypto cohorts and the two pure Motoko controls are measured: **199 cases × 3 trials = 597 successful independent output checks**. Independent crypto audits and integrated composition, rejection, packaging and codec/SHA regression checks pass. Algorithm screens and the unsuccessful initial P256 build are excluded from these counts and the tables below.

Preparation caches validated key data and precomputed tables in opaque, immutable, GC-managed Motoko values. The comparison uses each plugin's **same prepared-capable build for direct, factory and prepared calls**; shared improvements to the direct implementation are not credited to preparation. Each case runs on three fresh PocketIC canisters with the same compiler/RTS, independent input bytes, runner and dependency pins. Instruction and allocation counts were identical across all three trials in the completed cohorts, so each displayed median also equals its minimum and maximum.

Compiler: `2.0.0-16-g9f6ebeedc`, binary SHA256 `24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2`. These are new measurements; the earlier `92b1bde` figures are [historical](../round3/RESULTS.md). [Protocol and reproduction](README.md) · [comparison and archive rules](comparison-semantics.md).

## Public-call costs

Direct and prepared columns measure one public operation. **Prepared excludes the separately measured preparation.** Payload is the explicit prepared representation, excluding managed-object headers and containers. Allocation includes transient work and actual public result wrappers; it is not retained memory.

| Operation / independent fixture | Direct instructions | Preparation instructions | Prepared instructions | Payload B | Allocated B: direct / preparation / prepared |
|---|---:|---:|---:|---:|---:|
| Ed25519 sign, OpenSSL 32-byte message | 1,803,963 | 887,929 | 907,801 | 96 | 120 / 152 / 88 |
| Ed25519 verify, same message | 2,308,542 | 266,520 | 2,071,444 | 1,056 | 32 / 1,112 / 32 |
| Secp256k1 ECDSA verify, RFC6979 sample | 2,618,931 | 484,693 | 2,367,381 | 512 | 32 / 568 / 32 |
| Secp256k1 BIP340 sign, vector 0 | 5,099,447 | 2,517,394 | 2,584,269 | 64 | 120 / 120 / 120 |
| Secp256k1 BIP340 verify, vector 0 | 2,413,083 | 485,205 | 2,161,197 | 512 | 32 / 568 / 32 |
| P256 ECDSA verify, RFC6979 sample | 12,541,922 | 19,688,675 | 3,802,871 | 16,320 | 32 / 16,376 / 32 |
| RSA-3072 PSS sign, SHA-256 prehash + salt32 | 447,476,438 | 6,138,602 | 443,550,622 | 1,840 | 440 / 1,896 / 440 |
| RSA-3072 PSS verify, same fixture | 9,822,608 | 3,642,309 | 8,421,716 | 824 | 32 / 880 / 32 |
| RSA-3072 PSS sign, raw message + salt32 | 447,485,855 | 6,138,602 | 443,560,039 | 1,840 | 440 / 1,896 / 440 |
| RSA-3072 PSS verify, raw message | 9,832,026 | 3,642,309 | 8,431,134 | 824 | 32 / 880 / 32 |
| ML-DSA-44 deterministic sign, ACVP 4 | 13,193,656 | 5,016,889 | 9,076,804 | 28,800 | 2,480 / 28,856 / 2,480 |
| ML-DSA-44 verify, ACVP 4 | 3,810,844 | 2,525,559 | 1,920,986 | 20,576 | 32 / 20,632 / 32 |
| ML-DSA-44 randomized sign, ACVP 362 | 18,343,541 | 5,017,319 | 14,226,247 | 28,800 | 2,480 / 28,856 / 2,480 |
| BLS IC single, certificate fixture | 222,072,725 | 49,992,831 | 172,121,515 | 19,680 | 19,672 / 19,736 / 64 |
| BLS Ethereum single, official fixture | 286,405,944 | 12,239,690 | 274,167,416 | 144 | 39,280 / 200 / 39,280 |
| BLS IC aggregate, 2 distinct messages | 310,532,835 | 99,985,582 | 210,626,139 | 39,360 | 40,552 / 39,512 / 544 |
| BLS Ethereum aggregate, 8 distinct keys | 3,285,303,573 | 2,291,247,278 | 994,060,838 | 1,152 | 494,840 / 315,416 / 181,552 |

On these inputs, prepared Ed25519 signing uses **49.68% fewer instructions**, P256 verification **69.68% fewer**, ML-DSA verification **49.59% fewer**, and BLS IC single verification **22.49% fewer**. Ethereum single verification improves **4.27%** and keeps its 39,280-byte call allocation: message/signature pairing scratch remains.

Secp256k1 prepared BIP340 signing saves **49.32%**. Its ECDSA and BIP340 verification tables save **9.61%** and **10.44%**, respectively, using 512 payload bytes per public key. The selected table retains almost the same hot-call cost as the 1,024-byte candidate with less storage and preparation work.

RSA prehash verification improves **14.26%**; prepared signing saves only **0.88%**, since private exponentiation still dominates. Both direct and prepared rows use the selected window-five implementation, so its shared arithmetic improvement is not attributed to prepared keys. RSA's profile fixes a 3,072-bit modulus, exponent 65,537, PSS/MGF1 SHA-256 and 32-byte salt. Key generation remains external; signing uses explicit caller-provided salt.

Ed25519 signs raw messages; its prepared signer returns a Blob while the direct signer returns a Result, accounting for 32 bytes of the allocation difference. ECDSA rows use a supplied 32-byte digest and exclude message hashing. ML-DSA ACVP 4 has a 1-byte message and 59-byte context; ACVP 362 has an 871-byte message, empty context and explicit randomness. The other ML-DSA fixtures span 1,188–8,192-byte messages and contexts up to 255 bytes: prepared signing savings range from 15.76% to 46.88%, depending on rejection-sampling work. Separate direct ML-DSA `publicKey` costs 5,107,151 instructions and allocates 1,368 bytes. Algorithms, security profiles and signature sizes are different; this is not an interchangeable-security ranking.

P256 selects a width-eight table for the lowest measured repeated-call cost, trading 16,320 payload bytes and a larger factory for that speed. [Smaller table screens](p256/width-comparison.md) remain separate evidence. Full operation/input matrices: [Ed25519](ed25519/README.md), [Secp256k1 final measurements](results/prepared-secp256k1-final/results.json), [P256 final measurements](results/prepared-p256-width8-final-fixed/results.json), [RSA final measurements](results/prepared-rsa-window5-final/results.json), [ML-DSA](results/prepared-mldsa-final/summary.md), [BLS](bls12-381/measurements.md).

## Actual reuse and modeled break-even

For measured factory cost P, direct call D and prepared call H, the model is **P + N×H versus N×D**. The first strictly cheaper integer N is `P // (D-H) + 1` when H < D. This model uses only single-call medians; loop overhead, result handling and GC can make actual batches differ. No empty-loop cost is subtracted.

The model predicts two uses for Ed25519 verification, all three Secp256k1 operations, both ML-DSA operations, RSA signing and most BLS profiles, and three uses for the P256 sample and RSA verification. Ed25519 signing's first modeled use is only 8,233 instructions cheaper; the substantial benefit is reuse. That Ed25519 first-use claim is a projection, not a measured cold-call result.

The following **actual cold measurements include one factory plus N calls inside the interval**. Direct rows perform N direct calls. They show why a cheap prepared call does not automatically make one-off use faster.

| Operation | N | Direct batch instructions | Cold batch instructions | Allocated B: direct / cold |
|---|---:|---:|---:|---:|
| Secp256k1 ECDSA verify | 1 | 2,618,931 | 2,851,935 | 32 / 600 |
| Secp256k1 ECDSA verify | 2 | 5,237,984 | 5,219,361 | 64 / 632 |
| Secp256k1 ECDSA verify | 100 | 261,887,048 | 237,216,525 | 3,200 / 3,768 |
| Secp256k1 BIP340 sign | 1 | 5,099,447 | 5,101,493 | 120 / 240 |
| Secp256k1 BIP340 sign | 2 | 10,198,954 | 7,685,776 | 240 / 360 |
| Secp256k1 BIP340 sign | 100 | 509,935,548 | 260,934,926 | 12,000 / 12,120 |
| Secp256k1 BIP340 verify | 1 | 2,413,083 | 2,646,263 | 32 / 600 |
| Secp256k1 BIP340 verify | 2 | 4,826,288 | 4,807,505 | 64 / 632 |
| Secp256k1 BIP340 verify | 100 | 241,302,248 | 216,598,637 | 3,200 / 3,768 |
| P256 RFC sample verify | 1 | 12,541,922 | 23,491,346 | 32 / 16,408 |
| P256 RFC sample verify | 2 | 25,083,596 | 27,293,895 | 64 / 16,440 |
| P256 RFC sample verify | 10 | 125,416,988 | 57,714,287 | 320 / 16,696 |
| P256 RFC sample verify | 100 | 1,254,167,648 | 399,943,697 | 3,200 / 19,576 |
| ML-DSA ACVP 4 sign | 1 | 13,193,656 | 14,093,525 | 2,480 / 31,336 |
| ML-DSA ACVP 4 sign | 2 | 26,387,356 | 23,170,260 | 4,960 / 33,816 |
| ML-DSA ACVP 4 sign | 10 | 131,935,788 | 95,783,340 | 24,800 / 53,656 |
| ML-DSA ACVP 4 sign | 100 | 1,319,355,648 | 912,680,490 | 248,000 / 276,856 |
| ML-DSA ACVP 4 verify | 1 | 3,810,844 | 4,446,416 | 32 / 20,664 |
| ML-DSA ACVP 4 verify | 2 | 7,621,820 | 6,367,372 | 64 / 20,696 |
| ML-DSA ACVP 4 verify | 10 | 38,108,108 | 21,734,220 | 320 / 20,952 |
| ML-DSA ACVP 4 verify | 100 | 381,078,848 | 194,611,260 | 3,200 / 23,832 |

Ed25519's actual 100-call signing batch uses 180,386,148 direct versus 90,760,895 prepared instructions, **excluding preparation**. RSA measures signing batches up to 10 and verification batches up to 100, also excluding preparation; its 100-verification batch costs 982,253,348 direct versus 842,164,148 prepared instructions. Neither RSA nor BLS final cohorts measure cold batches.

BLS also demonstrates explicit object sharing. Eight references to one prepared Ethereum key and eight separately prepared equal keys both verify the repeated-key aggregate in 278,645,699 instructions. Shared preparation costs 286,406,258 instructions, carries 144 payload bytes and allocates 39,504 bytes. Eight factories cost 2,291,247,278 instructions, carry 1,152 payload bytes and allocate 315,416 bytes. There is no automatic key cache or deduplication. The modeled crossover changes from one use to eight; the shared first-use saving is only 26,600 instructions.

## Same-compiler pure Motoko controls

These controls rebuild pinned `ecdsa@8.0.1` with the new SDK and **the exact same compressed key, digest and compact signature bytes** as the corresponding native fixture. Reusable curve construction is outside timing; byte parsing, validation, verification and matching result handling stay inside. Library/native ratios are separate from direct/prepared reuse ratios.

| Verification fixture | Pure Motoko instructions | Direct plugin instructions | Prepared plugin instructions | Motoko/direct ratio | Motoko/prepared ratio | Allocated B: Motoko / direct / prepared |
|---|---:|---:|---:|---:|---:|---:|
| Secp256k1, RFC6979 scalar-1 sample | 137,009,273 | 2,618,931 | 2,367,381 | **52.31×** | **57.87×** | 10,903,256 / 32 / 32 |
| P256, RFC6979 sample | 323,983,718 | 12,541,922 | 3,802,871 | **25.83×** | **85.19×** | 23,927,448 / 32 / 32 |

The prepared ratio excludes its factory and compares reuse against a byte-oriented library call. It is not a benchmark of a separately predecoded Motoko key. P256's library normalizes the supplied high-S signature internally; this is a valid-input comparison, not proof of identical error or canonicality semantics. Supplied-nonce library signing is not compared to plugin RFC6979 signing. [Control sources and fixture identities](library-controls/README.md) · [measurements](results/prepared-library-controls-final/summary.md).

## Memory and lifetime

Ordinary benchmark snapshots report occupied heap and Wasm capacity before the run, after its message and after four more GC increments. They are **neither peaks nor exact retained live data**; four increments need not finish collection. All BLS snapshots recorded zero reclaimed bytes despite those increments, so its higher post-setup occupancy must not be called retained-key size. Separate pressure tests exercise prepared values across actual collection and suspension; prepared values are local and cannot be sent through Candid or persisted across upgrades.

The separate ML-DSA experiment initially **failed its absolute heap-plateau criterion**. On the pinned RTS forced GC leaves 17,504 bytes of common collector bookkeeping per trigger in the sampled window, including the baseline mode. A separately approved, post-hoc analysis compares matched baseline/public/secret samples at the same increment index; it does not relabel the original criterion as passing. With 32 separately prepared objects per mode and three trials, the observed baseline-subtracted increments were:

| Prepared type | Declared payload per key | Observed paired increment per key | Paired residual after dropping |
|---|---:|---:|---:|
| ML-DSA public | 20,576 B | 20,600 B | 0 B |
| ML-DSA secret | 28,800 B | 28,824 B | 0 B |

The deltas equal payload plus 24 bytes in this specific matched experiment. This supports collection and release under the tested schedule; it is not a universal exact-live-heap or secure-secret-erasure guarantee. The [unchanged raw run](../results/prepared-mldsa-memory/memory.json) preserves its failed qualification; the [independent paired review](../../../tests/crypto-audit/prepared/ml-dsa/paired-memory-review.json) checks every matched GC index, pinning that raw report and the exact SDK/RTS sources. The raw report's hash matches the review pin.

## Validation and provenance

| Included stage | Cases | Successful trials |
|---|---:|---:|
| [Ed25519 final](results/prepared-ed25519-final/results.json) | 30 | 90 |
| [BLS final](results/prepared-bls12-381-final/results.json) | 24 | 72 |
| [P256 width8 final fixed build](results/prepared-p256-width8-final-fixed/results.json) | 37 | 111 |
| [ML-DSA final](results/prepared-mldsa-final/results.json) | 45 | 135 |
| [RSA window5 final](results/prepared-rsa-window5-final/results.json) | 22 | 66 |
| [Secp256k1 final](results/prepared-secp256k1-final/results.json) | 39 | 117 |
| [Pure Motoko controls](results/prepared-library-controls-final/results.json) | 2 | 6 |
| **Final benchmark total** | **199** | **597** |

All six independent crypto correctness audits pass. All 23 plugin bundles build against the new SDK; the six rebuilt crypto runtimes match their audited artifacts byte-for-byte. Packaging and four build-configuration tests pass. The combined prepared-key composition fixture and 20 existing codec/SHA regression fixtures pass in all four execution engines; eight reviewed decoder/nominal rejection fixtures and one cross-plugin Ash test with actual GC also pass. [Cross-plugin composition/rejection/GC evidence](../../../tests/integration/prepared-validation/validation.json) preserves reviewed diagnostics, source/artifact pins and the executed collection assertions. [Build, packaging and regression evidence](../../../tests/integration/prepared-validation/integration.json) records the remaining gates and all 23 build manifests. These are the plugin integration gates; they are not a claim about the compiler repository's broader CI.

Each stage's `build.json` pins compiler/RTS, plugin artifacts, fixture and source hashes; `results.json` pins that build, PocketIC and runner dependencies. Results and source maps are immutable. The unsuccessful initial P256 build and algorithm screens remain archived separately rather than being counted as final successful measurements.

The [source-store index](source-store.json) and [deduplicated source archive](source-store.tar.gz) preserve 19 stages using 1,184 unique source contents. [Integrity verification](evidence-integrity.json) checks the retained metadata, source bytes, available binaries and exact restoration of the ML-DSA final snapshot. Its scope includes archived screens and failed attempts; source integrity does not convert those into successful benchmark observations.
