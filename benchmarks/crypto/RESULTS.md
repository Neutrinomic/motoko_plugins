# Crypto benchmark results

Final integrated artifact measurements.

**223 of 224 implementation/workload combinations passed**, each with three fresh-canister trials. The remaining baseline fails the official BLAKE3 16 KiB output and contributes no ratio. All successful selected measurements were checked against independent exact output bytes. Full numeric data, failure status, semantics and stage provenance are in [measurements.csv](summary/measurements.csv), [comparisons.csv](summary/comparisons.csv) and [summary.json](summary/summary.json).

The ratio below is Mops instructions divided by native instructions. Values below 1 mean the native API costs more. Canister Wasm size and allocation are measured separately; lower instruction counts do not imply smaller Wasm. See [methodology and reproduction](README.md).

## Representative primitives

| Workload | Native instructions | Mops instructions | Ratio | Allocated bytes native / Mops | Canister KiB native / Mops |
| --- | --- | --- | --- | --- | --- |
| BLAKE3, 1 KiB | 35,930 | 3,485,872 | 97.02× | 56 / 135,536 | 268.9 / 292.4 |
| BLAKE3 keyed, 1 KiB | 36,178 | 3,492,129 | 96.53× | 88 / 135,944 | 270.5 / 293.4 |
| SHA512, 1 KiB | 61,192 | 182,086 | 2.98× | 88 / 4,544 | 259.5 / 429.6 |
| RIPEMD160, 32 bytes | 3,845 | 47,388 | 12.32× | 48 / 1,216 | 249.4 / 280.7 |
| HMAC-SHA512, 64 bytes | 33,004 | 168,729 | 5.11× | 88 / 14,720 | 275.9 / 434.0 |
| HMAC-SHA512 prepared, 64 bytes | 19,620 | 59,322 | 3.02× | 88 / 4,000 | 278.0 / 434.2 |
| Base58 encode, 82 bytes | 32,903 | 228,644 | 6.95× | 280 / 2,864 | 242.8 / 245.9 |
| Bech32m decode, 53 values | 12,614 | 78,834 | 6.25× | 344 / 3,688 | 245.6 / 253.9 |
| secp256k1 ECDSA verify | 10,093,699 | 109,871,125 | 10.89× | 56 / 9,713,568 | 437.8 / 611.2 |
| P256 ECDSA verify | 22,609,363 | 324,683,945 | 14.36× | 32 / 24,513,360 | 323.9 / 611.1 |
| BLS map to G1 | 11,894,062 | 81,244,183 | 6.83× | 104 / 3,339,696 | 760.1 / 260.2 |
| BLS map to G2 | 49,488,489 | 496,609,072 | 10.03× | 152 / 19,298,680 | 760.2 / 257.3 |
| BLS G2 MSM, 128 distinct points | 7,476,866,125 | 20,182,625,551 | 2.70× | 30,896 / 813,279,488 | 776.3 / 429.3 |

Native curve APIs validate serialized inputs. Mops ECDSA fixtures prepare keys outside measurement. BLS MSM includes native compressed-point/subgroup validation while its Mops baseline starts from trusted in-memory points. These are complete public API comparisons, not isolated arithmetic kernels.

## Bitcoin composition

| Workflow | Native instructions | Mops instructions | Ratio |
| --- | --- | --- | --- |
| HASH160 compressed pubkey | 9,410 | 84,381 | 8.97× |
| P2PKH validating public API | 615,495 | 204,488 | 0.33× |
| P2PKH trusted-byte payload API | 40,172 | 204,488 | 5.09× |
| P2WPKH validating public API | 602,688 | 222,766 | 0.37× |
| P2WPKH trusted-byte payload API | 27,367 | 222,766 | 8.14× |
| BIP32 public child + xpub encoding | 8,265,639 | 147,502,352 | 17.85× |
| BIP86 account xpub → receive address | 22,870,034 | 469,787,471 | 20.54× |
| Serialize transaction, 100 inputs | 3,683,665 | 4,073,497 | 1.11× |
| Legacy sighashes, all 100 inputs | 400,819,144 | 724,751,320 | 1.81× |
| Taproot sighashes, all 100 inputs | 600,914,344 | 759,080,220 | 1.26× |
| Legacy sighash + ECDSA verify | 10,193,289 | 113,272,055 | 11.11× |

The validating address APIs are slower because the Mops convenience routines hash bytes without curve validation. The explicit trusted-byte payload rows perform equivalent HASH160 and address encoding without changing the validating API contract. The BIP86 row includes account parsing, two public child derivations, empty-tree TapTweak and Bech32m encoding.

Prepared transaction hashers amortize common hashes across inputs. Cold preparation is included in each measured batch. Mops has no BIP143 implementation to compare.

| Native 100-input workload | Variant | Instructions | Allocated bytes |
| --- | --- | --- | --- |
| bitcoin-bip143-all-cache-100-inputs | native | 398,305,644 | 18,044,824 |
| bitcoin-bip143-all-cache-100-inputs | native-prepared | 14,840,351 | 596,312 |
| bitcoin-taproot-default-cache-100-inputs | native | 600,914,344 | 24,248,024 |
| bitcoin-taproot-default-cache-100-inputs | native-prepared | 16,982,261 | 620,328 |

## Validation cost and absolute-only APIs

Trusted BLS addition is not equivalent to parsing and subgroup-checking public input. Native G1/G2 addition costs about 28.4M/75.7M instructions; trusted Mops arithmetic costs about 0.42M/0.98M. Including validation and encoding changes the comparison: the retained validated G1 baseline costs about 329M, and G2 about 168M. G2 uses EIP-style uncompressed baseline input versus native compressed input; this wire-format difference remains explicit.

| Native operation | Instructions | Allocated bytes |
| --- | --- | --- |
| secp256k1_sign_rfc6979_fast | 7,452,214 | 120 |
| p256_sign_rfc6979_fast | 13,457,023 | 120 |
| secp256k1_schnorr_sign_fast | 25,455,494 | 120 |
| secp256k1_schnorr_verify_fast | 9,928,829 | 56 |
| bls12_381_verify_ic_valid_fast | 236,236,297 | 39,280 |
| bls12_381_verify_ethereum_valid_fast | 286,386,472 | 39,280 |
| bls12_381_hash_to_g1_fast | 15,834,341 | 104 |
| bls12_381_hash_to_g2_fast | 65,993,098 | 152 |

Mops ECDSA signing takes a supplied nonce, while native signing uses RFC6979; those costs are not presented as a direct speedup. Schnorr and complete IC/Ethereum BLS verification have no corresponding API in the selected Mops packages. Valid and wrong-message BLS signatures were independently checked.

## Optimization experiments

Exact before/after artifact identities and instruction, allocation and Wasm deltas are in [optimizations.json](summary/optimizations.json).

Accepted changes were measured before and after: RIPEMD160 fixed 32-byte hashing cuts roughly 11% from the HASH160-sized kernel; Bech32 reverse-table decoding cuts roughly 3–4% while shrinking its runtime; secp256k1/P256 RFC6979 signing avoids an unused public-key multiplication and saves roughly 46%/45%; BLS windowed MSM saves up to roughly 65% on the retained matrix. Empty-input digest constants reduce BLAKE3, SHA512/SHA384 and RIPEMD160 overhead.

Prepared HMAC keys cut native 64-byte authentication costs by about 36% (SHA256) and 41% (SHA512). Prepared transaction hashing reduces instruction counts by factors of about 27 (BIP143) and 35 (Taproot) across 100 inputs, with cold setup counted.

SHA512 and HMAC compression-unrolling trials were rejected: modest instruction savings did not justify their larger Wasm and maintenance burden. Their frozen experiments remain available under `results/sha512-native-candidate` and `results/hmac-unrolled256-*`; the selected final results retain the pinned RustCrypto kernels.

## Correctness findings and retained evidence

- Mops BLAKE3 0.1.2 returns the wrong official digest for the 16 KiB patterned input. Its source lacks complete chunk-tree handling. Context-based derivation is also excluded because the package ignores the context. Correct single-chunk and keyed fixtures pass.
- An early benchmark typo added a question mark to the official BLAKE3 key, making it 33 bytes. Native correctly rejected it. The corrected 32-byte fixture supersedes those measurements; this was a harness defect, not a keyed-hash implementation failure.
- Early build/setup failures are retained in their original stage logs, including the missing published BLAKE3 base dependency and two incorrect Bitcoin baseline call adapters. Corrected rows pass all three trials.
- Every selected stage records compiler/RTS and plugin hashes, source snapshots, dependency hashes, Wasm identity and independent output hashes. `source-store.tar.gz` deduplicates exact source bytes; per-stage `source-map.json` files and the restore utility reconstruct them. Executable artifacts remain locally available but are excluded from version control.
