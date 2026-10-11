# Pure-map second optimization round

Two local changes retain the existing algorithms, ABI 1, stable node layout,
generic payload references, callback ordering, and structural sharing:

- Native lookup follows the search path in a loop, avoiding recursive calls.
  The initial depth is the compile-time constant zero. Its known-true guard is
  omitted; every successor depth is still checked before the next iteration,
  including an empty child at depth 128.
- Stable merging retains each compared array entry in a local and writes that
  same reference to the destination, avoiding a repeated array lookup. Equal
  keys retain their original relative order and last-input-wins behavior.

There is no alternate intersection algorithm, new specialization, API, or
unchecked accessor. Update/balancing kernels and interpreter semantics are
unchanged. The production diff adds four net lines.

## Measurements

The [function comparison](functions/costs.md) covers 30 workloads at exactly
1,000, 10,000, and 100,000 entries. It includes every affected row in the previous
public-function matrix: callback get/getEntry/contains, scalar get, and shuffled
fromIter/fromArray. Sorted construction, add-overwrite, find-missing, and foldLeft
are unchanged controls. Separate [small](small/costs.md) and [empty](empty/costs.md)
comparisons cover lookup at 0, 1, and 16 entries. All 35 workloads use three trials
per version and measure both instructions and cumulative allocated/reclaimed
bytes. Allocation is not peak or post-GC live memory.

| Operation | Entries | Core instructions | Before instructions | After instructions | Reduction | Plugin allocated B |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| get-hit | 1,000 | 2,041.19 | 1,648.41 | 1,604.38 | 2.67% | 0 |
| get-hit (scalar) | 1,000 | 2,041.19 | 935.81 | 891.78 | 4.71% | 0 |
| fromIter-shuffled | 1,000 | 7,605,488 | 8,140,350 | 7,862,332 | 3.42% | 487,880 |
| fromArray-shuffled | 1,000 | 7,606,083 | 7,066,561 | 6,788,543 | 3.93% | 463,216 |
| get-hit | 10,000 | 2,736.97 | 2,189.88 | 2,129.44 | 2.76% | 0 |
| get-hit (scalar) | 10,000 | 2,736.97 | 1,234.97 | 1,174.53 | 4.89% | 0 |
| fromIter-shuffled | 10,000 | 102,601,219 | 109,854,994 | 105,596,698 | 3.88% | 6,712,416 |
| fromArray-shuffled | 10,000 | 102,601,814 | 97,527,881 | 93,269,585 | 4.37% | 6,369,896 |
| get-hit | 100,000 | 3,324.09 | 2,600.75 | 2,524.38 | 2.94% | 0 |
| get-hit (scalar) | 100,000 | 3,324.09 | 1,421.56 | 1,345.19 | 5.37% | 0 |
| fromIter-shuffled | 100,000 | 1,233,076,595 | 1,255,250,803 | 1,204,273,073 | 4.06% | 76,471,536 |
| fromArray-shuffled | 100,000 | 1,233,077,190 | 1,140,602,747 | 1,089,625,017 | 4.47% | 73,573,936 |

Across all three suites there are **504 raw measurements**: 84 implementation
phases across 35 workloads × three trials × two versions.
All trial costs were identical. No measured phase regressed in instructions;
allocation/reclamation are unchanged, no synchronous collection occurred, and
Core plus all unchanged controls have exactly identical costs.

At 100,000 entries shuffled fromIter now costs 2.34% fewer instructions than
Core and allocates 65.9% fewer bytes. It still costs 3.38% more instructions
than Core at 1,000 entries and 2.92% more at 10,000 entries. The unmodified
small-intersection tradeoff is retained in the previous report; this is not a
claim that every map operation beats Core.

The existing full matrix remains in the repository README, with its unchanged
historical measurements identified separately. This round does not relabel
previous trials as new measurements. Indirect callers isDisjoint/isSubmap and
addList/mapKeys also use the changed helpers; they have no new standalone
performance claim.

## Checks and scope

The [source snapshots](sources/) and package [build manifests](packages/) identify
both versions. Compiler source is frozen at
`c320bf90d0b63a058b5de2c41a42c96e8b82243f`, binary SHA-256
`722ba089cc3f6fb7710423363c3adc55d0af9f841eaa5a283e97eb08f3c8335c`.
The baseline plugins revision is `0df5cd2d63d4b592e08c4c7a5f9d1e76fac22152`.
Both versions use Core 2.5.0, PocketIC 14.0.0, identical actor sources, inputs,
runner, compiler, dependency lock and cleanup protocol. Exact actor, compiler,
plugin, and dependency hashes are in each suite's provenance file.

Fifteen plugin fixtures exercise the source/IR/lowered interpreters, Wasm and
IC GC behavior. The new regression test checks the last accepted native search
depth, comparator sequence with allocation and reentrancy, stable duplicate
object keys, and shared mutable/closure payloads. The existing depth trap's
Wasm expectation was regenerated with `test-runner -a`: it now has one lookup
frame instead of recursive frames. The error and trap boundary are unchanged.
See [test evidence](validation/) and the [independent audit](audit.md).

The [one-trial pilots](pilots/) measured merge and search separately before
running the final matrix. The first loop retained an always-true initial guard
and cost three extra instructions for empty/singleton lookups; the final guard
placement saves two instructions per such lookup against the original. The
intermediate small/empty results are retained, with their own source hashes.
No small-intersection special case or broad builder rewrite was introduced.

## Reproduce

Use the exact archived actor and matching source snapshot for each version,
rebuild only pure-map against the pinned compiler, and use the frozen Core lock.
`selection.json` lists the subsets selected from the unchanged archived
function/point generators; the empty actor is stored directly. The measured
actors and manifests already contain the exact selected workloads.

```sh
scripts/build.sh --motoko "$MOTOKO_ROOT" --skip-motoko-build pure-map
python3 benchmarks/build-map-comparison.py --motoko "$MOTOKO_ROOT" \
  --deps "$MAP_DEPS" --out "$ACTOR_DIR" --require-clean-compiler
node benchmarks/run.mjs --wasm "$ACTOR_DIR/main.wasm" \
  --cases "$ACTOR_DIR/cases.json" --out "$ACTOR_DIR/results.json" \
  --trials 3 --server "$POCKET_IC_14" \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js \
  --delete-canisters true
```

Revalidate each of `functions`, `small`, and `empty` with the existing validator:

```sh
python3 benchmarks/compare-map-optimization.py \
  --before "$SUITE/before" --after "$SUITE/after" --out "$TEMP_REPORT"
```

It checks every phase and three-trial sample, missing/duplicate/failed results,
oracle output, actor/input/provenance identity, and unchanged Core costs. The
[harness](harness/) is archived unchanged; no new validation framework is needed.
