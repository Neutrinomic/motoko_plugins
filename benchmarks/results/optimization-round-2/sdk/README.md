# SDK: compare canonical small scalar words directly

Baseline compiler: `c320bf90d0b63a058b5de2c41a42c96e8b82243f`.
Candidate compiler: `128a41c060d473e4307dbfcce88b4587312a29b6`.
ABI remains **1**. There is no API, value representation, GC, callback, or
runtime-module change.

`Compare.scalar` no longer shifts both operands down before comparing
`Nat8/16/32`, `Int8/16/32`, or `Char`. The production patch removes one net line.
It saves **four IC instructions per affected comparison**. All allocation
counts are unchanged. Bool normalization, boxed 64-bit integers, big integers,
Text, Blob, and Principal comparisons retain their existing paths.

## Why the transformation is valid

A canonical scalar of width `w` has word representation
`value * 2^(64-w) + tag`, interpreted as signed for `Int8/16/32` and unsigned
for `Nat8/16/32` and `Char`. Both operands have the same statically selected
primitive type, so their low tag and padding bits are identical. This injective
representation preserves ordering and equality. For signed values the tag is
smaller than the payload step, so adding it cannot cross the sign boundary.
Type aliases and heap storage retain that same canonical representation.

The compiler already knows the primitive type at specialization time. There is
no new runtime tag test and no unchecked heap read. Bool is intentionally
excluded: runtime bridges permit noncanonical nonzero representations of true,
so its existing normalization remains necessary.

## Measurements

The final candidate was rebuilt and measured from the clean committed source.
The frozen baseline actor hashes were verified unchanged before reusing its raw
trials. Earlier precommit candidate runs remain under `precommit/`; they are not
relabeled as committed-compiler measurements.

`summary.csv` contains all 54 paired phases: 36 scalar-loop phases and 18 map
phases, each with three trials per compiler. `summarize.py` checks the complete
phase/trial matrix, rejects errors and duplicate samples, verifies input/runner/
Wasm hashes and the retained result, and checks allocations/reclamation before
emitting the summary.

The scalar actor compares every pair from six-value boundary vectors and six
additional pairs: 42 comparisons per repetition, with 0, 1, or 4,096
repetitions. The seven affected types save exactly 168 or 688,128 instructions;
empty loops and all five unaffected scalar controls are unchanged. This harness
includes substantial ordinary Motoko checksum arithmetic, so the complete large
loop improves only about **0.18%**. Its allocations also include that common
arithmetic; they are not attributed to the comparator.

The map actor uses the unchanged production pure-map compiler package and
wrapper from plugins revision `0df5cd2d63d4b592e08c4c7a5f9d1e76fac22152`.
It performs 1,000 static-order operations on maps with 1,000, 10,000, or 100,000
entries, for both `Nat32` and `Int32` keys. Positive and negative signed keys
are covered. Construction, input setup, forced collection, expected-value
calculation, and checking retained overwritten values occur outside timing.
These are SDK before/after comparisons, not new Core-library comparisons.

Per-call costs below divide each measured 1,000-operation batch by 1,000.

| Key | Operation | Map size | Before instructions/call | After instructions/call | Change | Allocated B/call, both |
|---|---|---:|---:|---:|---:|---:|
| Nat32 | getHit | 1,000 | 794.741 | 758.793 | -4.52% | 0.000 |
| Nat32 | getMiss | 1,000 | 921.221 | 881.313 | -4.33% | 0.000 |
| Nat32 | overwrite | 1,000 | 2,727.370 | 2,691.422 | -1.32% | 647.064 |
| Int32 | getHit | 1,000 | 864.741 | 828.793 | -4.16% | 0.000 |
| Int32 | getMiss | 1,000 | 991.221 | 951.313 | -4.03% | 0.000 |
| Int32 | overwrite | 1,000 | 2,797.370 | 2,761.422 | -1.29% | 647.064 |
| Nat32 | getHit | 10,000 | 951.797 | 903.773 | -5.05% | 0.000 |
| Nat32 | getMiss | 10,000 | 1,078.485 | 1,026.485 | -4.82% | 0.000 |
| Nat32 | overwrite | 10,000 | 3,509.487 | 3,461.463 | -1.37% | 864.432 |
| Int32 | getHit | 10,000 | 1,021.797 | 973.773 | -4.70% | 0.000 |
| Int32 | getMiss | 10,000 | 1,148.485 | 1,096.485 | -4.53% | 0.000 |
| Int32 | overwrite | 10,000 | 3,579.455 | 3,531.431 | -1.34% | 864.432 |
| Nat32 | getHit | 100,000 | 1,159.429 | 1,095.405 | -5.52% | 0.000 |
| Nat32 | getMiss | 100,000 | 1,286.117 | 1,218.117 | -5.29% | 0.000 |
| Nat32 | overwrite | 100,000 | 4,550.502 | 4,486.478 | -1.41% | 1,152.432 |
| Int32 | getHit | 100,000 | 1,229.429 | 1,165.405 | -5.21% | 0.000 |
| Int32 | getMiss | 100,000 | 1,356.117 | 1,288.117 | -5.01% | 0.000 |
| Int32 | overwrite | 100,000 | 4,620.845 | 4,556.821 | -1.39% | 1,152.432 |

Allocated bytes are cumulative allocation during each measured operation,
including temporary objects, not peak or live heap size. Synchronous
reclamation is zero. The runner forces collection before each phase and checks
the retained result afterwards.

## Checks retained and other approaches considered

- Plugin schemas, concrete specialization, generated result representations,
  ABI/toolchain compatibility, runtime import signatures and runtime layout
  are already checked during compilation/loading/linking.
- Dynamic array bounds, allocation lengths and callback argument conventions
  depend on executed values and cannot simply become build-time checks.
- Record field positions are not fixed by the expected type because Motoko
  permits width subtyping; runtime field lookup stays.
- Record/variant construction preserves the existing error-return and GC
  initialization rules. Array cursor construction was optimized in the prior
  round and was not expanded again.
- A special bignum comparison path would add branching or duplicate existing
  integer logic; this patch does not introduce it. Registry lookup caches and
  extra validation frameworks were not justified by a measured bottleneck.

## Validation and audit

Full native and JavaScript Dune build, native Dune tests, all **46** SDK fixtures,
and package-validation checks pass. The pre-existing js_of_ocaml warning for
`caml_unix_map_file_bytecode` remains; no new OCaml warning was introduced.
The added fixture exhausts all 65,536 pairs for both eight-bit domains and
checks aliases and boundary vectors for wider words and Unicode scalar values.

The independent auditor additionally exercised generic functions/closures,
mutable cells, arithmetic conversions, Candid-decoded arrays and values retained
across real GC with sanity checks enabled. Audit files contain the verdict and
exact commands. Generated test `_out` directories are not archived.

An early harness used native Bool equality as its oracle for deliberately
noncanonical `true` values. That oracle disagreed with logical Boolean equality
in **both** compiler versions. The complete rejected results and actor are
preserved under `rejected-oracle/`. The final actor uses conditionals for its
Bool oracle; no production Bool code changed. No failed sample is dropped from
a cohort or included in the accepted summary.

## Reproduce

Build the baseline and candidate compiler revisions separately, with matching
RTS files and the Nix environment described in the compiler repository. The
scripts expect this report at `_build/optimization-round-2-sdk` under the
candidate checkout; adjust the explicit baseline/plugins paths when needed.

```sh
python3 _build/optimization-round-2-sdk/generate.py
python3 _build/optimization-round-2-sdk/generate-map.py
python3 _build/optimization-round-2-sdk/build-evidence.py
python3 _build/optimization-round-2-sdk/build-map.py
```

The build scripts compile matching fixture/plugin packages into private report
subdirectories. They never rebuild or modify the baseline compiler or canonical
plugin distribution. Run the archived `run.mjs` against both versions' scalar
and map Wasm files with their adjacent `cases.json`, `--trials 3`, the CandidX
host dependency paths, and `--delete-canisters true`; then run `summarize.py`.
`artifact-manifest.json` identifies archived text/source files separately from
omitted generated binary hashes.
