# Compiler SDK optimization evidence

Baseline: `f1ccbba5e445df9db03bbc35be557187ade9b436`.
Candidate: `c320bf90d0b63a058b5de2c41a42c96e8b82243f`.
ABI remains **1**; public plugin signatures and value representations are
unchanged. The canonical baseline compiler was never rebuilt or modified.

The candidate removes repeated interpreter type specialization and retains one
array-element cursor during `Backend.Arr.tabulate`. Array size checks, complete
slot initialization, allocation barriers, and pointer write barriers remain.
Synchronous callbacks introduce no GC safepoint; memory growth preserves Wasm
offsets. Compiler-owned cursors therefore remain valid across nested callbacks.

## PocketIC instructions and allocation

Identical actor and fixture sources were compiled with separately built matching
native fixtures. Each workload used three fresh-canister trials, with input setup
and four forced GC calls before measurement. Every retained scalar and nested
element was checked outside the timed region. All three instruction samples were
identical, outputs matched, and synchronous reclamation was zero. Values below
are raw totals for one array construction, including measurement overhead.

| Elements | Element computation | Baseline instructions | Candidate instructions | Change | Allocated bytes, both |
|---:|---|---:|---:|---:|---:|
| 0 | Scalar | 561 | 562 | +1 instruction | 24 |
| 0 | Nested record/array | 561 | 562 | +1 instruction | 24 |
| 1 | Scalar | 637 | 628 | -1.41% | 32 |
| 1 | Nested record/array | 1,594 | 1,556 | -2.38% | 160 |
| 257 | Scalar | 20,093 | 17,524 | -12.79% | 2,080 |
| 257 | Nested record/array | 266,042 | 256,020 | -3.77% | 34,976 |
| 4,096 | Scalar | 311,857 | 270,898 | -13.13% | 32,792 |
| 4,096 | Nested record/array | 4,232,017 | 4,072,274 | -3.77% | 557,080 |

Nested construction creates a record and a three-element callback-generated
array for each outer element. These fixtures isolate the SDK change; integrated
production JSON/CBOR results require separate measurement. Empty arrays pay one
instruction for cursor setup. No allocation reduction is claimed.

## Interpreter timings, separately measured

One million generic opaque identity calls run through an alias and retain a
record containing arrays and a callback. The script alternates baseline and
candidate fresh processes for three trials per mode. These are median child
process CPU seconds, including startup and type checking, **not IC instructions**.

| Mode | Baseline CPU seconds | Candidate CPU seconds | Change |
|---|---:|---:|---:|
| Source (`-r`) | 2.725561 | 1.961829 | -28.02% |
| IR before await/async lowering | 2.929817 | 2.194173 | -25.11% |
| Lowered IR (`-r -iR`) | 2.953073 | 2.206180 | -25.29% |

All 18 processes completed successfully. Timings are local microbenchmark
measurements; raw CPU and wall times are in `interpreter.json`.

## Which checks stay where

The frontend validates each specialization, then source interpretation consumes
those checked annotations. Lowering carries the same metadata and the IR checker
validates it after transformations. Recomputing the schema and result type on
every interpreter execution is redundant. Value-count and callback calling
convention checks remain because they inspect values supplied at execution.

Static tuple-field access already uses direct constant offsets. Record lookup
still searches field hashes: width subtyping allows additional physical fields,
so an expected record type does not prove its exact field positions. Dynamic
array indexing still checks bounds. Loader and linker compatibility validation,
flat arguments, native tuple results, opaque values, and ordinary local callbacks
remain unchanged. No unchecked accessor or new plugin API was added.

## Validation and independent review

- All 45 compute-plugin fixtures and packaging checks passed on the committed
  native compiler, including early decoder returns during array construction.
- New tests cover empty arrays, nested callbacks, about 32 MiB of allocation
  during callbacks, memory growth, and retaining arrays across forced GC.
- Full native/JS Dune build, Dune native tests, and Nix `js.moc` and
  `js.moc_interpreter` builds/install checks passed. There were no OCaml warnings.
  The existing js_of_ocaml missing `caml_unix_map_file_bytecode` warning remains.
  This flake has no `js.didc` target; the native executable was built with Dune.
- The independent reviewer found no blocking findings, reran seven focused
  fixtures, and verified all benchmark hashes and paired outputs/allocations.
  See `independent-audit.json` and the associated logs.

`provenance.json` pins both compiler binaries, matching fixtures, actor source,
RTS files, and Wasm. `accepted.json` includes final source hashes.
`artifact-manifest.json` lists text/source files in `archive_files` and records
generated Wasm/native-plugin hashes separately in `generated_artifacts`.
Generated `.wasm` and `.cmxs` binaries are omitted from the committed archive;
the reproduction steps rebuild them.

## Reproduction

Build the pinned compiler revisions in separate checkouts in the Motoko Nix
shell, following `test/compute-plugins/build.sh`. Use the same RTS binaries for
both versions. Stage `main.mo`, `interpreter.mo`, `build-evidence.py`, and
`interpreter-benchmark.py` under the candidate checkout's `_build/opt-sdk/`.
The scripts derive the candidate root from that directory; adjust their
`baseline` constant to the frozen checkout's location. The committed callback
fixture source is also archived as `fixture_callbacks.ml`.

From the candidate root, with the repository's OCaml Bigarray compatibility
metadata on `OCAMLPATH` as configured by the fixture build script:

```sh
python3 _build/opt-sdk/build-evidence.py
python3 _build/opt-sdk/interpreter-benchmark.py
node /path/to/archive/run.mjs \
  --wasm _build/opt-sdk/baseline/main.wasm \
  --cases _build/opt-sdk/cases.json --out _build/opt-sdk/baseline.json \
  --label sdk-baseline --trials 3 \
  --sdk-package /path/to/candidx/ts/package.json \
  --canonicalizer /path/to/candidx/ts/dist/index.js
```

Repeat the last command with `candidate` replacing `baseline`. The runner needs
`pocket-ic-server`, Node, and the CandidX host dependencies; the archived runner
hash matches both reports. `committed-plugin-tests.log` records the final fixture
and packaging checks. Source and fixture compilation never write to shared
plugin distribution directories.

## Confirmed pre-existing compiler issue

The CBOR edge-case investigation exposed an ordinary Motoko constructor-identity
bug, reproduced without loading any plugin:

```motoko
actor {
  type T1 = [Bool];
  transient var value : ?T1 = null;
  public func go() : async () { value := value };
}
```

`alias-minimal.mo` fails with `free type constructor T1` after type-component
erasure. A separate compiler built from pre-plugin revision `52113d40c` also
reproduces it; see `pre-plugin-alias.log`. Its generated version metadata was
copied solely to satisfy the isolated build; source provenance is the archived
Git revision, rather than that displayed version string.

`Cons.session` restores stamp counters, while typing and lowering reopen the
same filename scope. Lowering-generated abstract `T1` can then collide with the
live source alias. A proper fix must address constructor identity across phases;
renaming generated identifiers would only hide an instance. This general
compiler issue is deferred. The SDK patch contains no workaround for it.
