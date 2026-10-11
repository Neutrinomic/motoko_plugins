# Independent benchmark validation audit

Reviewed the generator, build provenance, summary validator and shared PocketIC
runner on 2026-10-11. No measurement-equivalence or arithmetic defect found.
Configure, seed cloning/reset, forced GC and the checked-result query occur
outside the timed counters. The baseline is mutable `mo:core/Map` 2.5.0;
`find` and `getEntry` adapters are disclosed. Allocation is cumulative allocated
bytes, not peak/live heap; synchronous reclamation is reported separately.

Independently verified pilot-1's 24 cases and 60 phase samples: no failed
measurements, and actor, Wasm, runner, cases, provenance and archived plugin
source hashes matched. This is a one-trial pilot, not the final comparison.

The previous missing archive-integrity checks are fixed. Audited files:

- `benchmarks/summarize-mutable-map.py` SHA-256:
  `6616212a41606995690309c5c50f58d455b68f64c76c1bbd17ea80c01a3b678a`
- `pilot-1/results.json` SHA-256:
  `967ac9a4e197aa6e5c44f065a89f4bc35d84be305a1a3bdf14178ac2ff09b7a3`

All 20 checks below passed. Tests used a temporary copy of pilot-1, invoking
the audited summary with `--expected-trials 1`; each mutation was restored
before the next check. Archive checks used a temporary one-cohort inventory
with byte sizes and SHA-256 digests. Production and cohort files were unchanged.

| Check | Observed outcome |
| --- | --- |
| 1. Pristine pilot | Accepted |
| 2. Regenerated CSV and Markdown | Both byte-identical to archived tables |
| 3. Wrong report trial count | Rejected |
| 4. Dropped measurement | Rejected |
| 5. Duplicate measurement | Rejected |
| 6. Dropped case | Rejected |
| 7. Duplicate case | Rejected |
| 8. Incorrect output hash | Rejected |
| 9. Negative instruction count | Rejected |
| 10. Report runner hash mismatch | Rejected |
| 11. Report Wasm hash mismatch | Rejected |
| 12. Actor source tampering | Rejected |
| 13. Archived plugin source tampering | Rejected |
| 14. Archived runner tampering | Rejected |
| 15. Retained Wasm tampering | Rejected |
| 16. Optional local Wasm absent | Accepted as intended |
| 17. Complete archive inventory and offline table reproduction | Accepted |
| 18. Unlisted archive file | Rejected |
| 19. Archived table content tampering | Rejected |
| 20. Missing archived file | Rejected |

Validation tooling is approved. A subsequent independent check approved the
final **138 cases, 300 phase groups and 900 samples across three trials**:
zero failed measurements; identical instruction, allocation and reclamation
counts in all three trials; all seven production-source hashes matched the
correctness audit; regenerated CSV and Markdown matched byte for byte.
All measured reclamation counters were zero, so the report measures cumulative
allocation rather than steady-state GC cost. Exact artifact hashes are in
[`final-benchmark-validation.json`](final-benchmark-validation.json).
