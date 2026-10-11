# Independent mutable-map audit

**Approved.** No unresolved correctness or memory-safety defect was found in
the supported API contract. Review covered the schema, native generator,
interpreter reference, registration, Motoko wrapper and Core adapter, plus
benchmark generation, measurement boundaries and validation. No production
changes were needed from this audit. A missing benchmark archive-integrity
check was fixed and independently retested.

The audited candidate uses compiler commit
`abfba892fe4bd8fa2bc88e25dca0b895d35c1962`, ABI 1, and release `moc` SHA-256
`a5a68803ecc8d48509c77052889f05eb8b5e3e983ee55b2027e9689939d79498`.
All seven production-source hashes match the final benchmark cohort. The
candidate was audited before its plugin commit; the exact source snapshot,
package hashes and Core 2.5.0 dependency hashes are recorded in
[`candidate-provenance.json`](candidate-provenance.json) and `sources/`.

## Independent checks

All three original audit programs passed source interpretation, IR
interpretation, lowered IR interpretation and Wasm execution against the final
frozen package. Typechecking, compilation and Wasm validation produced no
diagnostics. Expected outputs were generated, inspected and rechecked without
acceptance; the retained evidence includes actual stage output, not only runner
exit status.

| Program | Coverage |
| --- | --- |
| `run/callback-state.mo` | Every comparator checks full tree invariants, exact pre-operation bindings and size, performs nested same-map reads, and mutates a separate map. Exercises insertion, shuffled deletion and missing deletion through splits, borrowing, merging and root collapse. |
| `run/helper-instantiations.mo` | Shared native helpers across unrelated key/value types, nullable record keys, nested optional mutable/closure payloads, replacement key identity, 1,200-entry deletion, clone independence, shared payload aliases and scalar extremes. |
| `run/randomized-core.mo` | 7,200 operations from three seeds against mutable Core Map, nullable signed keys, nested option values, both ordering directions and inclusive forward/reverse seeks. |

The three production IC fixtures were also copied to `run-drun/` with only
import/package paths adjusted, then independently rerun:

- Incremental GC with fragmented live data, comparator reentry, retained
  payloads/closures and aliases; point allocation independent of Blob size.
- Two actor upgrades preserving mutable-map aliases, independent clone nodes
  and shared mutable payloads, followed by collection checks.
- Traversal allocation checks preventing per-entry tuple garbage in `find`.

The review checked clearing vacated slots, typed GC barriers, generic helper
layout sharing, nullable result injection, and callback-visible valid state
during deletion. The optimized size decrement uses checked word conversion and
a zero guard before subtraction; the reference rejects oversized forged
metadata as well. This does not promise complete validation of manually forged
trees. The supported contract excludes structural same-map mutation in
callbacks and use of iterators after a mutation attempt; no locks or version
bookkeeping were added.

## Benchmark verification

The final **138 cases / 300 phase groups / 900 samples / three trials** passed
independent validation with zero failures. CSV and Markdown reproduced byte for
byte; all counters were deterministic across trials. Setup, reset, GC triggers
and correctness checks are outside measured intervals. Core's mutable Map is
the baseline, with `find` and `getEntry` adapters disclosed.

Allocation is cumulative allocated bytes. Every measured reclamation counter
was zero, so the benchmark does not measure steady-state GC cost or peak/live
memory. See [the validation receipt](benchmark-validation.md), including 20
negative/reproduction checks and
[exact final artifact hashes](final-benchmark-validation.json).

## Reproduce

Verify the retained evidence without a compiler:

```sh
python3 benchmarks/results/mutable-map/audit/verify.py
```

After building the frozen plugin against the matching compiler, enter that
compiler's Nix environment. Set `MOTOKO_CORE` to the pinned Core 2.5.0 `src`
directory and `PLUGIN_ROOT` to this repository, then run from the compiler root:

```sh
test-runner -b "$PLUGIN_ROOT/benchmarks/results/mutable-map/audit/run" \
  "$PLUGIN_ROOT/benchmarks/results/mutable-map/audit/run-drun"
```

The callback-state test intentionally takes about nine minutes in the
interpreters because every comparator traverses the entire map. Raw Wasm
binaries and temporary runner directories are omitted; their hashes and all
small actual stage outputs are retained.
