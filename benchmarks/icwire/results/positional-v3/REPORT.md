# Positional v3 baseline

The strict native-win gate passed all **105 workloads**, for both encoding and decoding, across **1,893 observations** (three fresh-canister trials). Instruction counts were identical across repetitions. There were no failed observations, no reclamation inside a timed interval, and no linear-memory growth. These results cover this explicit fixture matrix; they are not a universal speed guarantee.

This is the frozen baseline for the subsequent optimization requested by the user. The wire is raw positional and requires the exact schema. Historical tagged archives do not describe this format.

[Raw observations](results.json) · [Every phase, allocations and bytes](summary.csv) · [Complete instruction table](summary.md) · [Build and source hashes](build.json) · [Public API validation](public-tests.txt)

| Workload | Candid encode | ICWire encode | Candid decode | ICWire decode | Bytes Candid / ICWire |
| --- | ---: | ---: | ---: | ---: | ---: |
| scalar-nat64 | 1,114 | 689 | 81,870 | 80,514 | 15 / 8 |
| takt-event-32 | 84,177 | 83,372 | 93,967 | 84,186 | 151 / 78 |
| rechain-actions-32 | 146,019 | 136,373 | 371,175 | 181,094 | 1,518 / 1,319 |
| reactor-frames-64 | 537,522 | 506,770 | 1,015,934 | 547,593 | 6,860 / 6,516 |
| recursive-chain-63 | 102,688 | 98,475 | 366,055 | 279,300 | 591 / 568 |
| recursive-tree-63 | 111,889 | 106,801 | 222,776 | 135,329 | 577 / 536 |
| nat64-array-4096 | 720,453 | 367,806 | 1,086,441 | 442,139 | 32,779 / 32,770 |
| big-nat-array-4096 | 24,179,909 | 24,146,510 | 44,658,705 | 38,129,976 | 77,835 / 77,826 |
| mixed-int-array-4096 | 12,184,586 | 12,173,272 | 16,964,383 | 13,072,549 | 30,042 / 30,033 |
| text-array-4096 | 1,518,917 | 1,274,830 | 3,406,057 | 3,042,345 | 22,539 / 22,530 |
| blob-65536 | 612,404 | 386,445 | 388,361 | 386,357 | 65,548 / 65,539 |

Native instruction ratios range from 1.00093–2.786× for encoding and 1.00519–3.722× for decoding. Fresh-message page accounting is included without subtraction; it can dominate small values. See the [methodology](../../README.md) for the unchanged-memory and warm-capacity probes.

ICWire encoding still uses more instructions than CandidX encoding on three cases: `all-fixed-primitives` (82,374 versus 82,291), `float-array-4096` (490,702 versus 404,712), and `float32-array-4096` (494,798 versus 404,712). Every other encoding case beats CandidX; every ICWire decoding case beats native decoding of CandidX bytes.

Medium-integer decoding improves instruction counts by constructing through SDK integer operations, at a managed-allocation cost:

| Decode workload | Native allocated bytes | ICWire allocated bytes | ICWire / native |
| --- | ---: | ---: | ---: |
| big-nat-array-4096 | 622,672 | 2,129,984 | 3.42× |
| mixed-int-array-4096 | 278,584 | 682,824 | 2.45× |
| text-array-4096 | 163,920 | 164,048 | 1.00× |

Allocations include temporaries and output; they are not a retained-size measurement. The unchanged reclaimed-byte counter does not remove the later collection cost of extra garbage.

| Isolated actor, same 105 fixtures | Wasm bytes |
| --- | ---: |
| Candid encode + decode | 666,224 |
| CandidX encode + native decode | 757,578 |
| ICWire encode + decode | 787,616 |
| Combined actor with all three | 1,377,642 |

The ICWire isolated actor is 18.2% larger than the native actor and 4.0% larger than the CandidX actor. These sizes include fixture construction, correctness queries, and public Candid interfaces; they are not standalone codec sizes. Each isolated build passed a six-workload correctness screen plus the control interval. Their timing is not substituted into the combined-actor comparisons.

The full comparable suite uses Null/unit array lengths 0, 1, 512, and 1,024. Earlier raw archives preserve native decoder rejection at larger zero-width sizes; such rejections are capacity observations, not speed wins. No native expansion limit was changed.
