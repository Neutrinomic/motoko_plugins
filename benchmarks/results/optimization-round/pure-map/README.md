# Pure-map wrapper optimization

The same benchmark actors compare the original wrapper with a shorter wrapper
using bounded fixed-width depth counters, direct fold helpers, lazy cursor
descent, and separate merge-tail copies. The compiler, native kernels, ABI 1,
node/stable representation, generic managed keys and values, callback semantics,
and structural sharing are unchanged.

The [public-function table](functions/costs.md) covers all **111 workloads** at
exactly **1,000, 10,000, and 100,000 entries**, including actual get/add/find,
construction, folds, cursor creation, full consumption, and bounded seeks.
[Earlier point workloads](point/costs.md) add 32 cases at 16/256/4,096/65,536
entries, and [bulk workloads](bulk/costs.md) add 24 cases at
256/4,096/65,536. Each build runs three trials: 501 fresh canisters and 1,152
measurements. Both builds use PocketIC 14.0.0 and Core 2.5.0. Raw results,
manifests, actor sources, provenance, and validation are retained beside each
table; the earlier report archives were not changed.
All trial costs were identical, no synchronous collection occurred, and no
measured phase regressed in instructions or increased allocation versus the
original wrapper. Core costs also matched exactly between builds.

At 1,000 entries, complete-operation costs are:

| Operation | Before instructions | After instructions | Core instructions | Before allocated B | After allocated B | Core allocated B |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| foldLeft / foldRight | 461,310 | 312,965 | 315,007 | 72 | 0 | 0 |
| entries, create + full consumption | 1,237,767 | 1,134,244 | 1,608,622 | 40,440 | 40,400 | 256,176 |
| entries, one retained cursor | 5,653.38 | 2,363.38 | 1,072.38 | 440 | 400 | 176 |
| reverseEntries, one retained cursor | 6,801.38 | 2,471.38 | 1,078.38 | 440 | 400 | 176 |
| find, missing predicate match | 453,304 | 329,278 | 1,616,602 | 72 | 72 | 256,176 |
| map | 618,972 | 504,947 | 629,222 | 72,072 | 72,072 | 88,112 |
| fromIter, shuffled | 8,364,890 | 8,140,350 | 7,605,488 | 487,880 | 487,880 | 1,394,952 |
| fromArray, shuffled | 7,291,101 | 7,066,561 | 7,606,083 | 463,216 | 463,216 | 1,395,104 |

Fold instructions fall about 32%, and their private traversal closure no longer
allocates. Forward cursor creation improves 58.2–71.3%, and full consumption
improves about 8.4%. Lazy cursors improve creation **and** complete consumption and seeks;
this is more than moving work to the first `next()`. They still allocate their
bounded stack and snapshot when created. Creation remains more expensive than
Core's cursor. Whole-map snapshot metadata remains more expensive than simply
retaining Core's persistent root.

All 32 earlier point workloads have exactly unchanged instruction and allocation
counts on callback and scalar paths. Bulk scans improve 6.2–9.8%, filter-all
34.6–35.2%, filter-half 16.8–17.1%, union-small 2.1–2.5%, and intersection-small
7.4–7.8%. Set-operation allocation is unchanged. The small 256-entry intersection
still loses: **80,690 instructions / 12,184 allocated bytes**, versus Core's
**57,509 / 6,016**. Its sharing-preserving algorithm was retained.

Shuffled `fromIter` improves 2.7–3.3%, but remains 1.8–7.1% slower than Core,
with about 64–66% lower allocation.
The stable sort, duplicate compaction, last comparator-equal key/value policy,
and sorted-input fast path remain intact. Sorted construction is unchanged.
The full tables keep every result, including losses and operations whose costs
did not change. Allocation means cumulative bytes, including temporary garbage;
these measurements do not establish peak or post-GC live memory.

## Why these changes

Each private depth counter starts at zero and is checked against 128 before it
increments. Its only reachable values are therefore 0 through 129; the wrapping
`Nat32` increments cannot wrap. The recursive traversals preserve the previous
`depth > 128` boundary, including empty-child calls. Inlining that small guard avoids a helper call on every
visited node. Fold recursion passes the callback directly instead of capturing
it in a per-invocation recursive closure.

The cursor now has one descent loop rather than separate push, spine, and initial
seek paths. It retains the same snapshot, stores ordinary managed references,
and skips ranks in the requested direction before returning entries. Bounds and
advertised height are still checked at creation; descent checks occur when the
cursor advances. The lazy cursor can therefore reject a forged tree at a
different time or path than the previous eager seek. Stable merging compares while both runs have entries, then
copies the remaining tail without repeating merge conditions.

[Focused experiments](experiments/) preserve raw one-trial results, exact wrapper
snapshots, source hashes, and manifests. Moving fold recursion to direct helpers
alone improved the 1,000-entry fold by 5.3%. Extra branches to avoid empty-child
calls gave little additional benefit and were rejected. Fixed-width counters
provided the larger improvement without those branches. Retaining a separate
depth-check helper was also slower than the inline guard. No additional builder
abstraction, repeated-insertion constructor, or alternate intersection algorithm
was introduced.

## Reproduction and validation

The frozen compiler is `f1ccbba5e445df9db03bbc35be557187ade9b436`, binary SHA-256
`375484d8cb78891111b1a7c1700ac2bc31e71226b23a11583a5d22d973da1aa8`.
The [before wrapper](sources/before/Map.mo) hashes to
`4181cd24963d507611c1c9da5bf5b57ba1e350f10a46143c1a2a99714ef7f77c`;
the [after wrapper](sources/after/Map.mo) hashes to
`f653cbdbcfbfa456db5ddc78d6113ca8d926a39d6e435aa30991dc53fd9b888c`.
Compiler source and support hashes, plugin package hashes, and complete pinned
Core file hashes are in each provenance file. The alternate dependency cache's
Core 2.5.0 files were verified against its lock before every compilation.
The rebuilt native package has a different binary hash because it was built in
this worktree. Recompiling all three original actors with that package and the
original wrapper produces [byte-for-byte identical Wasm](package-rebuild-validation.json).

The original package, wrapper, and compiled actors were preserved under
`_build/opt-pure-map/baseline` before editing. Only the pure-map package was built:

```sh
scripts/build.sh --motoko "$MOTOKO_ROOT" --skip-motoko-build pure-map
```

Use the archived actor source and corresponding wrapper snapshot to reproduce
each build. The harness sources are [preserved here](harness/); the existing
build helper validates compiler/plugin/dependency source hashes. For each suite:

```sh
python3 benchmarks/build-map-comparison.py --motoko "$MOTOKO_ROOT" \
  --deps "$MAP_DEPS" --out "$ACTOR_DIR" --require-clean-compiler
node benchmarks/run.mjs --wasm "$ACTOR_DIR/main.wasm" \
  --cases "$ACTOR_DIR/cases.json" --out "$ACTOR_DIR/results.json" \
  --label final --trials 3 --server "$POCKET_IC_14" \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js \
  --delete-canisters true
python3 benchmarks/compare-map-optimization.py \
  --before "$BEFORE_DIR" --after "$AFTER_DIR" --out "$COMPARISON_DIR"
```

All before/after suites use identical actor source, inputs, compiler, dependencies,
runner, and cleanup protocol. Core costs match exactly. The comparison validator
checks every phase and three-trial sample, oracle digest, artifact identity, and
missing/duplicate/failed measurement before producing the tables. Full actor
validation checks outputs, stored keys, retained update histories, callback
counts/order, and all iterator contents outside the measured interval.

All 14 pure-map tests passed without warnings. The suite retains its independent sorted-array oracle, randomized
histories, scalar boundary tests, metadata traps, generic payloads, allocating
callbacks, and GC tests. New tests cover the last accepted fold depth and the
next rejected depth in both directions, plus unstarted and partially consumed
forward/reverse cursors with closure and mutable payloads across forced GC.
The independent audit additionally enumerates every rank interval for sizes
0 through 24 and checks last-wins duplicate object keys against a separate
arithmetic oracle in all interpreters and Wasm.
See the [test record](validation/tests.json), [test log](validation/tests.log), and
[independent audit](audit.md), including its small PocketIC repeat measurements.
