# Automatic comparator dispatch

This matrix compares ordinary `Map`/`Set` calls with Core 2.5.0, the plugin
before comparator specialization, and explicit `Nat64` helpers as a scalar
reference path. Mutable and pure maps and sets use the same generated programs. Each
case runs in its own freshly installed PocketIC canister, with a separate
configuration per operation, comparator, size, and trial.

The main matrix measures shuffled construction and 32 successful lookups,
new-key additions, or existing-key removals at 1,000, 10,000, and 100,000
entries. Map values are `Nat`; keys alternate between the low and high halves of
`Nat64`, so unsigned ordering matters. Empty and singleton cases measure
one missing lookup or new-key addition, exposing dispatch overhead. At 10,000
entries, additional lookups exercise a comparator alias stored in a record,
a generic function parameter, a comparator reading captured mutable state,
a reversed comparator, and a comparator incrementing an observable counter.

`direct` uses `mo:core/Nat64.compare` through the ordinary public API;
`static` uses the explicit `*Nat64` helper. The extra generic helper checks the
same retrieved map value as the direct case. The benchmark preserves comparator
effects and checks complete result contents and ordering after measurement;
pure updates also check the original tree. Correctness suites provide more
extensive comparator semantics and GC coverage.

Inputs, shuffled key arrays, and result buffers are prepared before `Test.test`.
Only construction itself is inside the build measurement. Validation follows
measurement. Allocation means the cumulative `totalAllocatedBytes` delta,
including temporary garbage; heap delta and live-size high-water mark are not
presented as peak memory. Wasm size means the complete canister file, including
the RTS, Ash harness and validation, rather than a standalone plugin payload.

## Recording

Use a frozen compiler/RTS bundle, native plugin `dist` directory, and `fast`
source directory for each capture. Preserve the old compiler and native
artifacts before rebuilding. The public module source directory must be the
same for both phases. Install the selected bundle using the managed Ash compiler
wrapper before recording; the runner verifies what Ash actually resolves and
never changes global tools or the Ash checkout itself.

```sh
python3 benchmarks/comparator-dispatch/generate.py \
  --out _build/comparator-before --deps _build/map-deps --phase baseline \
  --dist _build/comparator-baseline/dist --fast packages/fast/src
python3 benchmarks/comparator-dispatch/run.py \
  --out _build/comparator-before --archive _build/comparator-before-evidence \
  --phase baseline --trials 3 --jobs 4 --ash /path/to/ash \
  --toolchain _build/comparator-baseline/toolchain \
  --dist _build/comparator-baseline/dist --fast packages/fast/src \
  --deps _build/map-deps --plugin-source-revision OLD_PLUGIN_COMMIT

python3 benchmarks/comparator-dispatch/generate.py \
  --out _build/comparator-after --deps _build/map-deps --phase candidate
python3 benchmarks/comparator-dispatch/run.py \
  --out _build/comparator-after --archive _build/comparator-after-evidence \
  --phase candidate --trials 3 --jobs 4 --ash /path/to/ash \
  --toolchain /path/to/new/compiler-bundle \
  --dist dist --fast packages/fast/src --deps _build/map-deps
python3 benchmarks/comparator-dispatch/summarize.py \
  _build/comparator-after-evidence --baseline _build/comparator-before-evidence
```

The dependency directory contains the locked `core@2.5.0` installation used by
other map benchmarks. Start with `generate.py --select exploration` and
`run.py --trials 1` to validate dispatch, callbacks and code size before the
final capture. The complete candidate matrix has 196 cases; the baseline
records the 84 corresponding ordinary/callback cases. Three final trials give
840 independent samples in total. `--jobs` defaults to one; four parallel cases
can reduce recording time without sharing a canister or PocketIC instance.
Every trial finishes before the next starts, preventing configuration reuse.
Concurrency is recorded; these are instruction/allocation measurements, with
no wall-clock performance claim.

The runner checks native artifacts against their build manifests and compiler
hash, validates the locked Core sources, records compiler/RTS/Ash/PocketIC
provenance, and rechecks all runtime/source inputs after every case. A preserved
baseline can retrieve its plugin source snapshot from a commit, but every file
must still match its native build manifest. Raw Ash logs, metrics, generated
sources, plugin sources, module sources, manifests, and emitted Wasm size/hash
are retained. Failed runs remain incomplete. The summarizer verifies retained
files and raw records before calculating medians; a before/after comparison
also requires byte-identical generated programs, public modules and metric
harness.

Exact capture reproduction also requires the recorded unpublished local Ash
sources, including `mocArgs` support. Their hashes are retained, but the CLI
sources themselves are not archived here; this repository alone is therefore
insufficient to reconstruct that exact Ash checkout.

## Mixed comparator identities

`generate-mixed.py --out NEW_DIRECTORY --deps _build/map-deps` produces eight
additional 10k lookup cases: every family selects either the standard comparator
or the captured callback at runtime. Both identities are reachable through the
argument-taking `chooseStandard` configuration method; Ash skips that method
and measures `bench`. Selection occurs before `Test.test`. Use the same runner
with `--trials 3` to record another 24 samples, for 864 final samples overall.

These probes distinguish a canister containing only an unknown plugin comparator
from one also materializing a recognized comparator. Inspect the emitted Wasm
to confirm which contains `plugin_comparator_kind`; importing `Nat64` alone does
not establish that distinction because unused function values can be eliminated.
The mixed cases also hoist the chosen function value outside the measured loop.
Their differences from the main matrix measure complete lookup paths and do not
isolate the classifier's cost. The ordinary-versus-explicit-helper comparison
likewise includes the complete API-call difference.
