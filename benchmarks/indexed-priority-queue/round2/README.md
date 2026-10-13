# IndexedPriorityQueue: algorithm optimization round 2

The accepted changes reduce scalar Nat pop instructions by **13.10% at 10,000 shuffled entries and 15.40% at 100,000**, with unchanged allocation. They cache the moving priority, use bottom-up repair for scalar pop, and skip ordinary downward repair at leaves. The binary heap representation and public API stay unchanged.

Across the five distributions at 10,000 entries, the updated plugin uses **13.04–15.38% fewer instructions for scalar Nat pop** on descending, ascending, shuffled and duplicate-heavy heaps. Equal-priority Nat pop improves by 0.30%. Nat churn improves by 6.34–9.73%, and increasing priorities through `reschedule` improves by 2.81–5.83%. Composite deadline callbacks have smaller gains; their equal-priority pop regresses by 0.30%. Allocation is unchanged in all **201 matched benchmark calls**. The small two-entry drain regresses by 0.95% (+30 instructions); the largest regression in the main 160-case matrix is 0.38%.

The comparison starts from the already optimized delivered plugin, not the initial implementation or Core libraries. The [previous comparison](../README.md) and [first three optimization passes](../OPTIMIZATION.md) remain separate.

## What changed

The updated plugin keeps the indexed binary heap and existing managed representation. It caches the moving entry's immutable priority field during sifting. This caches a managed reference when the priority contains mutable data; it does not cache a comparison result or a mutable object's contents.

Scalar `pop` uses bottom-up repair: follow the smaller-child path to the bottom, then move the replacement back up. A root comparison stops immediately when no repair is needed, protecting equal-priority heaps. Ties select the left child, and the return ascent includes equality, so the resulting entry layout matches ordinary top-down repair. Arbitrary removal, replacement and rescheduling keep ordinary repair. A leaf guard avoids loading a moving entry when ordinary downward repair has no children.

Bottom-up movement is restricted to proven scalar comparators. Custom callbacks still observe complete swaps and consistent handle indices at every callback; they benefit from priority caching and the leaf guard. No compiler/SDK, ABI, module API or persisted layout change is required. The design and rejected alternatives are described in [algorithm research](../algorithm-research-round-2.md).

## Instructions at 10,000 entries

Each row is a batch of **256 operations**, including loop/adapter overhead. Negative changes mean fewer instructions. Nat uses the scalar comparator path; deadline uses the custom `{at : Int; ticket : Nat}` comparator. Their cost difference also includes record work, so it is not an isolated measurement of callback overhead.

| Key | Initial priorities | Operation | Delivered instructions | Updated instructions | Change |
|---|---|---|---:|---:|---:|
| nat | descending | pop | 1,724,137 | 1,499,369 | -13.04% |
| nat | descending | churn | 3,035,419 | 2,739,995 | -9.73% |
| nat | descending | reschedule | 369,435 | 348,699 | -5.61% |
| nat | ascending | pop | 1,737,530 | 1,470,340 | -15.38% |
| nat | ascending | churn | 3,035,419 | 2,739,995 | -9.73% |
| nat | ascending | reschedule | 1,696,884 | 1,597,981 | -5.83% |
| nat | shuffled | pop | 1,717,248 | 1,492,264 | -13.10% |
| nat | shuffled | churn | 3,035,419 | 2,739,995 | -9.73% |
| nat | shuffled | reschedule | 502,931 | 488,823 | -2.81% |
| nat | equal | pop | 429,595 | 428,315 | -0.30% |
| nat | equal | churn | 1,713,179 | 1,604,635 | -6.34% |
| nat | equal | reschedule | 1,193,014 | 1,139,261 | -4.51% |
| nat | duplicates | pop | 1,765,434 | 1,532,703 | -13.18% |
| nat | duplicates | churn | 1,733,980 | 1,622,830 | -6.41% |
| nat | duplicates | reschedule | 543,187 | 524,753 | -3.39% |
| deadline | descending | pop | 3,049,363 | 2,948,115 | -3.32% |
| deadline | descending | churn | 5,431,067 | 5,218,075 | -3.92% |
| deadline | descending | reschedule | 466,971 | 447,515 | -4.17% |
| deadline | ascending | pop | 3,249,870 | 3,151,107 | -3.04% |
| deadline | ascending | churn | 5,361,179 | 5,148,187 | -3.97% |
| deadline | ascending | reschedule | 3,264,991 | 3,166,088 | -3.03% |
| deadline | shuffled | pop | 3,015,580 | 2,916,642 | -3.28% |
| deadline | shuffled | churn | 5,379,611 | 5,166,619 | -3.96% |
| deadline | shuffled | reschedule | 697,466 | 683,983 | -1.93% |
| deadline | equal | pop | 590,619 | 592,411 | +0.30% |
| deadline | equal | churn | 3,404,315 | 3,298,843 | -3.10% |
| deadline | equal | reschedule | 2,304,620 | 2,250,867 | -2.33% |
| deadline | duplicates | pop | 3,525,363 | 3,422,330 | -2.92% |
| deadline | duplicates | churn | 3,451,254 | 3,344,137 | -3.10% |
| deadline | duplicates | reschedule | 817,484 | 799,710 | -2.17% |

Across both measured sizes (1,000 and 10,000), 126 cases improve and 34 regress. These are case counts, not a weighted application speedup.

| Operation | Improved / regressed cases | Instruction change range |
|---|---:|---:|
| push | 0 / 20 | +0.04% to +0.06% |
| pushMin | 20 / 0 | -2.97% to -1.63% |
| pop | 18 / 2 | -15.38% to +0.30% |
| remove | 16 / 4 | -5.48% to +0.33% |
| removeShuffled | 20 / 0 | -2.53% to -1.14% |
| reschedule | 20 / 0 | -5.83% to -1.68% |
| decrease | 12 / 8 | -5.16% to +0.38% |
| churn | 20 / 0 | -9.73% to -2.62% |

Every ordinary push costs one extra instruction per operation (+256 per batch, +0.04–0.06%). The other regressions are seven extra instructions per operation (+1,792 per batch): decreasing priorities in ascending/equal heaps, removing from equal heaps, and popping equal composite deadlines. Within this 160-case matrix, the largest relative regression is **+0.38%**, for Nat decreases on equal-priority heaps. These small costs are included rather than removed from the report.

`push` adds priorities above the existing range; `pushMin` adds priority zero. `reschedule` increases the first 256 inserted entries to priorities above the original range; `decrease` changes those entries to zero. `remove` uses insertion order, while `removeShuffled` uses a deterministic stride through handles. Churn inserts a new minimum and immediately pops it. These are distinct operation scenarios, not randomized average-case performance.

## Larger heaps and small drains

The shuffled 10,000-entry pop, reschedule and churn cases above were repeated three times per implementation; all instruction and allocation counters matched exactly. At **100,000 shuffled entries**, the three-trial medians below cover 256 operations; again, every trial returned identical counters.

| Key | Operation | Delivered instructions | Updated instructions | Change |
|---|---|---:|---:|---:|
| nat | pop | 2,087,900 | 1,766,338 | -15.40% |
| nat | reschedule | 621,564 | 603,329 | -2.93% |
| nat | churn | 3,579,163 | 3,178,523 | -11.19% |
| deadline | pop | 3,749,491 | 3,620,488 | -3.44% |
| deadline | reschedule | 923,833 | 906,018 | -1.93% |
| deadline | churn | 6,430,491 | 6,163,739 | -4.15% |

Small-heap checks drain the entire shuffled Nat heap, so repetition counts differ from the 256-operation tables. The two-entry case exposes a real fixed-overhead regression; it is retained in the comparison.

| Initial entries / pop count | Delivered instructions | Updated instructions | Change |
|---:|---:|---:|---:|
| 1 | 1,777 | 1,777 | +0.00% |
| 2 | 3,147 | 3,177 | +0.95% |
| 31 | 84,839 | 83,822 | -1.20% |
| 32 | 87,872 | 86,466 | -1.60% |
| 33 | 91,980 | 90,961 | -1.11% |

## Allocation and memory

Allocation is exactly unchanged for every matched case. At 10,000 entries, the byte counts per 256-operation batch are:

| Key | Push / pushMin | Pop / remove / removeShuffled | Reschedule / decrease | Churn |
|---|---:|---:|---:|---:|
| Nat | 34,816 | 10,240 | 12,288 | 45,056 |
| Deadline | 45,056 | 10,240 | 22,528 | 55,296 |

Before- and after-operation heap snapshots also match exactly between versions. Four GC-trigger messages precede each snapshot, but all reclaimed counters are zero; these are observed heap growth figures, not retained live heap. Both versions report a 128 MiB Wasm memory high-water. This round demonstrates lower instruction cost, not lower allocation or retained memory.

## Validation and measurement limits

The approved evidence contains **201 calls per implementation**: the 160-case main matrix (two key types, two sizes, five distributions, eight operations), 18 repeated 10,000-entry calls, 18 repeated 100,000-entry calls, and five small drains. This is 171 unique scenarios per implementation, or 402 calls across both builds. Each starts with a fresh canister and excludes bounded setup messages from the measured loop. Descending and ascending priorities are 1 through n; shuffled uses `(i * 157) % n + 1`, which permutes all tested sizes; equal uses 1; duplicate-heavy uses `i % 16 + 1`. This deterministic stride is not a sample of random permutations.

For each recorded case, the host checks the measured checksum, remaining count and zero reclaimed bytes during the timed loop, then verifies sorted draining and the exact remaining priority/value multiset. All recorded baseline/updated per-case fields other than instruction cost match, including allocation, exact-entry hashes and memory observations. A deliberately broken reschedule actor failed the exact multiset assertion, confirming that the validation detects incorrect priorities even when count and value sum are unchanged ([negative control](exploratory/negative-control-v2.log)).

The separate [heap oracle](heap-oracle.json) checks exact payload identities, array layouts, owners and handle indices: 12,061 exhaustive heaps of sizes 0–12 with keys 0–2, 132,081 exhaustive pops, 400 seeded random heaps with 198,570 pops, and 80 mixed 1,000-step operation sequences. Its equality argument assumes a total scalar order and no callbacks during hole movement. This model is separate from generated-code and GC verification. Independent validation of the published artifact passed **3/3 native fixtures, 11/11 semantic Ash cases and 3/3 GC Ash cases**, including two real upgrades, mixed scalar/callback operations, allocating callbacks, duplicate-key layouts and managed payloads during an active GC cycle ([validation record](../../../packages/fast/tests/ash/coverage/IndexedPriorityQueue.round2.validation.json)).

The timed matrix does not cover every small/growth boundary, unchanged-priority updates or large scalar integers. It does not isolate each optimization's contribution or measure application throughput. No new Core-library controls were run in this round; these are improvements over the delivered plugin, not new Core speedup claims.

Two exploratory runs stopped on host expected-sum assertions: the original `Array.from` oracle appeared to retain values from the preceding distribution, while the canister sum matched the intended distribution. The precise cause remains unconfirmed. The final runner constructs priorities with an explicit loop, checks the initial sum independently with a closed-form formula, then checks the exact remaining multiset. Both complete approved matrices and all repetitions/boundary runs passed with that runner. The [original log](exploratory/delivered-validated.log), [diagnostic log](exploratory/delivered-diagnostic.log), [initial runner](exploratory/initial-runner.mjs) and [diagnostic runner](exploratory/diagnostic-runner.mjs) are preserved; exploratory results are excluded from the tables and counts above.

## Provenance

Both builds use Motoko `2.0.0-14-g92b1bdecb`, the original release RTS, identical fixed source/import paths and the same private counter harness. PocketIC is 10.0.0 with Bun 1.2.13 and `@dfinity/pic` 0.16.1.

| Version | Generator SHA-256 | Native artifact SHA-256 |
|---|---|---|
| Delivered baseline | `1cc19ed9b76753947ebe95d43a4e40ce4f5a48361b360de33600516147e91ff9` | `4cbe7359b0b4f88c6f520575ea92e9dc660e3689a20afa1a2e3344839df3c912` |
| Timed private build | `9c6a60f8f201bbd3d761d4b1da3044713b121cd1d62343d65452de01925883d5` | `94c8d35a5b9375d5e329e88bd164698176a495ba41673e7d2625a4f5e5af51db` |

The published native artifact is `87627cd033f978563ad17d991376427de4118343f5fc6b697306c500e0e6364e`, built from the same `9c6a60f8…` generator. The timed private artifact was `94c8d35a…`; these native build artifacts differ. Recompiling both timed benchmark actors with the published artifact produced **byte-identical Wasm**: Nat `a339a20b88781844add1bce62ae6cdfee8744b2eba548ba3fdc111b031d437a6`, deadline `df37cb5fd7550d9d0dfe2441684f71651218091002fbe71f9c1926645321832b` ([equivalence evidence](publication/wasm-equivalence.json)). Independent tests used the published artifact.

The exact executed runner SHA-256 is `1cd94c8c4e872a066826c168dc24e0ca41462cf67ac840e81109f7b0cbddc42c`. It matches [run.mjs](run.mjs) and each phase's `harness/executed-runner.mjs`. The separately archived `harness/run.mjs` is the earlier build-time runner, not the executed runner used for approved measurements. The build manifests retain full compiler, RTS, source, module and Wasm digests. The [acceptance manifest](acceptance-manifest.json) pins the approved raw results, runner, publication proof, oracle and diagnostic evidence.

| Approved evidence | Delivered baseline | Updated plugin |
|---|---|---|
| Main matrix: 160 calls | [JSON](results/delivered-validated/results-accepted.json) | [JSON](results/candidate-validated/results-accepted.json) |
| 10,000-entry repetitions: 18 calls | [JSON](results/delivered-validated/results-headline.json) | [JSON](results/candidate-validated/results-headline.json) |
| 100,000-entry repetitions: 18 calls | [JSON](results/delivered-validated/results-large-v2.json) | [JSON](results/candidate-validated/results-large-v2.json) |
| Small drains: five calls | [JSON](results/delivered-validated/results-boundary.json) | [JSON](results/candidate-validated/results-boundary.json) |
| Build manifest | [JSON](results/delivered-validated/build.json) | [JSON](results/candidate-validated/build.json) |
| Executed runner | [Source](results/delivered-validated/harness/executed-runner.mjs) | [Source](results/candidate-validated/harness/executed-runner.mjs) |

To run the main matrix against the current built plugin in a fresh phase:

```sh
python3 benchmarks/indexed-priority-queue/round2/build.py --phase reproduced --variants plugin --keys nat,deadline
bun benchmarks/indexed-priority-queue/round2/run.mjs --phase reproduced --variants plugin --keys nat,deadline \
  --sizes 1000,10000 --distributions descending,ascending,shuffled,equal,duplicates \
  --operations push,pushMin,pop,remove,reschedule,decrease,removeShuffled,churn --out results-accepted.json
```

The phase directory must not exist. The raw files record the remaining run options. For a new baseline/candidate comparison, use separate matching source/artifact trees via `build.py --plugin-root` and fresh phase names; do not overwrite archived evidence or build the old baseline from current sources.
