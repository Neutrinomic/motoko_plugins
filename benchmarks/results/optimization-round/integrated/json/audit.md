# Independent integrated JSON review

No unresolved finding. This bounded review checked the final archive and headline comparisons after integration with clean compiler `c320bf90d0b63a058b5de2c41a42c96e8b82243f`. It did not change production source, rebuild artifacts, or rerun test suites. The earlier [plugin audit](../../json/audit.md) remains the source/runtime review.

Independently verified the actual canonical compiler binary (`722ba089…`), package source and artifact hashes, both generated Wasm actors, report hashes, and value-corpus artifact hashes against provenance. The runtime remains byte-identical (`90515e97…`) to the audited plugin. Actor source, input manifests, and runner bytes match the original comparisons exactly.

Checked all **39 phase cohorts × three trials × three versions** against the original baseline, audited plugin, and integrated reports. Coverage is complete with no duplicate trial/phase entries. Every successful cohort has deterministic counters, matching output hashes/sizes across versions, and zero measured synchronous reclamation. The comparison CSV agrees with raw records. All successful native-library counters are unchanged. Both serde implementations retain their 64 KiB text-decoder stack overflows in all trials: **six recorded failures per version**, with no timing assigned to failed calls.

SDK effects match the array-construction change: focused singleton decode saves nine instructions, 1,024-record decode saves 10,239, and nested-array decode saves 10,527 compared with the audited plugin. Empty-array decode adds one instruction (1,363 → 1,364), still below the original baseline's 1,379. Allocation is unchanged from the audited plugin in every successful phase. The original **eight-byte increases** for small record encode/decode and the small error remain explicit tradeoffs.

Verified the root README headline rows and independently selected the successful native library with the lowest instruction count. Allocation comes from that same library:

| 1,024-record operation | Native instructions / allocated bytes | Plugin instructions / allocated bytes | Ratio |
| --- | ---: | ---: | ---: |
| Encode (`json 1.4.0`) | 53,258,267 / 7,145,616 | 5,081,644 / 194,176 | 10.48× |
| Decode (`serde 3.5.0`) | 763,222,636 / 136,203,896 | 18,251,729 / 172,816 | 41.82× |

The slower native `json` decoder's 30,305,226,309 instructions remain recorded. Counts cover complete typed operations; input setup, validation, reply conversion, and message-end GC remain outside measurement. Allocated bytes measure cumulative pressure, not retained memory or wall time.

Reviewed passing integration logs for all ten permanent Motoko fixtures and 765 independent scalar/binary/Unicode cases, with matching final package hashes. The unchanged runtime's earlier 20 Rust tests and 9,263 syntax cases are referenced honestly as prior evidence. Historical archives were not modified.
