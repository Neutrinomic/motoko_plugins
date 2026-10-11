# Callback dispatch and map comparison optimization

Two small changes reduce callback work without changing the plugin ABI,
comparator semantics, tree algorithms, or payload sharing:

- SDK `Call.local` keeps arguments on the Wasm operand stack instead of storing
  and reloading them through temporary locals. The compiler's existing peephole
  also combines an adjacent closure store/read. Two-argument callbacks save
  **five instructions per invocation** in the isolated [SDK experiment](sdk/README.md).
- Both map plugins read the returned `Order` tag once and compare the cached
  tag. The old code could load the same variant tag twice. Callback arguments,
  invocation order/count, captures and side effects are unchanged.

The final comparison covers **36 workloads at 1,000, 10,000, and 100,000
entries**, with **612 measurements** across three trials and two builds.
All three trials produce identical instruction, allocation and reclamation
counts. Core and scalar controls have exactly the
same instruction counts before/after; allocation and reclamation are unchanged
for every phase. There are no instruction regressions in the selected callback
operations. This is a targeted refresh, not a rerun of every historical map API.

Selected costs at **100,000 entries**, in instructions per operation:

| Map | Operation | Before | After | Reduction | Plugin allocated B |
| --- | --- | ---: | ---: | ---: | ---: |
| Persistent | Get hit | 2,524.38 | 2,410.75 | 4.50% | 0 |
| Persistent | Get miss | 2,649.88 | 2,531.88 | 4.45% | 0 |
| Persistent | Insert new key | 10,137.75 | 10,019.75 | 1.16% | 1,289.25 |
| Persistent | Overwrite | 6,056.12 | 5,942.50 | 1.88% | 1,143 |
| Mutable | Get hit | 3,876.91 | 3,765.66 | 2.87% | 0 |
| Mutable | Get miss | 3,986.16 | 3,871.16 | 2.88% | 0 |
| Mutable | Insert new key | 5,497.94 | 5,382.94 | 2.09% | 40 |
| Mutable | Overwrite | 4,491.41 | 4,380.16 | 2.48% | 40 |
| Mutable | Remove hit | 7,767.81 | 7,654.47 | 1.46% | 0 |
| Mutable | Remove miss | 6,880.97 | 6,763.88 | 1.70% | 0 |

Across the three sizes, persistent lookup saves **4.18–4.50%** and mutable
lookup saves **2.66–2.88%**. All selected operations, Core comparisons, scalar
controls and allocation counts are in the [full table](tables/costs.md) and
[comparison CSV](tables/comparison.csv).

These changes remove avoidable work around the callback. They do not eliminate
the generic-versus-scalar gap. The generic path still dispatches an arbitrary
Motoko closure, executes its comparator body and decodes `Order`. A scalar
operation performs a known comparison directly. Both paths keep generic values
as managed references. Nullary `Order` values are constant objects in this
benchmark; there is no new allocation per comparison.

## Measurement correction: isolate each implementation

The earlier mutable-map matrix sometimes showed scalar removal costing more
than callback removal. A [same-Wasm diagnostic](phase-order/results.json)
changes only the order of measured phases:

| 100,000-entry scalar operation | Third phase after Core/callback | First phase | Only phase in fresh canister |
| --- | ---: | ---: | ---: |
| Remove hit | 8,886.19 | 6,580.94 | 6,580.94 |
| Remove miss | 7,258.94 | 5,651.34 | 5,651.34 |

These are one-trial per-operation diagnostic counts. The source, Wasm,
inputs and reset routine are identical. The result demonstrates an execution
history effect; the exact runtime cause was not isolated. Zero measured
reclamation does not establish identical runtime state.

The final matrix therefore uses **a fresh canister for every implementation,
workload and trial** (`--fresh-per-phase true`). Each runs the same deterministic
configuration, fresh-map preparation and four forced GC increments before
timing. Earlier phases and their validation queries cannot affect the next
implementation. The final three-trial scalar remove costs remain 6,580.94 and
5,651.34 instructions, below callback removal. Old reports remain unchanged;
their phase-order-dependent numbers are historical observations, not evidence
that scalar comparison is inherently slower.

Inputs use boxed `Nat64` keys above `2^63`, generic `Nat` values and the same
ordinary Motoko comparator as Core 2.5.0. Each point workload performs 32
distinct probes; setup, cloning, validation and reply encoding are outside
timing. Allocation is cumulative allocated heap bytes, not peak or retained
live memory. No synchronous reclamation was recorded; message-end GC is
excluded. The data does not establish a whole-canister or steady-state GC gain.

## Candidate selection and correctness

One-trial [baseline](pilots/baseline), [cached-tag](pilots/tag-once), and
[branchless](pilots/branchless) pilots keep the compiler fixed at `abfba892f`.
They compare hit/miss lookup at 1,000 and 100,000 entries. Cached-tag decoding
saves 1.21–1.36% for persistent lookup and 0.75–0.81% for mutable lookup.
The branchless alternative `(tag == greater) - (tag == less)` is slower than
cached-tag branching in all eight rows, so it was rejected. Its sources and
measurements remain archived.

The final candidate combines cached-tag decoding with compiler `fc7612098`;
the baseline uses `abfba892f`. Each map's actor source, input cases, dependency
lock and runner are exactly equal across the pair. Source snapshots, package
build manifests, compiler/runtime hashes and actor hashes identify every
cohort. Baseline compiler metadata records a dirty checkout because the user's
untracked `tmp/forumbench.md` existed; tracked compiler sources were unchanged,
and the baseline compiler binary was the previously validated release build.
The final candidate compiler checkout is clean. Wasm binaries are not committed.

The strengthened mutable payload fixture covers all three `Order` results,
exact callback count/argument order, captured mutable state, allocation,
nested reads of the same map, mutation of another map and nullable closure
payloads. Existing pure-map fixtures cover exact comparator traces and shared
payload identity. All **28 selected map fixtures** pass across the source/IR/
lowered interpreters, Wasm, fail/trap and IC run-drun suites, including GC and
upgrade fixtures. The focused two-fixture subset also passes separately.
The [validation logs](validation/) record exact commands and artifact hashes;
the composed six-plugin fixture is delegated to canonical integration.
No expectations changed. The SDK separately passes 53 fixtures plus packaging
checks. The [independent audit](audit.md) confirms the measurements, callback
semantics and verifier's rejection of 13 corrupted archive cases.

## Reproduce and verify

Build the matching map package against the compiler recorded in its provenance,
then compile the archived actor with `build-map-comparison.py` or
`build-mutable-map-comparison.py`. For each archived final cohort:

```sh
node benchmarks/run.mjs --wasm "$COHORT/main.wasm" \
  --cases "$COHORT/cases.json" --out "$COHORT/results.json" \
  --trials 3 --fresh-per-phase true --delete-canisters true \
  --server "$POCKET_IC_14" --sdk-package "$CANDIDX_TS/package.json" \
  --canonicalizer "$CANDIDX_TS/dist/index.js"
```

Historical phase-order pilots explicitly use the older archived runner.
Independent fresh phases require deterministic equivalent `configure` inputs;
these map actors do not depend on their canister ID or a previous phase.
Both the old default protocol and the new fresh-phase protocol passed small
checked-result smoke runs retained in `default-smoke/` and `fresh-phase-smoke/`.

From the repository root, verify the source archive and reproduce the final CSVs
into a directory outside this archive:

```sh
python3 benchmarks/results/callback-round/verify.py --out /tmp/callback-verification
```

The verifier checks the inventory, source/runner/provenance hashes, expected
case and sample coverage, oracle replies, identical trials, unchanged controls
and allocation, both existing strict map summarizers, and the isolated SDK
experiment. Old benchmark archives are untouched.
