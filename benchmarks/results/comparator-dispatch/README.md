# Comparator dispatch evidence

The [results report](../../comparator-dispatch/RESULTS.md) explains the findings
and includes every measured operation and size. The
[runner guide](../../comparator-dispatch/README.md) describes generation,
measurement boundaries and reproduction.

| Archive | Distinct cases | Trials per case | Samples |
|---|---:|---:|---:|
| [Baseline](baseline/provenance.json) | 84 | 3 | 252 |
| [Candidate](candidate/provenance.json) | 196 | 3 | 588 |
| [Mixed identities](mixed/provenance.json) | 8 | 3 | 24 |
| Total | 288 | 3 | 864 |

Each case has identical instruction counts, cumulative allocated bytes and
emitted Wasm hashes across all three independent trials. Four cases run in
parallel within each trial, using separate freshly installed canisters and
PocketIC instances; trials do not overlap. These are instruction/allocation
measurements, with no wall-time claim.

## What is retained

Every phase contains `results.json`, `provenance.json`, a complete SHA-256
`manifest.json`, generated programs/configurations, public Motoko modules,
native source snapshots/build manifests and the Ash metrics module. Under
`raw/trial-N/<case>/`, each measurement retains `ash.log`,
`test-metrics.json` and `wasm.json` (complete canister byte count and SHA-256).
Native plugin and complete canister binary bytes are not stored here. The
manifests identify them by hash, and the generated programs identify the
compilation inputs.

Provenance records exact compiler, RTS, PocketIC, didc, Core and local Ash
source hashes. The Ash checkout had pre-existing changes; only its generated
metrics module is copied, with source hashes identifying the exact local CLI.
Exact reruns require those recorded unpublished local Ash sources, including
`mocArgs` support. They are hashed but not archived, so this repository alone
cannot reconstruct the exact Ash checkout.
The runner rejects changed inputs during capture. Raw allocation means
cumulative `totalAllocatedBytes`, including garbage, rather than peak/live
heap. Complete canister Wasm sizes include the RTS, harness and validation.

Before/after comparisons require the same common generated programs, public
modules, harness, Core, Ash, RTS and execution binaries. Only the compiler and
native plugin implementations intentionally differ. Core and explicit Nat64
reference cases use the candidate compiler.

## Compiler provenance

Baseline compiler commit:
`fc7612098196031d1b1c42345f3279b5928c5071`.
Binary SHA-256:
`800ab820f06e127259f62ce5fdc68d39249a420547d717fa869182c8d60262ec`.
Baseline native plugin sources:
`f5ae694f61a6121d4a5355ee0941edc98e6e8ffd`.

Candidate binary SHA-256:
`6392a9fe6dca57a707bca5670bb4fdf67dd4cafcd03ba9228dd44d158a887546`.
All 292 compiler-source hashes in all four candidate native build manifests
match commit `92b1bdecbc7bc67fd51ad226f8d147d15494fc09`; the
[verification record](compiler-source-verification.json) identifies the
manifests and check. Cached build `source_id` text left the candidate version
banner reporting `source 2.0.0-13-gfc7612098`. The exact binary and source hashes
identify the candidate; the banner alone does not. This source check is not an
independent reproducible compiler rebuild.

Candidate captures identify plugins commit
`c602651ebfdc112952882dae99df5dd1e0072296`. Their native build manifests retain
the earlier build-time revision and source hashes; public wrapper sources are
identical to the baseline. Recorded dirty flags are preserved rather than
rewritten after capture.

The supplemental [Wasm inspection](classifier-inspection.json) checks 24
artifacts against their final archived hashes. All 12 unknown-only cases omit
the comparator classifier; four direct and eight mixed cases include it.
Static call-site counts are not dynamic invocation counts. These supplemental
records sit outside the immutable phase manifests.

## Verify the archives

From the repository root:

```sh
python3 benchmarks/comparator-dispatch/summarize.py \
  benchmarks/results/comparator-dispatch/candidate \
  --baseline benchmarks/results/comparator-dispatch/baseline
python3 benchmarks/comparator-dispatch/summarize.py \
  benchmarks/results/comparator-dispatch/mixed
```

These commands verify exact file sets and every checksum, compare raw records
with summaries, recompute medians/stability, and validate the common
before/after inputs. Do not add files inside completed phase directories
without invalidating their manifests. Raw `ash.log` files are required even
though repository-wide benchmark ignore rules normally exclude `*.log`.
