# Final integrated CandidX and SHA-256 comparison

These fresh native/plugin measurements use the final integrated packages and
clean compiler `c320bf90d0b63a058b5de2c41a42c96e8b82243f` (ABI 1). They reuse
the exact actor, full input manifest, runner and seven-case selection from the
historical codec-comparison CandidX/SHA report. Three trials cover every phase.

| Workload | Native instructions | Plugin instructions | Native/plugin | Native allocated | Plugin allocated |
|---|---:|---:|---:|---:|---:|
| SHA-256, 32 bytes | 27,968 | 4,966 | 5.63× | 1,008 B | 56 B |
| SHA-256, 64 KiB | 20,253,300 | 4,888,128 | 4.14× | 1,008 B | 56 B |
| SHA-256, 1 MiB | 323,721,060 | 78,124,848 | 4.14× | 1,008 B | 56 B |
| CandidX, fixed record | 404,924 | 1,797 | 225.33× | 24,912 B | 136 B |
| CandidX, 64 KiB Blob | 210,032 | 66,508 | 3.16× | 138,280 B | 65,608 B |
| CandidX, 1,024 sparse records | 88,379,476 | 6,140,310 | 14.39× | 3,578,064 B | 22,624 B |

All 57 measured phase trials pass the independent output checks; every phase
has identical instruction and allocation counts across its three trials and
zero synchronous reclamation. Control is 256 instructions and zero allocation,
without subtraction. Relative to the saved historical report, the sparse
record plugin improves from 6,154,646 to 6,140,310 instructions (0.23%). Every
other selected phase is unchanged, as are all allocation counts and output
hashes. These final integration measurements include a compiler update and
multiple integrated plugin changes; component attribution belongs to the
separate matched-compiler optimization reports.

CandidX native means `canonicalize(to_candid(value))`, including successful
Result unwrapping, using upstream revision
`94c2868988d98e8f660a9aa569a0ebc36fcda8ea`. SHA native means
`Sha256.fromBlob(#sha256, input)` from locked Mops `sha2@0.2.5`, including
initialization and finalization. Both native libraries use locked
`core@2.5.0`. Their dependency sources were checked against the archived Mops
lock, including rejection of additional unpinned Motoko source files.

Input construction, four forced GC increments, output queries and oracle
checks are outside timing. Each phase retains its output and includes any
synchronous GC; message-end GC is excluded. Allocation is cumulative
`rts_total_allocation`, not retained heap or RSS. SHA output is checked against
the manifest's independently generated Python hashlib digest. CandidX output
is checked against the host TypeScript canonicalizer applied to ordinary
Candid bytes, and native/plugin outputs must also agree. The ordinary and
canonicalization-only context phases remain visible in the raw data.

## Evidence and reproduction

[Results](results.json), [standard summary](summary.csv),
[historical comparison](historical.json), and [provenance](provenance.json)
record every selected phase, counter, output hash and artifact identity.
[main.mo](main.mo), [cases.json](cases.json) and [run.mjs](run.mjs) are exact
historical copies; the manifest declares all 20 original workloads while the
anchored filter selects the same seven that were previously measured.
Historical archives are unchanged. Package build manifests and
[dependency file hashes](dependencies.json) accompany this report.

Compiler SHA-256:
`722ba089cc3f6fb7710423363c3adc55d0af9f841eaa5a283e97eb08f3c8335c`.
The compiler and all five packages were built by the integration owner before
this measurement; this follow-up only compiled the benchmark actor. No
production source, compiler, dependency or historical artifact was edited.
The CandidX conformance and fuzz suites already passed the accepted source;
this bounded integration check does not repeat them or use `cx.wasm`.

Run inside the compiler checkout's Nix shell, after the integration owner has
built the packages, using these exact commands from the plugins repository:

```sh
export MOTOKO_ROOT=/srv/shared/code/motoko_experiments/motoko_sha
cd /srv/shared/code/motoko_experiments/plugins
mkdir -p _build/opt-candidx-sha256-integrated
cp benchmarks/results/codec-comparison/candidx-sha/main.mo \
  _build/opt-candidx-sha256-integrated/main.mo
cp benchmarks/results/codec-comparison/candidx-sha/cases.json \
  _build/opt-candidx-sha256-integrated/cases.json
"$MOTOKO_ROOT/bin/moc" --plugin dist/candidx --plugin dist/sha256 \
  --package candidx /srv/shared/code/candidx/motoko/src \
  --package sha2 _build/codec-comparison/deps/.mops/sha2@0.2.5/src \
  --package core _build/codec-comparison/deps/.mops/core@2.5.0/src \
  _build/opt-candidx-sha256-integrated/main.mo \
  -o _build/opt-candidx-sha256-integrated/main.wasm
node benchmarks/results/optimization-round/integrated/candidx-sha256/run.mjs \
  --wasm _build/opt-candidx-sha256-integrated/main.wasm \
  --cases _build/opt-candidx-sha256-integrated/cases.json \
  --out benchmarks/results/optimization-round/integrated/candidx-sha256/results.json \
  --label integrated-candidx-sha256 --trials 3 \
  --filter '^(control|sha256-(32|65536|1048576)|candid-(static-record|blob-64k|sparse-1024))$' \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js
python3 benchmarks/summarize-comparison.py \
  benchmarks/results/optimization-round/integrated/candidx-sha256/results.json \
  --expected-cases 7 --expected-trials 3 \
  --out benchmarks/results/optimization-round/integrated/candidx-sha256/summary.csv
```

The verifier rejects failed phases, missing or duplicated trials, inconsistent
output hashes, and unexpected plugin reclamation. The integration audit also
checked the paired historical/final source, cases, runner and PocketIC hashes,
every phase's output identity, deterministic counters, and zero reclamation
for native and context phases. The final Wasm remains in the named scratch
directory; its exact digest and size are recorded in `results.json`.
