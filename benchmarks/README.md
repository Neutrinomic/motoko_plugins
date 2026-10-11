# PocketIC compute-plugin benchmarks

Current generators target the development plugin API and include successful
`#ok` unwrapping inside each CandidX measurement. The SDK remains at ABI 1
while the compiler PR is unmerged. Archived reports retain their original
artifact hashes and version labels, including runs made during the temporary
ABI 2 development version.
The [typed-result CandidX report](results/typed-results/README.md) records
native-library comparisons and both complete 500-record fuzz seeds.
The [JSON report](results/json/README.md) records typed encoding and decoding
costs for records, arrays, and binary data.

The recorded [first-pass results](results/README.md) and
[second-pass results](results/pass2/README.md) include raw reports and artifact
hashes. The second pass uses the previous optimized implementation as its
baseline.

The [native-library comparison](results/native-comparison/report.txt) measures
CandidX's native Motoko library and Mops `sha2@0.2.5` against the plugins.
Its [CSV](results/native-comparison/summary.csv) includes instruction and
allocation counts for all 40 workload entries. Reproduction commands are below.

Run from this repository root inside the selected Motoko compiler checkout's
`nix develop` environment, after `scripts/build.sh --motoko PATH`. Set
`MOTOKO_ROOT` to that checkout's absolute path:

```sh
export MOTOKO_ROOT="$(realpath ../motoko_sha)"
```

This harness uses `pocket-ic-server` from that environment, Python 3, and Node.js.
It also uses
the Candid SDK and canonicalizer from the sibling `../../candidx/ts` project
(with dependencies installed and its TypeScript build completed). Override
their paths with `--sdk-package` and `--canonicalizer` when needed.

Generate once, then compile the **same actor source** against each compiler and
plugin package being compared:

```sh
python3 benchmarks/generate.py --out _build/plugin-perf/bench
"$MOTOKO_ROOT/bin/moc" --plugin dist/candidx \
  --plugin dist/sha256 \
  _build/plugin-perf/bench/main.mo -o _build/plugin-perf/current.wasm
node benchmarks/run.mjs \
  --wasm _build/plugin-perf/current.wasm \
  --cases _build/plugin-perf/bench/cases.json \
  --out _build/plugin-perf/current.json --label current --trials 3
python3 benchmarks/compare.py \
  _build/plugin-perf/baseline/results.json _build/plugin-perf/current.json
```

When invoking a saved native `moc` binary directly, set `MOC_RELEASE_RTS` and
`MOC_DEBUG_RTS` to the runtime Wasm files used for that build. The selected compiler's `bin/moc`
wrapper sets these automatically for the current compiler.

The workloads cover SHA-256 block/padding boundaries and 1 KiB, 64 KiB, and
1 MiB inputs; empty/scalar/static-record Candid; a 64 KiB Blob; 4,096 Nat64s;
sparse records; nested optional arrays; and growing variant unions. Generate
the optional large union separately with
`--variant-width 6000 --variant-payload null --host-variant-reference`, compile its
`main.mo`, then run with `--filter variants-6000`. The host-reference option
constructs ordinary Candid with the host SDK, avoiding an additional large
ordinary-encoder function in the actor. Use matching manifests and
variant widths for a comparison, because ordinary Candid encodes the complete
static variant type. Extremely wide variant types can exceed IC limits on
Wasm locals or function complexity at installation before encoding can run.
The generator splits constructors for widths above 1,024 into 256-case
helpers so benchmark input setup does not itself hit those function limits.

For a separate fixed-shape array suite, run
`python3 benchmarks/generate-static-arrays.py --out _build/plugin-perf/static-arrays`
and compile/run its `main.mo` and `cases.json` with the same commands above.
It covers empty, singleton, and 1,024-element arrays of fixed-width records
and records containing Text, Blob, or `[Nat8]`, including empty and nonempty
byte fields. Keeping this actor separate preserves the original suite's
source hash. Compile the identical generated source for both versions.

Generate another separate actor with `generate.py --repeated-variants --out DIR`
and run with `--filter repeated-variants` to measure empty/singleton arrays,
1,024 entries using one tag, 4,096 entries cycling four tags, and 6,000 entries
cycling 64 tags. These complement the distinct-tag variant workloads and use
ordinary Candid plus host canonicalization for their reference bytes.

Each workload/trial uses a fresh canister. Input construction, four forced GC
increments, output serialization, and correctness checks happen outside the
measured interval. An update measures one call with `performanceCounter(0)`
and `rts_total_allocation`; the output is retained to make the work observable.
The original plugin-only suites require zero reclamation during the synchronous measurement.
End-of-message GC is excluded. Allocation is cumulative heap allocation, not
RSS or retained live memory.

Instruction counts are the **raw measured interval**, including counter and
output-assignment overhead. The separate `control` workload makes that fixed
cost visible; the comparison script does not subtract it. These are IC
instruction counts, not wall-clock timings or host CPU cycles. Ordinary
`to_candid` has different semantics and is reported as context, not an
equivalent canonical encoder.

SHA-256 outputs are checked against Python `hashlib` digests generated from
the exact inputs. CandidX outputs are checked against the host canonicalizer
applied to ordinary Candid bytes. Reports include every trial, output sizes
and hashes, Wasm hashes, the PocketIC version, and failures. The comparison
script rejects failed or incomplete reports and checks matching output hashes
and sizes before reporting reductions. When using `--filter`, apply the same
filter to both runs so the comparison covers matching workloads.

## Typed JSON

Generate independent Python JSON inputs, then compile and measure the JSON
plugin in the same environment:

```sh
python3 benchmarks/generate-json.py --out _build/json-perf
"$MOTOKO_ROOT/bin/moc" --plugin dist/json \
  _build/json-perf/main.mo -o _build/json-perf/main.wasm
node benchmarks/run.mjs \
  --wasm _build/json-perf/main.wasm --cases _build/json-perf/cases.json \
  --out _build/json-perf/results.json --label typed-json --trials 3
```

The six workloads encode and decode a small record, 1,024 records, and a
64 KiB Blob. The timed interval includes successful Result unwrapping and
assignment of the retained typed result. Encoder outputs are parsed by the
host's `JSON.parse` and compared with independently generated Python data.
For decoding, a separate actor query compares the full decoded value with an
independently constructed Motoko value. Its two-byte `"ok"` response is the
reported decoder output size; it is not the size of the decoded heap object.
Validation, UTF-8 reply conversion, and message-end GC are outside the interval.
These measurements establish plugin costs; they do not compare JSON libraries.

## Native-library comparison

This comparison puts native and plugin implementations in the same actor and
uses the same compiler, inputs, and measurement boundaries. Native CandidX is
`CandidX.canonicalize(to_candid(value))`, including successful result unwrapping;
the plugin is `Prim.to_candid_canonical(value)`. The separate `normalize` phase
only canonicalizes an already prepared ordinary Candid Blob. Its cost does not
represent complete encoding from a Motoko value. Ordinary `to_candid` is also
recorded for context.

SHA-256 compares `Sha256.fromBlob(#sha256, input)` from Mops `sha2@0.2.5` with
`Prim.sha256(input)`. Both include digest initialization and finalization. Inputs
use deterministic xorshift32 bytes with seed `0x9e3779b9`; Python `hashlib`
provides the reference digest. Input generation is outside the measurement.

The recorded CandidX revision is
`94c2868988d98e8f660a9aa569a0ebc36fcda8ea`. Both native libraries use the exact
Mops `core@2.5.0` dependency pinned by SHA-256. CandidX declares core 1.0.0;
compatibility and canonical output parity were checked with 2.5.0. Dependency
hashes, the Mops lockfile, and compiler/plugin hashes are saved with the reports.

Run these commands from this repository root inside the selected compiler's
Nix shell, after building the plugins and preparing the sibling CandidX TypeScript
oracle as described above. Use the recorded CandidX revision for reproduction;
do not reset an existing working tree to obtain it.

```sh
mkdir -p _build/plugin-comparison/deps
cp benchmarks/results/native-comparison/dependencies/mops.toml \
  benchmarks/results/native-comparison/dependencies/mops.lock \
  _build/plugin-comparison/deps/
(cd _build/plugin-comparison/deps && mops install --no-toolchain --lock check)

for bench_suite in main static-arrays repeated-variants; do
  bench_dir="_build/plugin-comparison/replay/$bench_suite"
  python3 benchmarks/generate-comparison.py \
    --suite "$bench_suite" --out "$bench_dir"
  "$MOTOKO_ROOT/bin/moc" --plugin dist/candidx \
    --plugin dist/sha256 \
    --package candidx ../../candidx/motoko/src \
    --package sha2 _build/plugin-comparison/deps/.mops/sha2@0.2.5/src \
    --package core _build/plugin-comparison/deps/.mops/core@2.5.0/src \
    "$bench_dir/main.mo" -o "$bench_dir/main.wasm"
  bench_filter=()
  if [ "$bench_suite" = repeated-variants ]; then
    bench_filter=(--filter repeated-variants)
  fi
  node benchmarks/run.mjs \
    --wasm "$bench_dir/main.wasm" --cases "$bench_dir/cases.json" \
    --out "$bench_dir/results.json" --label "native-$bench_suite" \
    --trials 3 "${bench_filter[@]}"
done

python3 benchmarks/summarize-comparison.py \
  _build/plugin-comparison/replay/main/results.json \
  _build/plugin-comparison/replay/static-arrays/results.json \
  _build/plugin-comparison/replay/repeated-variants/results.json \
  --expected-trials 3 --expected-cases 40 \
  --out _build/plugin-comparison/replay/summary.csv
```

The generator accepts `--provenance FILE` to embed a JSON description of the
compiler, plugins, and libraries. Capture fresh artifact hashes for a new run;
the saved provenance describes the recorded run only. Reports independently
fingerprint their actor Wasm, source, cases, and runner.

Explicit `phases` entries describe each method's correctness semantics and
whether reclamation is forbidden. Native phases may perform synchronous GC,
which is included in their instruction count and reported as reclaimed bytes;
plugin phases require zero reclamation. The recorded comparison had zero
reclamation in every phase and identical instruction counts in all three
trials. It contains 40 workload entries (including two control entries),
120 fresh canisters, and 414 measurements. These are synchronous operation
costs; allocation-driven message-end GC remains outside the measured interval.

## CandidX repository correctness suite

[Saved correctness reports](results/native-comparison/candidx-correctness/summary.json)
include the existing CandidX conformance driver and two 500-random-record fuzz
runs, seeds `0xcad1d` and `0x5eedc0de`. Each seed expands to 1,130 typed plugin
record case instances; directed cases repeat across seeds. The 93-case directed
corpus also runs separately. Independent canonicality, schema-extension
invariance, and original-value recovery through Rust, TypeScript, and Motoko
all passed. Binary-input controls in the conformance report test the oracles and
native normalizers, rather than an inbound plugin API.

The reusable [compiler adapter](../plugins/candidx/tests/candidx-moc.py) lets those existing drivers
invoke the plugin without modifying their oracles or original probes. Pass its
absolute path as both `--moc` and `--runtime-moc`, and pass `--skip-wasm` to
exclude the standalone Wasm backend. Set `CANDIDX_TEST_ROOT` to a directory
containing the driver's `--out` directory. It rewrites the upstream probes'
`to_candid_canonical(...)` calls to `Prim.to_candid_canonical(...)` and unwraps
the Result for the upstream driver's Blob-or-trap contract in adjacent copies, recording source hashes
and translations. Expected `#err` results become traps only in this test adapter.

Follow the sibling CandidX repository's test setup for its Python/Wasmtime,
Rust, OCaml, and TypeScript oracles. The saved summary includes exact commands
and frozen artifact hashes. For a current-build run, omit
`CANDIDX_TEST_ARTIFACTS`; set `MOTOKO_ROOT` and the adapter uses that compiler's
`bin/moc` with this repository's `dist/candidx` package. For a frozen run, that variable names a directory containing `moc`,
`mo-rts.wasm`, `mo-rts-debug.wasm`, and
`candidx/{plugin.cmxs,runtime.wasm}`. The reusable adapter was revalidated on all
93 directed cases and its output matched all 42 previously tested generated
source translations.
