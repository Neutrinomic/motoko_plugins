# JSON optimization and simplification round

The previous optimized JSON package is the baseline. The final runtime defers
JSON Pointer formatting until the first error and reuses the existing borrowed
number lexer for syntax-only skips. This removes 30 implementation lines, excluding tests.
A single `Vec<PathComponent>` replaces the eager `String` plus length stack;
the two component kinds are the existing borrowed `Key` and an array index.
There is no generic path framework, new ABI, or new support profile. Key bytes
remain in the rooted input or compiler literals for the synchronous call.
Only the first failure formats and owns the pointer string, preserving the
snapshot while visitors unwind. Limits and array syntax pre-scan precedence
are unchanged.

Three PocketIC trials per version and workload use identical actor source,
manifest, frozen compiler, and runner. Every successful output hash matches
before/after; counters are identical across all three trials. All measured
phases had zero synchronous reclamation. Allocation means cumulative heap
allocation, including scratch, rather than retained heap size. Setup, four
forced GC increments, host JSON validation and typed decoder equality checks
are outside the measured interval. The decoder reply is the two-byte `ok`
validation marker, not a decoded heap size.

| Workload | Before instructions | After instructions | Reduction | Before allocated bytes | After allocated bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| record-encode | 11,270 | 8,803 | 21.89% | 768 | 776 |
| record-decode | 17,372 | 14,861 | 14.45% | 872 | 880 |
| records-empty-encode | 1,740 | 1,726 | 0.80% | 392 | 368 |
| records-empty-decode | 1,379 | 1,363 | 1.16% | 352 | 328 |
| records-one-encode | 13,129 | 9,711 | 26.03% | 928 | 896 |
| records-one-decode | 28,864 | 22,804 | 21.00% | 944 | 912 |
| nested-records-encode | 7,657,085 | 5,045,703 | 34.10% | 193,928 | 193,896 |
| nested-records-decode | 33,909,381 | 25,772,907 | 23.99% | 130,160 | 130,128 |
| records-1024-encode | 7,714,028 | 5,034,822 | 34.73% | 193,864 | 193,832 |
| records-1024-decode | 23,844,170 | 18,303,758 | 23.24% | 129,136 | 129,104 |
| blob-64k-encode | 3,257,056 | 3,257,041 | 0.00% | 175,160 | 175,136 |
| blob-64k-decode | 3,257,270 | 3,257,250 | 0.00% | 131,456 | 131,432 |
| error-small | 12,304 | 10,964 | 10.89% | 1,032 | 1,040 |
| error-escaped-key | 21,107 | 19,059 | 9.70% | 1,392 | 1,384 |
| error-late-record | 23,861,723 | 18,318,563 | 23.23% | 129,440 | 129,440 |

There are no instruction regressions in the final measurements. The small
record encoder, small record decoder, and small error allocate **8 bytes more**
(the component vector's initial capacity); the native comparison's small record
cases have the same tradeoff. Singleton/nested/large arrays allocate 32 fewer
bytes, empty/Blob/Text cases 24 fewer, and the late error is unchanged.
The earlier ~90.6% reduction in large-record decode allocation is preserved:
this round changes 129,136 to 129,104 bytes. The independent native allocation
probe for 64 nested arrays around a 256 KiB key now requests 6,336 scratch bytes
for either plain or escaped keys, versus the prior archive's 264,825/264,831.
The prior values are historical probe evidence, not new PocketIC trials.

The native comparison uses its own fixed actor and matching Bool/Text record
wire semantics. Timed operations include each library's necessary typed/tree
or Candid conversions. These costs compare complete operations, not only a
plugin boundary. Native phase counters are unchanged between baseline/final.

| Workload | serde 3.5.0 | serde-core 0.2.1 | json 1.4.0 | Final plugin | Best successful native / plugin |
| --- | ---: | ---: | ---: | ---: | ---: |
| record-encode | 299,736 | 1,683,837 | 79,183 | 9,553 | 8.29× |
| record-decode | 1,060,911 | 1,191,909 | 266,644 | 14,128 | 18.87× |
| records-1024-encode | 172,565,661 | 800,867,778 | 53,258,267 | 5,081,644 | 10.48× |
| records-1024-decode | 763,222,636 | 822,340,588 | 30,305,226,309 | 18,261,968 | 41.79× |
| text-64k-encode | 331,656,428 | 2,462,535,428 | 89,974,425 | 765,024 | 117.61× |
| text-64k-decode | stack overflow | stack overflow | 161,941,413 | 739,230 | 219.07× |

All plugin phases pass. Both versions reproduce the known `serde` and
`serde-core` 64 KiB Text decoder stack overflows in all three trials; their
failed rows remain in the raw reports, with no invented timings. Full allocation
counts, including native libraries, are in [summary.csv](summary.csv).

The first lazy-path experiment retained the generic root `fail` call during
context construction. Wasm inspection showed a 248-byte stack-to-heap context
copy, adding about 318 instructions to empty and Blob calls. That version was
rejected. Direct construction of the already-known root error removes that
copy and uses fewer instructions than the baseline. Its measurements are
preserved in [rejected-first-path.json](rejected-first-path.json). Removing
array/tuple syntax pre-scans was considered and declined because it would
change established error precedence without a simpler replacement.

Independent review also tested an actual error below a 256 KiB ignored key.
The unreserved lazy pointer grew geometrically: 1,048,952 native allocated bytes
versus baseline 524,610/524,617 (plain/escaped keys). Reserving the known raw key
length only while rendering errors reduces this to **262,537/262,543 bytes**.
The permanent exact-path/allocation regression and archived
`validation/large-error-*.txt` probes cover the correction. The input is built
outside the allocation counter. Reproduce the probe for any copied runtime
with `validation/probe-large-error.py --runtime SOURCE --out DIR`, then
`cargo test --manifest-path DIR/Cargo.toml actual_large_error_path_allocation -- --nocapture`.
This one reserve call is the only change from the separately measured version
that already eliminated the context copy.

Validation passed: 20 native Rust tests; all 10 JSON Motoko fixtures, including
source/IR/lowered-IR/Wasm paths where applicable, compile-failure expectations,
and GC canisters; 604 independent scalar cases; 161 binary/Unicode cases;
9,263 Python-derived syntax cases; and both nested-key allocation probes.
The permanent Motoko audit fixture now additionally checks a nested pointer
containing escaped Unicode, slash, tilde, a numeric object key, an empty key,
and array indices. Logs and the generated corpus manifest are in `validation/`.
The separate review is recorded in [audit.md](audit.md).

The baseline is plugin commit `093957ad1ba611384a8b998c83bd86c75b585e4f`.
The copied baseline package's recorded build commit predates that commit, so
all its recorded source hashes were checked against `git show 093957a:path`;
every source matches. Compiler `f1ccbba5e445df9db03bbc35be557187ade9b436`
and its binary are unchanged. Full compiler/source/artifact fingerprints are
in [package-baseline.json](package-baseline.json),
[package-final.json](package-final.json), and [provenance.json](provenance.json).
Raw reports embed actor, manifest, runner and Wasm hashes.

To reproduce, run from this plugin checkout inside the selected compiler's
Nix environment. The compiler shell hook requires entering Nix from its own
checkout; then `cd` to this plugin checkout. Save the baseline package before
editing, compile each actor against that saved package, then build only JSON
and compile the same actor against `dist/json`. The compiler is never rebuilt.

```sh
JSON_PLUGIN_ROOT="$PWD"
scripts/build.sh --motoko "$MOTOKO_ROOT" --skip-motoko-build json
python3 benchmarks/generate-json-optimization.py --out _build/opt-json/bench
"$MOTOKO_ROOT/bin/moc" --plugin dist/json \
  _build/opt-json/bench/main.mo -o _build/opt-json/final/main.wasm
node benchmarks/run.mjs --wasm _build/opt-json/final/main.wasm \
  --cases _build/opt-json/bench/cases.json --out _build/opt-json/final/results.json \
  --label json-final --trials 3 --delete-canisters true \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js
python3 benchmarks/generate-codec-comparison.py --codec json --out _build/opt-json/native
python3 benchmarks/build-codec-comparison.py --motoko "$MOTOKO_ROOT" \
  --deps "$CODEC_DEPS" --codec json --out _build/opt-json/native
node benchmarks/run.mjs --wasm _build/opt-json/native/main.wasm \
  --cases _build/opt-json/native/cases.json --out _build/opt-json/final/native.json \
  --label json-native-final --trials 3 --delete-canisters true \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js
cargo test -p motoko-compute-json --locked --target-dir _build/opt-json/native-tests
(cd "$MOTOKO_ROOT" && PATH="$MOTOKO_ROOT/bin:$PATH" test-runner -b \
  "$JSON_PLUGIN_ROOT/plugins/json/tests/run" \
  "$JSON_PLUGIN_ROOT/plugins/json/tests/fail" \
  "$JSON_PLUGIN_ROOT/plugins/json/tests/run-drun")
plugins/json/tests/audit/run.sh --motoko "$MOTOKO_ROOT" \
  --output "$PWD/_build/opt-json/final/audit"
python3 benchmarks/results/optimization-round/json/summarize.py
```

`CODEC_DEPS` points to the installed dependencies from the unchanged archived
`benchmarks/results/codec-comparison/dependencies/mops.{toml,lock}`. The build
helper verifies every locked file and all 20 aliases/18 packages. The native
runner exits 1 for its six expected failed measurements; inspect those exact
rows, then use the archived summarizer to validate both complete reports.
Use full plugin test paths so `test-runner` directory modes are inferred correctly.
