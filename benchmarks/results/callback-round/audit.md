# Independent callback optimization audit

**Approved, with no unresolved correctness findings.** Production changes and
measurement evidence were reviewed independently of their implementation and
benchmark execution. This audit also supplied the focused SDK regression
fixtures for nested argument suppliers and trap propagation.

## Code and semantics

- Motoko `src/codegen/compile.ml`, `Call.local`, at commit `fc7612098` removes
  redundant argument locals. Its closure preparation now follows the existing
  ordinary local-call path. Closure and argument expressions still execute
  once, left to right; preparation only reads the forwarding pointer. Retaining
  managed arguments on the operand stack is valid under the existing
  synchronous, no-GC-safepoint contract. Captures, reentry, allocation and traps
  retain their behavior. ABI 1 and the public callback interface are unchanged.
- Both [pure-map](../../../plugins/pure-map/compiler/generator.ml) and
  [mutable-map](../../../plugins/mutable-map/compiler/generator.ml) cache the
  returned variant tag. The same callback executes once and the same ordered
  label tests produce the result. Tree algorithms and payload sharing do not
  change. The branchless alternative was correctly rejected: it lost to the
  retained implementation in all eight pilot rows.
- The strengthened mutable-map payload fixture checks every `Order` result,
  exact invocation count and argument direction, mutable captures, allocation,
  nested same-map reads, other-map mutation and shared nullable payloads.
  SDK logs confirm 53 passing fixtures plus packaging checks, including the
  new supplier/trap tests and retained-value GC coverage.

## Measurements and provenance

The final paired map experiment has **36 workloads, 102 implementation/workload
groups per build and 612 measurements**. Three trials agree exactly. Before
and after use identical actor source, inputs, dependency snapshots and runner,
with a fresh canister for each implementation/workload/trial. Core and scalar
instruction controls are unchanged; allocation and reclamation are unchanged
for every phase.

Generic operations improve by **1.087–4.501% for pure-map** and
**1.365–2.885% for mutable-map**. At 100,000 entries, lookup changes from
2,524.375 to 2,410.75 instructions for pure-map, and from 3,876.90625 to
3,765.65625 for mutable-map; both allocate zero bytes.

The separate SDK experiment has **54 measurements**, confirming exactly
0/3/5 saved instructions per zero/one/two-argument callback, with zero allocated
or reclaimed bytes. Archived source, runner, cases and available Wasm hashes
were checked; SDK compiler source hashes were also checked against their
recorded Git revisions. Disassembly confirms the removed spills and the
additional `local.tee` peephole saving.

The portable archive verifier passed. Independent corruption checks used
temporary copies, leaving the evidence untouched:

- **Seven SDK checks:** fatal cleanup failure, missing or duplicate sample,
  incorrect instruction count, wrong oracle, wrong protocol and allocation.
- **Thirteen map/archive checks:** missing case; duplicate or missing sample;
  inconsistent trials; Core instruction drift; allocation change; wrong oracle;
  invalid metric type; fatal cleanup failure; changed phase methods; changed
  fresh-canister protocol; missing artifact; unexpected artifact. For the first
  eleven, copied inventory hashes were updated so semantic checks were tested
  beneath the file-integrity check.

All twenty corrupted copies were rejected.

## Limits

These are targeted instruction and cumulative allocation measurements, not
wall-clock, peak/live memory or steady-state GC results. The earlier removal
anomaly is demonstrably sensitive to phase history; its exact runtime cause
was not isolated. Historical archives remain valid observations of that older
protocol and must not be mixed with the new paired comparison.

The remaining generic/scalar gap includes comparator-body work and `Order`
decoding. Baseline Wasm repeats boxed Nat64 unboxing on the equality branch;
nullary `Order` results are constant objects, not per-call allocations. The
measurements do not attribute the entire gap to indirect dispatch or establish
the benefit of unimplemented callback specialization.
