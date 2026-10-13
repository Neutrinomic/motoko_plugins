# Round-two harness audit

Read-only review of `main.mo`, `build.py`, and `run.mjs`, followed by independent validation of the completed `baseline-targeted` evidence. No harness or plugin files were changed by this review.

## Verified

- Baseline is the current implementation: archived generator SHA-256 `26762844620d56539dc4f40ac589b6724cbf47d16c19408c8801ca01b809c311`, not round one's initial implementation.
- Every archived file matches its manifest hash. The archived plugin build manifest matches the compiler sources, registration, plugin manifest, and `plugin.cmxs`. Registration includes append, get, pop-front, drop, and page, using ABI 1.
- Compiler and RTS hashes match the restored plugin PR toolchain. All recorded Core source files were present and unchanged during this audit. Core files are hashed rather than duplicated in the archive.
- The fixed compilation command names the private round-two plugin path and the same module, Core, harness, and output paths. Input hashes are checked before/after compilation. Candidate comparison still needs matching commands and unchanged non-plugin inputs.
- Ash launches the same local PocketIC binary whose version/hash the runner records. Each implementation/case/trial uses a fresh canister; measured instruction/allocation deltas exclude setup, replies, and message-end GC. Reclamation during the measured call must be zero.
- All **72 baseline cases / 72 paired samples** independently match closed-form expected checksum, size, first sequence, next sequence, and operation count for both implementations. This includes wrapped pages and drops. Nat32 accumulation wraps correctly; the individual sequence values converted to Nat32 remain in range at the proposed 100,000 capacity.

Run the independent checker on a completed stage:

```sh
python3 benchmarks/history-ring/round2/verify_semantics.py \
  benchmarks/history-ring/round2/results/baseline-targeted
```

It also rejects incomplete case/trial sets and checks archived-file hashes. Pass multiple stage directories to validate further runs.

## Interpretation and coverage limits

- Primary round-two comparison is current plugin versus optimized plugin. Core's page baseline always traverses forward, although these measured pages are suffixes: `Queue.reverseValues` permits O(page length) suffix traversal, and `peekBack` handles the final element in O(1). Label Core results as **forward-cursor baseline**; do not present that ratio as an inherent advantage over the best Core suffix implementation.
- Drop checks count and sequence metadata; additive page/pop checksums cannot detect reordered values. The separate flat-array model tests check each retained value and exact array order after wrapped drops, pops, and pages, including shared head/tail chunks. Run those tests against each accepted plugin build.
- `storage()` inspects only the plugin ring. Its zero-valued fields in Core churn rows are not Core retention measurements. Plugin occupied-slot and payload-byte counts independently check reachable storage; `clear` removes the whole directory.
- A fixed number of incremental GC calls does not establish a precise live-heap measurement. Current heap, historical maximum live heap, allocation, and Wasm high-water memory have distinct meanings, correctly separated in the harness methodology.
- Results are saved incrementally. A present `results.json` alone does not prove completion; require successful runner exit plus complete case/trial counts (and completed churn checkpoints when requested).

No correctness or provenance blocker was found for the intended plugin-to-plugin measurements.

## Final-harness follow-up

The final harness adds an untimed `verify()` query after both timing and post-GC memory sampling. It asserts every retained Nat equals its expected absolute sequence, checks iteration completion, and counts occupied physical plugin slots. The runner records and compares its count/first/next fields against the measured result. This addresses the earlier retained-order and post-drop storage gaps without including verification costs in either measured interval.

The Blob retention probe now drops 512 of the final 1,024 entries after 64 batches, advances eight GC increments, verifies every remaining byte and exactly 512 occupied slots / 524,288 payload bytes, then clears and advances GC again. Core storage fields remain plugin-only inspection placeholders. GC heap/high-water caveats remain unchanged.

`verify_semantics.py` detects `verify()` from each stage's archived actor and requires the recorded exact-state fields when present, allowing the intentionally older exploratory harness archives to remain verifiable. Every run requesting churn must contain both implementations, all checkpoints through batch 64, correct independently calculated payload checksums, partial-drop evidence, and completed clear evidence. A partial churn run is rejected even if all timed cases finished.

Remaining scope limit: retained-state verification cannot prove the order of already-popped results after `pop_all`, nor the order within a returned page array. Independent model/Ash tests still check those exact results. No new correctness or measurement blocker was found in the final-harness changes. This follow-up reviews code; completed final-run evidence is checked separately as it becomes available.
