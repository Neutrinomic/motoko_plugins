# ICWire codec benchmarks

The [final positional-v6 report](results/positional-v6/REPORT.md) passes both
instruction gates on all 105 workloads: encode and decode beat native Candid
and CandidX encoding/native decoding across 1,893 observations. It links the
complete per-case CSV, matching-input optimization comparisons, correctness
evidence, allocation tradeoff, and isolated actor sizes. The earlier
[positional-v3 baseline](results/positional-v3/REPORT.md) remains frozen,
including its three CandidX encoding losses; later passes remove those losses.

**Historical archives:** `candid-baseline`, `pass1` through `pass4`, and the
`pass3-*` supplementary archives were measured before the user selected the raw
positional wire contract. They retain the discarded tagged-record experiment
and its controls. They are not performance evidence for the final positional
codec. Their source/byte hashes make that distinction independently auditable.

This suite measures native `to_candid`/`from_candid`, CandidX encoding with native
Candid decoding, and `mo:fast/ICWire` encoding/decoding. The codecs have different
wire contracts: ICWire supplies a typed schema outside the bytes; Candid carries
a type table; CandidX canonicalizes Candid. Instruction counts compare those
complete operations, including successful result unwrapping.

The fixtures cover scalar boundaries, a small record, 0–64 KiB Blobs, Takt event
envelopes and child admissions, mixed Rechain-like action batches, Reactor frame
batches, recursive chains and trees, every supported numeric array family,
zero-width arrays, Unicode text/characters, principals, and nested variants.
Takt and Reactor shapes mirror their current `src/memory/v1.mo` contracts.
The Rechain fixture is a representative typed business-action batch.
These are codec measurements; no application transport or block path changes.

Each workload, implementation, and trial gets a fresh canister. Deterministic
inputs and encoded decoder inputs are constructed before timing. After clearing
outputs and four explicit GC calls, the actor records `performanceCounter(0)`,
`rts_total_allocation`, and `rts_reclaimed` around one operation. The result is
retained. Instruction counts include counter/assignment overhead and any
synchronous GC; end-of-message GC and all setup/checking are excluded.
The control interval is reported without subtracting it. Allocations include
temporary garbage and output, not just retained live memory.
The final combined suite also samples linear-memory capacity and occupied heap
immediately outside the timed interval.

These are fresh-message measurements, including IC memory-page accounting.
The `positional-v1-cold-probe` and `positional-v1-warm-probe` archives compare
seven selected cases with and without reserving 8 MiB before the ordinary clear
and GC sequence. Every instruction count was identical, and linear memory
remained 128 MiB throughout each measured interval. Warming capacity therefore
does not become the default. Observed 80,000-instruction steps are consistent
with the tested IC revision's [5,000-instruction OS-page charge](https://github.com/dfinity/ic/blob/fc21803c3c3a8dd452b3b58b959751c41fecb89c/rs/config/src/subnet_config.rs#L141)
and [64 KiB access/dirty-page groups](https://github.com/dfinity/ic/blob/fc21803c3c3a8dd452b3b58b959751c41fecb89c/rs/memory_tracker/src/deterministic.rs#L331)
(16 OS pages per group); the probes rule out linear-memory growth as their
cause. All such costs remain in the reported counts.

An unmeasured query checks every entire decoded value against the independently
constructed fixture. Encode outputs are also decoded and compared there, before
their bytes are returned. CandidX outputs additionally match the existing host
canonicalizer applied to native Candid. Wire conformance and malformed-input
tests are in the ICWire plugin's test suite; round-trip performance fixtures
alone are not an independent wire-format oracle.

`results/candid-baseline/` retains the initial Candid-only 23-workload screen:
276 successful observations across three fresh-canister trials, identical
counts across repetitions, and zero reclamation inside the measured intervals.
Final codec comparisons should use native Candid and CandidX observations
repeated in the same actor as ICWire, rather than mix actor builds.

From the plugin repository root, with `dist/icwire` and `dist/candidx` built for
the installed compiler bundle:

```sh
python3 benchmarks/icwire/build.py candidate --combined --memory-probe
node benchmarks/icwire/run-probe.mjs \
  --wasm benchmarks/icwire/results/candidate/main.wasm \
  --cases benchmarks/icwire/results/candidate/sources/cases.json \
  --out benchmarks/icwire/results/candidate/results.json \
  --label candidate --trials 3 --delete-canisters true \
  --server /home/devbox/.cache/canic/pocket-ic-server-16.0.0/pocket-ic
python3 benchmarks/icwire/summarize.py \
  benchmarks/icwire/results/candidate/results.json \
  --require-native-win --require-candidx-win
```

The build script defaults to `/home/devbox/.local/lib/motoko-compute`; override
it with `--bundle`. It snapshots the actor, codec modules, plugin sources and
artifacts, checks artifact/source provenance, pins compiler/RTS hashes, and
records the build command and resulting Wasm hash. `--plugin` and
`--candidx-plugin` select isolated plugin builds. Existing result directories
are never overwritten. `--baseline-only` omits ICWire when screening the native
controls. Binaries stay local; source snapshots, hashes and raw results are
retained in the repository. The shared runner uses the installed Candid SDK and
canonicalizer at `../../candidx/ts`.

The actual actor compiler is the installed binary `24d8d0b9…`, with its original
RTS, throughout these passes. ICWire plugin packages were produced with a
separately linked, interface-compatible compiler binary `a2f5b46b…` from the
same SDK revision `9f6ebeedc`; their producer hashes remain in each plugin build
manifest. Successful native loading checks compatibility. No SDK code changed
for this codec. Producer and benchmark-compiler hashes are recorded separately;
they are not claimed to be byte-identical.

For a quick candidate screen, pass `--trials 1 --filter
'scalar|tiny|takt-event-32|rechain-actions-32|reactor-frames-64'` to the runner.
Final reports use at least three trials and include every workload, including
small-input or encoding losses.

The full matrix uses `build.py LABEL --combined --memory-probe`: all 23
application/main fixtures, three recursive fixtures, 21 scalar-boundary
fixtures, and 58 array/principal/rope fixtures, plus a control interval.
Duplicate scalar Blob sizes remain explicitly named instead of being removed.
This is 105 workloads and 1,893 observations at three trials, with encode and
decode timed separately. `summarize.py RESULT --require-native-win` rejects
any workload whose ICWire instruction median fails to beat native Candid on
either operation. It also rejects partial suites or fewer than three trials.
`--require-candidx-win` applies the same complete-suite gate against CandidX
encoding and native decoding of CandidX bytes. Both flags can be required
together; failed candidates remain archived instead of being omitted.

The first raw matrix, `positional-v1`, retains all 48 native/CandidX failures
for Null/unit arrays of 4,096 and 65,536 elements: native decoding rejects these
under its default value-expansion limit. ICWire decoded them, but those cases
cannot count as speed wins. The separate `positional-v1-capacity` archive keeps
the boundary probes and exact errors. The comparable full matrix uses zero-width
array sizes 0, 1, 512, and 1,024, all accepted by native Candid; native limits are
unchanged. Its manifest differs from the first raw matrix, so the two are not
silently presented as an identical-suite before/after comparison.

`--recursive` and `--scalars` select standalone diagnostic suites. `--codec`
selects `candid`, `candidx`, or `icwire` to build isolated actors for code-size
comparison. Isolated CandidX actors check full typed equality but do not include
the native encoder needed for a host canonicalization reference; use the full
matrix for the independent canonical-byte check. All codec-only actors retain
the same deterministic fixture construction and public Candid query interfaces.

The summarizer rejects missing/duplicate workloads, failed or incomplete trials,
and actor/Wasm/runner provenance mismatches. `--allow-partial` permits an explicit
filtered screen. Compare optimization passes with:

```sh
python3 benchmarks/icwire/compare.py \
  benchmarks/icwire/results/pass1/results.json \
  benchmarks/icwire/results/pass2/results.json
```

This requires identical generated actor source, compiler/RTS, runner, workload
manifest, repetitions, PocketIC version and output bytes. It reports repeated
Candid control changes as well as ICWire changes, rather than silently assuming
that a different codec's setup allocations cannot affect heap placement.
