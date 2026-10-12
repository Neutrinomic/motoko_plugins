# Base58 optimization round two

Candidate: `_build/crypto-optimization-round2/base58-limbs-v3`. Root implementation is unchanged pending independent audit and promotion.

Each of the 68 paired cases ran on three fresh canisters. Python integer conversion and hashlib supply independent exact outputs. Every trial matched, instruction/allocation counts were repeatable, and managed allocation was unchanged. Inputs are prepared and result serialization performed outside the measured interval. Wasm sizes are whole canister artifacts.

| Case | Baseline instructions | Candidate instructions | Speedup | Allocated bytes | Wasm delta |
|---|---:|---:|---:|---:|---:|
| base58-encode-0-pattern | 785 | 764 | 1.027x | 56 | +1,640 |
| base58-decode-0-pattern | 936 | 918 | 1.020x | 80 | +1,640 |
| base58-encode-1-pattern | 1,081 | 1,022 | 1.058x | 64 | +1,640 |
| base58-decode-1-pattern | 1,211 | 1,178 | 1.028x | 96 | +1,640 |
| base58-encode-25-pattern | 6,395 | 4,409 | 1.450x | 128 | +1,640 |
| base58-decode-25-pattern | 4,986 | 4,209 | 1.185x | 152 | +1,640 |
| base58-encode-25-leading | 4,607 | 3,485 | 1.322x | 120 | +1,640 |
| base58-decode-25-leading | 3,671 | 3,547 | 1.035x | 144 | +1,640 |
| base58-encode-25-ff | 6,547 | 4,513 | 1.451x | 128 | +1,640 |
| base58-decode-25-ff | 5,023 | 4,265 | 1.178x | 152 | +1,640 |
| base58-encode-25-zero | 1,468 | 1,449 | 1.013x | 120 | +1,640 |
| base58-decode-25-zero | 2,160 | 2,141 | 1.009x | 144 | +1,640 |
| base58-encode-32-pattern | 8,687 | 5,293 | 1.641x | 144 | +1,640 |
| base58-decode-32-pattern | 6,261 | 5,246 | 1.193x | 160 | +1,640 |
| base58-encode-78-pattern | 32,649 | 15,509 | 2.105x | 272 | +1,640 |
| base58-decode-78-pattern | 19,414 | 13,503 | 1.438x | 272 | +1,640 |
| base58-encode-82-pattern | 33,228 | 16,643 | 1.997x | 280 | +1,640 |
| base58-decode-82-pattern | 19,720 | 14,301 | 1.379x | 280 | +1,640 |
| base58-encode-82-leading | 18,379 | 10,465 | 1.756x | 272 | +1,640 |
| base58-decode-82-leading | 13,175 | 10,410 | 1.266x | 272 | +1,640 |
| base58-encode-82-ff | 33,503 | 16,744 | 2.001x | 280 | +1,640 |
| base58-decode-82-ff | 19,808 | 14,328 | 1.382x | 280 | +1,640 |
| base58-encode-82-zero | 2,516 | 2,497 | 1.008x | 256 | +1,640 |
| base58-decode-82-zero | 4,668 | 4,649 | 1.004x | 256 | +1,640 |
| base58-encode-256-pattern | 244,569 | 97,815 | 2.500x | 760 | +1,640 |
| base58-decode-256-pattern | 128,381 | 68,406 | 1.877x | 688 | +1,640 |
| base58-encode-256-leading | 120,888 | 51,863 | 2.331x | 728 | +1,640 |
| base58-decode-256-leading | 69,263 | 41,158 | 1.683x | 656 | +1,640 |
| base58-encode-256-ff | 245,443 | 98,136 | 2.501x | 760 | +1,640 |
| base58-decode-256-ff | 128,349 | 68,391 | 1.877x | 688 | +1,640 |
| base58-encode-256-zero | 5,714 | 5,695 | 1.003x | 664 | +1,640 |
| base58-decode-256-zero | 12,324 | 12,305 | 1.002x | 592 | +1,640 |
| base58-encode-1024-pattern | 3,481,981 | 1,260,562 | 2.762x | 2,864 | +1,640 |
| base58-decode-1024-pattern | 1,699,731 | 747,885 | 2.273x | 2,504 | +1,640 |
| base58-encode-4096-pattern | 53,842,476 | 19,001,036 | 2.834x | 11,304 | +1,640 |
| base58-decode-4096-pattern | 25,894,036 | 10,608,211 | 2.441x | 8,272 | +1,640 |
| base58-encode-4096-leading | 24,113,257 | 8,566,599 | 2.815x | 10,800 | +1,640 |
| base58-decode-4096-leading | 11,680,575 | 4,873,138 | 2.397x | 8,272 | +1,640 |
| base58-encode-4096-ff | 53,855,021 | 19,005,427 | 2.834x | 11,304 | +1,640 |
| base58-decode-4096-ff | 25,900,002 | 10,610,608 | 2.441x | 8,272 | +1,640 |
| base58-encode-4096-zero | 76,293 | 76,274 | 1.000x | 9,800 | +1,640 |
| base58-decode-4096-zero | 181,284 | 181,265 | 1.000x | 8,272 | +1,640 |
| base58check-encode-0 | 7,985 | 7,806 | 1.023x | 320 | +1,640 |
| base58check-decode-0 | 8,089 | 7,932 | 1.020x | 328 | +1,640 |
| base58check-encode-21 | 21,777 | 19,791 | 1.100x | 576 | +1,640 |
| base58check-decode-21 | 19,543 | 18,766 | 1.041x | 576 | +1,640 |
| base58check-encode-78 | 63,232 | 46,647 | 1.356x | 1,240 | +1,640 |
| base58check-decode-78 | 46,448 | 41,029 | 1.132x | 1,216 | +1,640 |
| base58check-encode-252 | 319,030 | 172,276 | 1.852x | 3,280 | +1,640 |
| base58check-decode-252 | 192,084 | 132,109 | 1.454x | 3,192 | +1,640 |
| base58check-encode-4092 | 54,867,337 | 20,025,897 | 2.740x | 48,384 | +1,640 |
| base58check-decode-4092 | 26,743,019 | 11,457,194 | 2.334x | 45,336 | +1,640 |
| base58-encode-2-pattern | 1,279 | 1,172 | 1.091x | 64 | +1,640 |
| base58-decode-2-pattern | 1,380 | 1,296 | 1.065x | 96 | +1,640 |
| base58-encode-4-pattern | 1,487 | 1,332 | 1.116x | 64 | +1,640 |
| base58-decode-4-pattern | 1,551 | 1,398 | 1.109x | 96 | +1,640 |
| base58-encode-7-pattern | 1,897 | 1,648 | 1.151x | 80 | +1,640 |
| base58-decode-7-pattern | 2,006 | 1,606 | 1.249x | 104 | +1,640 |
| base58-encode-8-pattern | 2,442 | 1,745 | 1.399x | 80 | +1,640 |
| base58-decode-8-pattern | 2,174 | 2,154 | 1.009x | 104 | +1,640 |
| base58-encode-9-pattern | 2,567 | 2,119 | 1.211x | 80 | +1,640 |
| base58-decode-9-pattern | 2,215 | 2,227 | 0.995x | 112 | +1,640 |
| base58-encode-10-pattern | 2,660 | 2,208 | 1.205x | 80 | +1,640 |
| base58-decode-10-pattern | 2,317 | 2,297 | 1.009x | 112 | +1,640 |
| base58-encode-11-pattern | 2,819 | 2,366 | 1.191x | 80 | +1,640 |
| base58-decode-11-pattern | 2,453 | 2,384 | 1.029x | 112 | +1,640 |
| base58-encode-12-pattern | 2,948 | 2,324 | 1.269x | 88 | +1,640 |
| base58-decode-12-pattern | 2,512 | 2,622 | 0.958x | 112 | +1,640 |

Two transition cases regress: decoding the nine-byte payload adds 12 instructions (0.54%), and the twelve-byte payload adds 110 instructions (4.38%). The other 66 cases improve. The candidate is recommended for the much larger address, extended-key and bounded bulk gains; these small regressions and the code-size increase are explicit tradeoffs.

Runtime Wasm grows from 3,099 to 4888 bytes. Bounded stack scratch replaces repeated byte/digit carry loops with wider limbs, without additional managed allocation. Empty/zero-only and small arbitrary inputs avoid limb scratch.

Earlier candidates are retained in `round2-base58-limbs-v1` and `round2-base58-limbs-v2`. V1 had small-input regressions; v2 added scalar conversion; v3 avoids redundant zero-only scalar conversion. No input-specific precomputed outputs are used.

Validation: all five original native tests plus seven baseline/differential tests pass; the independent differential suite exercises 1,665 byte strings, capacities, output sentinels, padding, input preservation, alphabet errors and quota precedence. All eight public source/IR/lowered/Wasm run/fail/trap fixtures passed with unchanged goldens, and all six Base58 Ash methods passed. The independent round-two auditor passed 1,657 Python bigint oracle vectors, all 16 pointer alignment residues, read-only input/guarded output pages, error precedence and ASan/debug execution; evidence is under `_build/crypto-optimization-round2/central-audit/base58`.

Reproduction: `python3 benchmarks/crypto/round2/base58-workloads/generate.py`; run the frozen baseline with `cases.json` and `small-cases.json` through `round2/run-stage.py`, and the selected candidate with `broad-cases.json`, `--root _build/crypto-optimization-round2/base58-limbs-v3 --plugin base58`. Use fresh stage names; results are immutable. Run this comparator after collecting the named stages.

Machine-readable hashes, per-case allocation and Wasm sizes are in `comparison.json`.
