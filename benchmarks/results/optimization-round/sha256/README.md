# SHA-256 optimization round

The accepted change is a source simplification, **not a speedup**. The general
kernel writes its state directly through the same unaligned word-store helper
as the 32/64-byte kernels. This removes its intermediate 32-byte Rust array,
its copy, and the redundant wrapper. The compiler already removed this overhead:
the final runtime Wasm and the final benchmark actor are byte-for-byte identical
to baseline. All measured instruction and allocation counts are unchanged.

The fixed-size kernel now checks its permitted const-generic lengths at compile
time. ABI 1, stack-only hashing state, direct borrowed input, the 32-byte managed
result, and all empty/fixed/general paths remain. Output stores use raw pointers
without first creating references to the newly allocated Blob's uninitialized
payload; `write_unaligned` preserves support for unaligned input/output buffers.

## Measurements

Both builds use the frozen Motoko compiler commit
`f1ccbba5e445df9db03bbc35be557187ade9b436`. The baseline plugin source is
`093957ad1ba611384a8b998c83bd86c75b585e4f`. The compiler was not rebuilt or
modified. [provenance.json](provenance.json) records compiler, source, artifact,
runner, and dependency hashes; the build manifests preserve the full recorded
build inputs.

[main.mo](main.mo) is identical for baseline and final. Each workload runs in a
fresh PocketIC canister for each of three trials, with deterministic xorshift32
input prepared outside measurement. Before each phase, output is cleared and
four forced GC increments run. The existing repository runner measures one
synchronous call with `performanceCounter(0)`, `rts_total_allocation`, and
`rts_reclaimed`. Counter and assignment overhead is included; end-of-message GC
is excluded. Every result is checked against Python `hashlib.sha256` and both
implementations' bytes must match. Every phase has identical counters in all
three trials; no phase reclaimed bytes.

The comparison uses the existing suite's Mops `sha2` 0.2.5
`Sha256.fromBlob(#sha256, bytes)` and `core` 2.5.0. Every dependency file was
verified against the existing native-comparison archive. This comparison is
context for the existing plugin, not an improvement introduced by this change.

| Input bytes | Baseline = final instructions | Mops sha2 instructions |
| ---: | ---: | ---: |
| 0 | 445 | 19,766 |
| 1 | 5,770 | 25,154 |
| 31 | 5,800 | 28,080 |
| 32 | 4,966 | 27,968 |
| 33 | 5,802 | 28,278 |
| 55 | 5,824 | 30,456 |
| 56 | 10,598 | 49,213 |
| 63 | 10,605 | 50,117 |
| 64 | 8,322 | 41,857 |
| 65 | 10,538 | 46,891 |
| 119 | 10,592 | 52,193 |
| 120 | 15,366 | 70,950 |
| 127 | 15,373 | 71,854 |
| 128 | 15,200 | 61,614 |
| 129 | 15,306 | 66,648 |
| 1,024 | 81,952 | 338,212 |
| 65,536 | 4,888,128 | 20,253,300 |
| 1,048,576 | 78,124,848 | 323,721,060 |

Every plugin call allocates 56 managed bytes: the 32-byte result payload and its
Blob header. Mops allocates 1,008 bytes for each measured input size. The kernel
itself does not allocate. Raw three-trial results are in
[baseline.json](baseline.json) and [final.json](final.json); the machine-readable
comparison is [summary.csv](summary.csv).

Both runtime binaries are 29,350 bytes with SHA-256
`0d8a6c3e6a1fdc20d7878da83b1d8c066e31a06049c305db80c149dabad0bf9c`.
Both actors have SHA-256
`de66ff43a24d241f47156474a2e112553c377ab798745717526999e031db6286`.
The native `.cmxs` artifacts differ because they were built in different
checkout paths; the OCaml registration/reference sources are unchanged.

## Rejected experiments

The baseline already keeps an unrolled 16-word rolling schedule in Wasm locals,
reuses a majority XOR across rounds, reads input blocks directly, and folds
padding for the 32/64-byte paths. We tested two simpler control structures with
the same actor, inputs, oracle checks, and three-trial protocol:

- A standard iterator chain for input and padding adds control state. At 1 MiB
  it costs 78,190,388 instructions, 65,540 more than baseline (+0.084%), and
  general-path boundary cases also regress. Runtime size is 29,356 bytes.
- A loop over three groups of 16 expanded rounds reduces runtime size to 16,804
  bytes (-42.75%), but costs 82,253,868 instructions at 1 MiB (+5.29%) and 10,239
  at 64 bytes (+23.04%). Dynamic round constants prevent useful constant folding.

Neither is retained. [experiments.csv](experiments.csv) includes all sizes;
[rejected/](rejected/) retains exact exploratory patches and raw results. These
patches include an intermediate byte-slice output helper; it was discarded in
favor of raw stores for the accepted cleanup. The intermediate helper saved
only 2–4 instructions and offered no material performance gain. Exploratory
sources are evidence, not proposed implementations.

## Validation and reproduction

The final package passes all three existing Rust tests (standard vectors,
fixed-size extremes, and binary padding boundaries), including a million-byte
message, unaligned input/output, input immutability, and output sentinels. Seven
Motoko fixtures pass: the SHA run/fail fixtures, four composition fixtures,
and `compute-plugins-gc.mo` in `run-drun`. See
[rust-tests.log](rust-tests.log) and [motoko-tests.log](motoko-tests.log).
Expectations were not edited. An independent audit is recorded alongside this
report.

To reproduce, enter the frozen compiler's Nix shell from its checkout, then
change into the plugin checkout. Build each source revision separately using:

```sh
scripts/build.sh --motoko "$MOTOKO" --skip-motoko-build sha256
```

`MOTOKO` must identify the already built frozen compiler above. Save the baseline
`dist/sha256` before editing or rebuilding; this run preserves it under
`_build/opt-sha256/baseline/package`. The corresponding baseline and final actor
binaries are also preserved there and under `_build/opt-sha256/final`.

Generate the identical input manifest and actor, and compile with each package:

```sh
REPORT=benchmarks/results/optimization-round/sha256
python3 "$REPORT/generate.py"
"$MOTOKO/bin/moc" --plugin "$PACKAGE" \
  --package sha2 "$SHA_DEPS/sha2@0.2.5/src" \
  --package core "$SHA_DEPS/core@2.5.0/src" \
  "$REPORT/main.mo" -o "$WASM"
node benchmarks/run.mjs --wasm "$WASM" --cases "$REPORT/cases.json" \
  --out "$RESULT" --label "$LABEL" --trials 3 \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js
```

Here `PACKAGE`, `WASM`, `RESULT`, and `LABEL` select baseline or final;
`SHA_DEPS` points to the verified Mops package directory. In this run it was
`/srv/shared/code/motoko_experiments/plugins/_build/codec-comparison/deps/.mops`.
Use a fresh result location when reproducing so this evidence stays immutable.
The runner remains the existing `benchmarks/run.mjs`; its source hash is recorded
in each raw result. Compiler/plugin build logs and exploratory artifacts are
under `_build/opt-sha256`. All prior historical result archives are unchanged.
