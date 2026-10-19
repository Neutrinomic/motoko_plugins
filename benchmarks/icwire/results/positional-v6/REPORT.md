# Final positional codec benchmark

**Both strict instruction gates passed all 105 workloads**, separately for encoding and decoding, against native Candid and CandidX encoding/native decoding. The complete run contains **1,893 observations** across three fresh-canister trials. Every repeated instruction count was identical; no observation failed, reclaimed memory inside the timed interval, or grew linear memory. This demonstrates the measured fixture matrix, not a universal speed guarantee.

[Raw observations](results.json) · [Every phase and allocation](summary.csv) · [Complete instruction table](summary.md) · [Build provenance](build.json) · [Validation evidence](validation.json) · [Public API test output](public-tests.txt)

ICWire uses the exact externally known schema: raw positional fields, no header, field identifiers, record framing, or type table. The output bytes are unchanged from positional-v3. The final [v3 comparison](compare-v3.txt) and [v5 comparison](compare-v5.txt) verify identical actor source, fixture manifest, runner, compiler/RTS, repetitions, PocketIC version, and output hashes. Repeated native and CandidX control counts are unchanged.

Representative instruction speedups (baseline instructions divided by ICWire instructions):

| Workload | Encode vs native | Encode vs CandidX | Decode vs native |
| --- | ---: | ---: | ---: |
| takt-event-32 | 1.014× | 1.010× | 1.121× |
| rechain-actions-1024 | 1.190× | 4.082× | 2.440× |
| reactor-frames-1024 | 1.231× | 3.134× | 2.232× |
| nat64-array-4096 | 1.959× | 1.045× | 2.457× |
| bool-array-4096 | 2.786× | 1.069× | 2.897× |
| small-nat-array-4096 | 1.718× | 1.613× | 1.338× |
| float-array-4096 | 1.833× | 1.053× | 1.381× |
| float32-array-4096 | 1.771× | 1.042× | 2.113× |

Selected absolute counts and bytes:

| Workload | Native encode | CandidX encode | ICWire encode | Native decode | ICWire decode | Bytes native / ICWire |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| scalar-nat64 | 1,114 | 706 | 689 | 81,870 | 80,514 | 15 / 8 |
| takt-event-32 | 84,177 | 83,798 | 82,984 | 93,967 | 83,860 | 151 / 78 |
| rechain-actions-32 | 146,019 | 408,098 | 131,376 | 371,175 | 178,511 | 1,518 / 1,319 |
| rechain-actions-1024 | 2,748,635 | 9,432,570 | 2,310,623 | 9,456,600 | 3,875,810 | 43,407 / 41,968 |
| reactor-frames-64 | 537,522 | 1,164,508 | 492,049 | 1,015,934 | 537,462 | 6,860 / 6,516 |
| reactor-frames-1024 | 5,539,274 | 14,099,994 | 4,498,872 | 13,477,261 | 6,036,929 | 107,133 / 104,869 |
| recursive-chain-63 | 102,688 | 665,393 | 98,475 | 366,055 | 279,490 | 591 / 568 |
| recursive-tree-63 | 111,889 | 262,409 | 106,801 | 222,776 | 135,424 | 577 / 536 |
| nat64-array-4096 | 720,453 | 384,232 | 367,802 | 1,086,441 | 442,140 | 32,779 / 32,770 |
| small-nat-array-4096 | 813,509 | 764,028 | 473,613 | 1,237,737 | 925,098 | 4,107 / 4,098 |
| bool-array-4096 | 499,013 | 191,462 | 179,128 | 912,105 | 314,889 | 4,107 / 4,098 |
| big-nat-array-4096 | 24,179,909 | 24,175,228 | 24,121,933 | 44,658,705 | 33,758,862 | 77,835 / 77,826 |
| mixed-int-array-4096 | 12,184,586 | 12,201,990 | 11,956,168 | 16,964,383 | 11,388,766 | 30,042 / 30,033 |
| text-array-4096 | 1,518,917 | 1,401,852 | 1,258,445 | 3,406,057 | 3,038,250 | 22,539 / 22,530 |
| float-array-4096 | 704,069 | 404,712 | 384,190 | 1,889,769 | 1,368,371 | 32,779 / 32,770 |
| float32-array-4096 | 687,685 | 404,712 | 388,286 | 1,141,865 | 540,462 | 16,395 / 16,386 |
| blob-65536 | 612,404 | 386,515 | 386,445 | 388,361 | 386,357 | 65,548 / 65,539 |

Relative to the earlier v3 baseline, the targeted optimizations produce:

| Workload / operation | V3 instructions | Final instructions | Reduction |
| --- | ---: | ---: | ---: |
| small-nat-array-4096 / encode | 735,310 | 473,613 | 35.59% |
| bool-array-4096 / decode | 572,841 | 314,889 | 45.03% |
| float-array-4096 / encode | 490,702 | 384,190 | 21.71% |
| float-array-4096 / decode | 1,773,737 | 1,368,371 | 22.85% |
| float32-array-4096 / encode | 494,798 | 388,286 | 21.53% |
| float32-array-4096 / decode | 941,737 | 540,462 | 42.61% |
| big-nat-array-4096 / decode | 38,129,976 | 33,758,862 | 11.46% |
| mixed-int-array-4096 / decode | 13,072,549 | 11,388,766 | 12.88% |
| reactor-frames-64 / encode | 506,770 | 492,049 | 2.90% |

V6 further improves small-Nat array encoding by 20.0% and the medium-integer array decoders by approximately 2.8% relative to V5. The new compact-value branch adds one instruction to the heap-backed root Nat encoder and five to the root Int encoder; both still beat CandidX. The full comparisons retain all other tiny regressions and unchanged cases.

Across these fixtures, native/ICWire encode instruction ratios range from 1.00189× to 2.786× (median 1.0069×).
Across these fixtures, native/ICWire decode instruction ratios range from 1.00519× to 3.722× (median 1.0177×).

Fresh-message memory-page accounting is included without subtraction and can dominate small inputs. The [methodology](../../README.md) documents the control interval, unchanged-memory probe and ineffective warm-capacity reservation. Native/CandidX and ICWire are measured repeatedly within the same combined actor build.

Medium-integer decoding trades managed allocation for fewer instructions:

| Decode workload | Native allocated bytes | ICWire allocated bytes | ICWire / native |
| --- | ---: | ---: | ---: |
| big-nat-array-4096 | 622,672 | 1,835,136 | 2.95× |
| mixed-int-array-4096 | 278,584 | 584,608 | 2.10× |
| text-array-4096 | 163,920 | 164,040 | 1.00× |

Allocation includes temporaries and output, not just retained size. Compared with V3, medium-integer allocation falls by approximately 14%, but remains above native. The reclaimed-byte counter remained unchanged in each timed interval; that observation does not remove later garbage-collection costs. This implementation prioritizes instruction cost over code size and temporary allocation.

| Isolated actor, same 105 fixtures | Wasm bytes |
| --- | ---: |
| [Candid encode + decode](../positional-v6-size-candid/build.json) | 666,224 |
| [CandidX encode + native decode](../positional-v6-size-candidx/build.json) | 757,578 |
| [ICWire encode + decode](../positional-v6-size-icwire/build.json) | 835,596 |
| Combined actor with all codecs | 1,425,622 |

The isolated ICWire actor is 25.4% larger than native and 10.3% larger than CandidX. The final combined actor adds 47,980 bytes versus V3 and 38,721 versus V5. Each isolated actor passed eight correctness workloads plus the control interval. Sizes include deterministic fixtures, queries and public Candid interfaces; they are not standalone codec sizes. Isolated timings do not replace the combined-actor comparisons.

The comparable suite uses Null/unit array lengths 0, 1, 512 and 1,024. Earlier raw archives retain native decoder rejection at larger zero-width sizes. These are capacity findings, not speed wins; native expansion limits were unchanged. Historical tagged-record archives precede the selected positional contract and do not describe the final codec.
