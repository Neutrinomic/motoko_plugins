# Signature plugin results — round three

The final integrated build adds Ed25519, RSA-PSS and ML-DSA-44 and retains the
measured Secp256k1, P256 and BLS optimizations. All **98 workloads × 3
fresh-canister trials passed** their independent expected results. The compiler
remains `92b1bdecbc7bc67fd51ad226f8d147d15494fc09`, with the original RTS and
plugin ABI 1; no SDK or GC change contributes to these results.

## Current public signature costs

IC instructions per call and cumulative allocated bytes. Each value is the
median of three trials, including input decoding/validation and the public
operation. All three trials have identical instruction, allocation and reclamation
counters for every final case. Setup and output-oracle checks are outside timing.

| Plugin | Input | Sign instructions | Verify instructions | Allocated B, sign / verify |
| --- | --- | ---: | ---: | ---: |
| Ed25519 | 32-byte message | 1,802,738 | 2,306,648 | 120 / 32 |
| Secp256k1 ECDSA | 32-byte SHA-256 digest | 3,618,817 | 2,735,020 | 120 / 32 |
| Secp256k1 BIP340 | 32-byte message | 5,099,055 | 2,519,140 | 120 / 32 |
| P256 ECDSA | 32-byte SHA-256 digest | 7,225,034 | 12,873,707 | 120 / 32 |
| RSA-3072 PSS | 32-byte SHA-256 digest; 32-byte signing salt | 550,857,988 | 9,822,506 | 440 / 32 |
| ML-DSA-44 | 1-byte message; 59-byte context | 14,753,165 | 3,806,359 | 2,480 / 32 |

`signPrehash` / `verifyPrehash` are used for ECDSA and RSA; SHA-256 hashing is
excluded from those rows. Secp256k1 and P256 verification use compressed SEC1
public keys and valid compact low-S signatures. BIP340 uses its official
32-byte-message fixture and caller-supplied signing auxiliary bytes. Ed25519
uses an independent OpenSSL 32-byte-message fixture and the selected upstream
serial32 backend; this is pure Ed25519, not Ed25519ph. ML-DSA uses final FIPS 204
ML-DSA-44, official NIST ACVP group 1 case 4, with its one-byte message and
59-byte context. **All rows above are plugins.** Older RSA/ML-DSA screening
manifests sometimes use `native` to label the compiled plugin, not Motoko code.

These schemes have different formats and security profiles; choosing one also
requires compatible signers, keys and protocols. A faster fixture does not
establish equal security or a universally fastest scheme. Ed25519 uses 32-byte
public keys and 64-byte signatures; the measured ECDSA keys are 33-byte SEC1
and signatures are 64-byte compact values. BIP340 uses 32-byte x-only keys and
64-byte signatures. RSA uses a 384-byte public modulus and signature;
ML-DSA-44 uses 1,312-byte public keys and 2,420-byte signatures.

RSA fixes the public exponent at 65537 and uses PSS with SHA-256,
MGF1-SHA256 and exactly 32 bytes of supplied salt. Its message APIs cost
**550,867,405** signing and **9,831,924** verification instructions for the
47-byte fixture, versus the prehash costs above. RSA keys are generated
externally; the [OpenSSL import helper](../../../plugins/rsa/README.md) validates
and converts standard keys to the plugin's fixed CRT representation. Runtime
CRT consistency checks do not prove the factors prime, and signing checks the
completed signature with the public exponent before returning it.

ML-DSA signing includes **full expansion of its 32-byte seed on every call**.
Across five official deterministic/hedged fixtures, signing costs
10,296,367–27,591,733 instructions and allocates 2,480 B; verification costs
3,806,359–4,466,575 and allocates 32 B. Rejection sampling varies by key,
message, context and randomness: the 8,192-byte case signs faster than one
1,188-byte case. Public-key generation below is a separate operation, not an
estimate to subtract from signing. [Per-fixture ML-DSA results](ml-dsa/README.md).

## Public-key derivation

| Plugin and operation | Output bytes | Instructions | Allocated B |
| --- | ---: | ---: | ---: |
| Ed25519 `derivePublicKey` | 32 | 888,629 | 88 |
| Secp256k1 `derivePublicKey` | 33 | 2,517,615 | 96 |
| P256 `derivePublicKey` | 33 | 4,968,688 | 96 |
| RSA `derivePublicKey` | 384 | 1,946,943 | 440 |
| MLDSA `publicKey` | 1,312 | 5,109,077 | 1,368 |

These calls derive public keys from caller-provided secrets/seeds; they do not
create cryptographic randomness. RSA derives its modulus from an imported
private CRT key. Ed25519's seeded keypair helper costs 888,951 instructions
and allocates 160 B, retaining the caller's seed reference.

## Fresh pure Motoko verification comparison

| Verification | Motoko `ecdsa@8.0.1` instructions | Current plugin instructions | Instruction ratio | Allocated B, Motoko / plugin |
| --- | ---: | ---: | ---: | ---: |
| Secp256k1 ECDSA | 135,628,126 | 2,735,020 | **49.59×** | 10,763,472 / 32 |
| P256 ECDSA | 341,837,259 | 12,873,707 | **26.55×** | 25,290,680 / 32 |

[Both controls](../results/round3-motoko-verification-controls/results.json)
were measured again with the frozen compiler, RTS, runner and independent
valid inputs. The Motoko adapter includes byte parsing, strict length/range
checks and verification; reusable curve construction is prepared outside timing.
Its `ecdsa@8.0.1` signature handling normalizes S; the chosen signatures are
already low-S. Error text and every malformed-input boundary are not identical
contracts. No current library comparison is claimed for Ed25519, RSA, ML-DSA
or BLS aggregation. The two instruction ratios are for these valid calls. The
[comparison certificate](comparisons/motoko-verification.json) checks the frozen
stages and exact decoded key/digest/signature input bytes across both adapters.

## What the optimizations change

| Matched plugin workload | Before instructions | Final instructions | Reduction | Allocated B, before → final |
| --- | ---: | ---: | ---: | ---: |
| Secp256k1 ECDSA verify | 10,093,580 | 2,735,020 | 72.90% | 56 → 32 |
| Secp256k1 Schnorr verify | 9,920,568 | 2,519,140 | 74.61% | 56 → 32 |
| Secp256k1 ECDSA sign | 7,452,214 | 3,618,817 | 51.44% | 120 → 120 |
| Secp256k1 Schnorr sign | 12,762,901 | 5,099,055 | 60.05% | 120 → 120 |
| P256 sign | 13,458,880 | 7,225,034 | 46.32% | 120 → 120 |
| P256 public-key derivation | 5,207,095 | 4,968,688 | 4.58% | 96 → 96 |
| Ed25519 verify, 32-byte message | 6,267,668 | 2,306,648 | 63.20% | 32 → 32 |
| Ed25519 sign, 32-byte message | 3,455,698 | 1,802,738 | 47.83% | 120 → 120 |
| RSA prehash verify, initial → fixed exponent | 23,623,625 | 9,822,506 | 58.42% | 32 → 32 |
| RSA prehash sign, initial → fixed exponent | 564,659,446 | 550,857,988 | 2.44% | 440 → 440 |

Secp256k1/P256/BLS compare with the delivered plugins. Ed25519 compares its
initial serial64 backend with upstream serial32; RSA compares its initial
public exponentiation with a fixed-65537 specialization. The latter two are
optimization steps within newly added plugins, not speedups over previously
shipped implementations or Motoko libraries.

Secp256k1 selects upstream 10×26-bit coordinate arithmetic suited to Wasm,
then uses GLV/width-five NAF multiplication only for public-input verification.
Secret operations retain their constant-time arithmetic path. Omitting an
unused zero-length predicate output Blob removes 24 allocated bytes from each
verifier. P256 reuses its constant-time generator comb for RFC6979 signing;
verification arithmetic is unchanged, as are its matched verification counts.
Ed25519 selects upstream serial32 rather than emulating wider multiplication.
RSA's private exponentiation is unchanged; its signing improvement comes from
the required public-operation fault check. [RSA matched screen](rsa/README.md).

Whole-canister Wasm changes are **−68,732 to −68,691 B for Secp256k1**,
**+8,416 B for P256**, **+10,499 B for Ed25519**, and **+11,042 to +23,669 B for
BLS** across their matched cohorts. RSA's original matched exponent screen
adds 838 B. These numbers describe each entire compiled fixture canister,
not just the plugin's runtime. Later fixtures with extra memory queries must
not be mixed with earlier fixture sizes.

The early seven-case Secp256k1 screen unwrapped `#ok` inside its timed call.
The final verification/Schnorr actors store the complete `Result` and unwrap
it in the untimed output query. This changes the measured caller work: ECDSA
verification is 2,735,020 here versus 2,735,069 in that screen, Schnorr
verification is 2,519,140 versus 2,519,189, and Schnorr signing is 5,099,055
versus 5,099,108. Each reported improvement uses identical actor source on
both sides; these are different fixtures, not variable results from one fixture.

Strict final comparisons retain every selected row, including neutral and
regressing cases: [Secp256k1](comparisons/final-secp256k1.json),
[P256](comparisons/final-p256.json), [Ed25519](comparisons/final-ed25519.json),
[BLS](comparisons/final-bls12-381.json).

## BLS aggregate gains and early-error costs

The aggregate bridge validates and computes within one synchronous plugin
call, avoiding repeated packing, decoding and validation of intermediate
points. External key/signature/subgroup checks and Ethereum proof-of-possession
checks remain. No decoded native key is retained between calls.

| Valid aggregate workload | Before instructions | Final instructions | Reduction | Allocated B, before → final |
| --- | ---: | ---: | ---: | ---: |
| Ethereum repeated key/message, 2 entries | 708,658,473 | 564,480,101 | 20.35% | 85,488 → 79,928 |
| Ethereum distinct keys/messages, 2 entries | 1,093,955,874 | 949,761,405 | 13.18% | 144,576 → 138,800 |
| Ethereum fast aggregate, distinct keys, 2 entries | 887,685,951 | 850,936,989 | 4.14% | 119,160 → 118,064 |
| IC distinct messages, 2 entries | 468,894,403 | 324,691,228 | 30.75% | 66,240 → 60,136 |
| Ethereum repeated key/message, 8 entries | 997,512,481 | 565,040,193 | 43.36% | 97,104 → 82,664 |
| Ethereum distinct keys/messages, 8 entries | 3,717,682,205 | 3,285,090,641 | 11.64% | 510,720 → 494,768 |
| Ethereum fast aggregate, distinct keys, 8 entries | 2,680,034,928 | 2,569,760,937 | 4.11% | 358,344 → 354,272 |
| IC distinct messages, 8 entries | 1,288,036,398 | 855,389,985 | 33.59% | 197,520 → 180,184 |

Single-signature IC verification remains **236,236,649 instructions / 39,280
allocated B**; Ethereum remains **286,386,819 / 39,280 B**. These single-signature
and wrong-message controls are unchanged. Pairing controls differ by only
19–28 instructions, with unchanged allocation.

| IC duplicate-message rejection | Before instructions | Final instructions | Allocated B, before → final |
| --- | ---: | ---: | ---: |
| 2 entries | 1,896 | 7,891 | 0 → 216 |
| 8 entries | 8,175 | 10,886 | 0 → 504 |
| 127 entries | 306,828 | 300,301 | 2,120 → 6,216 |

Descriptor allocation occurs before duplicate rejection. Small invalid calls
therefore cost more instructions and memory, and the 127-entry rejection still
allocates more despite its small instruction reduction. Successful cases save
1,096–17,336 allocated B; the code-size increase above also remains part of the
cost. [BLS source reasoning, tests and complete cohort](bls12-381/README.md).

## Memory: what is and is not measured

Allocation is cumulative **managed-heap allocation during the public call**,
including temporary objects and returned values. It does not measure native
stack scratch, retained live data or total canister memory. Every final case
has zero synchronous reclamation. A verifier allocating 32 B still uses
arithmetic workspaces in linear-memory stack space.

Untimed snapshots sample occupied heap and Wasm capacity after setup, after the
operation message and after four more forced GC increments. The result remains
reachable. Occupancy includes runtime state and garbage; four increments need
not finish collection, and these are not true peak or live-memory measurements.
All final sampled Wasm capacities are 128 MiB. For eight-message IC aggregation,
post-operation occupied heap is 5,521,632 → 5,503,440 B; the eight-message
Ethereum distinct case is 5,835,528 → 5,818,808 B. Initial module heap differs
slightly, so these occupancy differences are not allocation savings to sum.

The [independent ML-DSA stack audit](../../../tests/crypto-audit/round3/ml-dsa/stack/README.md)
bounds additional native shadow stack for the pinned runtime at **134,016 B
for key generation, 129,776 B for signing and 93,696 B for verification**.
These exclude the Motoko caller and engine stack. The complete direct-call
graph is acyclic and has fixed frames; these are conservative bounds for the
exact audited runtime hash, not general bounds for another build or a whole
canister. The report also records the upstream zeroization and rejection-counter
limitations; managed caller-owned secret Blobs are not erased by the plugin.

## Validation and reproducible evidence

The [integrated gate report](validation/report.json) records **54 native tests,
14 fixtures through source/IR/lowered-IR/Wasm execution and validation,
7 compiler rejection fixtures, 62 Ash methods, and packaging checks for all
23 plugins** passing. Composition retains inputs and outputs from the linked
algorithms across 13 message boundaries and requires more than 4 MiB of actual
reclamation. Separate vector audits check RFC8032/BIP340/RFC6979,
Wycheproof, OpenSSL and official NIST ACVP answers. Tests do not amount to
cryptographic certification, comprehensive constant-time proof or secret erasure.
The initial composition test typo and manifest metadata failure are retained
in the validation record; final measurements use their corrected versions.

- [All 98 final cases, individual trials and memory snapshots](../results/round3-final-direct/results.json), with [build/source/toolchain hashes](../results/round3-final-direct/build.json).
- [Fresh Motoko comparison trials](../results/round3-motoko-verification-controls/results.json).
- [Measurement and restoration protocol](README.md), including strict input, toolchain, oracle and cohort identity checks.
- [Portable source archive](source-store.tar.gz), [source index](source-store.json), and [integrity verification](validation/source-integrity.json): **17 stages**, deduplicated into **12,194,315 bytes** (12.2 MB). Exact source and vendor/test-vector content is portable; compiler binaries, Wasm and object files remain local, with their hashes pinned in retained metadata. Successful source restoration does not make failed exploratory measurements valid.

The three-trial medians describe these deterministic examples, not input-wide
worst cases or mainnet wall-clock latency. PocketIC measurement was exclusive
within this team, without claiming an otherwise idle host. Prepared-key SDK
experiments are separate and contribute nothing to this round's numbers.
