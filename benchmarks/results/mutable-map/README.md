# Mutable-map plugin: instruction and allocation measurements

The [final three-trial table](final/costs.md) compares the plugin with **mutable
`mo:core/Map` 2.5.0** at 1,000, 10,000 and 100,000 entries. It retains all 138
workload rows and 24 scalar-ordering comparisons, including weaker cases.
The [CSV](final/summary.csv) contains raw batches, per-operation costs, trial
ranges and reclaimed bytes; [methodology](final/README.md) explains units and
correctness checks. This is separate from the existing Core **pure-map** report.

Mutations operate on ordinary GC-managed Motoko nodes and retain keys/values
by reference. Reported memory is cumulative allocated/reclaimed bytes, including
temporary garbage and retained results; **peak or live heap is not measured**.
Benchmark reset clones are outside timing and are not part of normal updates.

## Bounded optimization pilots

Each paired pilot uses byte-identical actor source, compiler binary and inputs.
All pilots are explicitly one trial; final comparisons use three trials.
Every measured candidate and its source is retained:

- [Initial points/construction](pilot-1/costs.md) and
  [cached array references/size arithmetic](pilot-2/costs.md): fewer repeated
  field loads and simpler checked deletion accounting.
- [Initial wrappers](wrapper-before/costs.md) and
  [leaf traversal](wrapper-after/costs.md): skip null child recursion on leaves.
- [Direct tuple retention](wrapper-direct-slot/costs.md): `find` reuses stored
  tuples; scanning 100,000 entries allocates 72 bytes instead of 4,000,072.
- [Full API smoke](api-pilot/costs.md) and
  [final API smoke](api-final-pilot/costs.md): min/max no longer allocate a tuple;
  seeks avoid temporary tuple projections. The final API pair has small Core
  control differences of 16–48 instructions per batch in 33/46 workloads,
  with identical allocation. These differences are reported without subtracting
  them; their exact cause was not isolated. Earlier point/wrapper pairs have
  identical Core counters. The final table compares implementations within one
  frozen actor, not across these pilot artifacts.

The [performance review](performance-review.md) records accepted changes and
remaining tradeoffs. All [14 permanent fixtures](validation/permanent-tests.log)
and [six-package packaging checks](validation/packaging.json) also passed on
the measured compiler/package; [test provenance](validation/permanent-tests.json)
records their exact source and expectation hashes. Full map transformation can use more instructions than
Core even while allocating less; use the actual row at the intended size.
The matrix measures 46 workload variants, not every convenience wrapper.

## Offline verification

From the repository root, no compiler, PocketIC or network is required:

```sh
python3 benchmarks/summarize-mutable-map.py --archive benchmarks/results/mutable-map
```

The [archive inventory](artifact-manifest.json) records every retained file's
size and SHA-256. Verification checks complete case/phase/trial coverage,
successful independent oracles, source/runner/provenance identities and
reproduces all CSV/Markdown tables. Wasm binaries are omitted from Git; their
exact hashes remain in each provenance/report. If a local Wasm is present,
its hash is checked too.

## Running new measurements

Use the pinned clean compiler and the shared runner dependencies described in
[benchmark setup](../../README.md). Set `MOTOKO_ROOT` to the compiler checkout,
`MOPS_DEPS` to an installed locked Core 2.5.0 dependency directory and
`CANDIDX_TS` to the built CandidX TypeScript project used by that shared runner.
The exact measurement [Mops manifests](dependencies) are retained; the build
helper checks every imported Core source against its lockfile.
Run inside the compiler's `nix develop` environment, from this repository:

```sh
scripts/build.sh --motoko "$MOTOKO_ROOT" --skip-motoko-build mutable-map
python3 benchmarks/generate-mutable-map-functions.py --out _build/mutable-map
python3 benchmarks/build-mutable-map-comparison.py \
  --motoko "$MOTOKO_ROOT" --deps "$MOPS_DEPS" \
  --out _build/mutable-map --require-clean-compiler
node benchmarks/run.mjs --wasm _build/mutable-map/main.wasm \
  --cases _build/mutable-map/cases.json --out _build/mutable-map/results.json \
  --label mutable-map --trials 3 --delete-canisters true \
  --sdk-package "$CANDIDX_TS/package.json" --canonicalizer "$CANDIDX_TS/dist/index.js"
python3 benchmarks/summarize-mutable-map.py _build/mutable-map/results.json \
  --cases _build/mutable-map/cases.json --out _build/mutable-map/summary.csv
```

The build helper records compiler/package/source hashes and snapshots plugin
sources plus harness files for offline validation. Compiler revision, binary,
RTS inputs and built package must match; stale packages or changing sources
are rejected. `--operations` and `--sizes` select smaller generator matrices;
those runs require their own manifests and must not be mixed into the final
three-trial results.
