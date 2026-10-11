# Independent JSON optimization audit

Reviewed the complete JSON plugin and the delta from `093957ad1ba611384a8b998c83bd86c75b585e4f`, with compiler `f1ccbba5e445df9db03bbc35be557187ade9b436` frozen. No correctness defect was found. Final runtime SHA-256: `90515e9744aed97da77ecaca14d9729c6f7c62b6911391de9920c8ced313545e`.

The path stack copies the existing borrowed `Key` descriptor or an array index. Key bytes belong to validated input or compiler field literals, never to the replaceable scalar buffer. The existing synchronous, callback-free, no-GC borrowing interval keeps those bytes valid until the first error materializes an owned path. UTF-8 decoding, surrogate handling, `~0`/`~1` escaping, empty/numeric keys, nested pre-scans, first-error preservation, and unwind behavior remain consistent with the reference evaluator. `skip_number` now uses the same nonallocating lexer as typed numbers. Direct root-limit initialization preserves kind, message, empty path, and zero offset.

During final review, an error under a 256 KiB key exposed geometric path-buffer growth: 1,048,952 native scratch bytes versus baseline 524,610/524,617 (plain/escaped). One `reserve(key.text.len())` in error rendering fixes it without changing successful traversal. Independently rerunning the baseline, rejected candidate, and fixed probes reproduced all counts; the fixed version uses 262,537/262,543 bytes. A permanent regression checks both exact decoded paths and the allocation bound.

Schema validation, recursive visitors, tagged options, tuple lengths, duplicate/unknown fields, quotas, managed `#ok`/`#err` construction, and result copying before context destruction were also reviewed. The change adds no public API, ABI change, persistent state, generic framework, or alternate parser.

Reviewed final validation logs and their source/artifact hashes:

- 20 Rust runtime tests and all 10 permanent Motoko fixtures passed, including rejected types, exact nested escaped-key diagnostics, limits, retained results, early failures, forced GC, and heap evacuation.
- Existing independent corpora passed: 604 scalar and 161 binary/Unicode cases through source, IR, lowered IR, and Wasm; 9,263 syntax cases against the Python oracle.
- Both nested large-key allocation probes used 6,336 native scratch bytes. The earlier same-runtime baseline figures, 264,825 and 264,831 bytes, are historical measurements explicitly identified in provenance; these are cumulative native requests, not Motoko heap bytes or retained memory.

Independently checked raw benchmark records and hashes, rather than relying only on the summary: 39 phase cohorts, three trials, both versions; matching harness/input hashes, complete trial coverage, deterministic counters, unchanged output hashes, and zero measured reclamation. Baseline package source hashes match `git show 093957a:path`; final hashes match the reviewed source. Native-library counters remain identical between versions.

Inputs are prepared before measurement. Encoding includes typed-to-library conversion where required; decoding includes conversion back to the requested Motoko type. Validation runs afterward against independently generated JSON or complete typed values. No codec work moved outside the interval. Counts are instructions and cumulative allocated bytes per call, not wall time or post-GC live memory; message-end GC is excluded.

All 15 plugin-only workloads use fewer instructions, with useful record/array reductions of approximately 14–35%. The 64 KiB Blob cases are effectively unchanged. Small record encode/decode and the small error retain an **8-byte allocation regression**; other sampled allocations are unchanged or lower. Both native serde implementations still overflow the stack decoding 64 KiB text in every trial; those failures remain recorded. These are workload-specific results and targeted correctness evidence, not a proof for every valid program or a universal performance claim.
