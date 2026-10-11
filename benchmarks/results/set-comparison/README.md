# Ordered Set performance evidence

This comparison covers mutable and pure ordered sets at 1,000, 10,000, and
100,000 elements. The Core control is version 2.5.0. Plugin variants use
generic comparison callbacks or native `Nat` helpers. Every operation runs
in its own newly installed canister and PocketIC instance.

The matrix contains 162 cases, repeated in three independent trials.
[Full comparison tables](../../set-comparison/RESULTS.md) show every measured
operation and size.
Point cases measure 32 distinct probes; construction, complete iteration,
union, and intersection each measure one operation. Source generation,
dependency checking, measurement boundaries, and reproduction commands are
documented in [the harness guide](../../set-comparison/README.md).

The measurements are IC instructions and cumulative Motoko allocated bytes.
Heap deltas are preserved separately and are not labelled peak memory.
Keys are small natural numbers; this matrix does not cover every key type.

```sh
python3 benchmarks/set-comparison/summarize.py benchmarks/results/set-comparison
```

The summarizer verifies file hashes and summary samples against the raw Ash
metrics before printing tables. [results.json](results.json) contains exact
totals and all repeated samples. [provenance.json](provenance.json) identifies
the compiler, native plugin builds, public modules, Core sources, Ash harness,
PocketIC binary, and commands. `sources/` preserves plugin and generated source inputs;
`raw/` contains Ash logs, exact metrics, and emitted Wasm hashes.

Iteration uses a checksum modulo 1,000,003 to avoid creating unrelated large
integers in the consumer loop. Ash source is identified by commit, dirty
status, and hashes; only the generated metrics module is copied to
`harness/Test.mo`. Reconstructing the exact local Ash CLI requires matching
its recorded source hashes.
