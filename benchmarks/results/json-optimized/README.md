# JSON optimization measurements

PocketIC instruction costs for the same typed Motoko inputs, source actor, compiler and frozen runner. Three trials each; every count was identical, all outputs match the independent oracle and the baseline bytes, and no synchronous GC occurred. Allocation is cumulative heap allocation, including temporary scratch, not retained memory. Decoder output-size fields describe the two-byte validation reply.

| Workload | Before instructions | After instructions | Reduction | Before allocated bytes | After allocated bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| json-record-encode | 15,105 | 11,270 | 25.39% | 936 | 768 |
| json-record-decode | 20,703 | 17,372 | 16.09% | 1,304 | 872 |
| json-records-1024-encode | 10,652,793 | 7,714,028 | 27.59% | 226,640 | 193,864 |
| json-records-1024-decode | 30,899,899 | 23,844,154 | 22.83% | 1,371,360 | 129,136 |
| json-blob-64k-encode | 3,257,044 | 3,257,056 | -0.00% | 175,136 | 175,160 |
| json-blob-64k-decode | 7,353,704 | 3,257,270 | 55.71% | 218,840 | 131,456 |

Changes: borrow unescaped scalar input and validated raw object keys; decode escaped keys lazily for equality/path operations; reuse a key stack for objects with at most eight keys while keeping tree-based duplicate detection for larger objects; format fixed-width integers and indices into stack storage; scan ordinary string bytes eight at a time; write base64 decoding directly to its final scratch buffer; precompute escaped object-key punctuation during specialization.

The audit also found and fixed error-path parity for array item quota preflight and tagged optional encoding. The key-allocation regression covers 64 nested arrays containing a 256 KiB object key, including an escaped spelling: cumulative native scratch fell from 35,147,632/69,226,417 bytes to 264,825/264,831 bytes in the independent audit reproduction.

Reports: `baseline.json`, `final.json`, `summary.csv`, `provenance.json`; actor source and manifest under `bench/`; frozen harness `run.mjs`. Artifact Wasm hashes are embedded in both raw reports.
