# Queue optimization round 2

The new Queue reduces instructions across the common endpoint, churn and traversal workloads while preserving bounded chunk reuse. Compared with the **already delivered plugin**, 100k-element FIFO churn uses 12.52% fewer instructions, front pops use 16.65% fewer, and forward traversal uses 9.50% fewer. Chunks shrink from 440 to 408 allocated bytes and iterator construction from 232 to 200 bytes. Core Queue remains preferable for fresh singleton/few-element queues and several read-heavy operations.

This compares complete modules. Core Queue already has O(1) endpoint operations. Packing metadata is a representation improvement also available to a Motoko implementation; native code generation is responsible for the emitted endpoint operations and direct array export, not all storage savings.

## Matched instruction and allocation results

All totals include the measured loop and checksum. Push/pop/peek totals below process 100,000 operations; churn totals process 100,000 push/pop pairs; traversal and bulk totals process 100,000 elements. Setup is outside measurement.

| Operation / size | Core instructions | Delivered plugin | New plugin | Plugin reduction | Core / new | Core allocated B | Delivered / new allocated B |
|---|---:|---:|---:|---:|---:|---:|---:|
| `push_back` / 100,000 | 99,300,314 | 64,828,362 | 60,709,612 | 6.35% | 1.64× | 9,600,000 | 1,375,000 / 1,275,000 |
| `push_front` / 100,000 | 99,300,344 | 70,628,392 | 60,709,642 | 14.04% | 1.64× | 9,600,000 | 1,375,000 / 1,275,000 |
| `pop_front` / 100,000 | 71,200,385 | 79,812,686 | 66,525,182 | 16.65% | 1.07× | 0 | 0 / 0 |
| `pop_back` / 100,000 | 71,200,415 | 74,012,716 | 66,725,212 | 9.85% | 1.07× | 0 | 0 / 0 |
| `peek_front` / 100,000 | 35,500,459 | 46,800,466 | 41,300,466 | 11.75% | 0.86× | 0 | 0 / 0 |
| `peek_back` / 100,000 | 35,500,489 | 47,200,496 | 41,900,496 | 11.23% | 0.85× | 0 | 0 / 0 |
| `fifo_churn` / 100,000 | 167,500,519 | 135,668,063 | 118,680,429 | 12.52% | 1.41× | 9,600,000 | 440 / 408 |
| `lifo_churn` / 100,000 | 167,500,549 | 187,702,468 | 177,102,334 | 5.65% | 0.95× | 9,600,000 | 440 / 408 |
| `both_ends_churn` / 100,000 | 174,250,579 | 170,402,498 | 153,702,364 | 9.80% | 1.13× | 9,600,000 | 440 / 408 |
| `values` / 100,000 | 26,901,159 | 32,383,088 | 29,307,931 | 9.50% | 0.92× | 96 | 232 / 200 |
| `reverse_values` / 100,000 | 53,901,733 | 32,401,868 | 29,339,211 | 9.45% | 1.84× | 4,000,192 | 232 / 200 |
| `from_array` / 100,000 | 89,401,414 | 73,130,371 | 69,011,621 | 5.63% | 1.30× | 9,600,120 | 1,375,304 / 1,275,304 |
| `to_array` / 100,000 | 27,201,860 | 8,785,756 | 8,657,631 | 1.46% | 3.14× | 800,160 | 800,024 / 800,024 |
| `clone` / 100,000 | 105,302,036 | 76,312,160 | 69,118,253 | 9.43% | 1.52× | 9,600,216 | 1,375,384 / 1,275,352 |

None of the 140 measured cases regressed in instruction count versus the delivered plugin.

| Operation / size | Core instructions | Delivered plugin | New plugin | Plugin reduction | Core / new | Core allocated B | Delivered / new allocated B |
|---|---:|---:|---:|---:|---:|---:|---:|
| `push_back` / 1 | 1,307 | 3,002 | 2,831 | 5.70% | 0.46× | 96 | 440 / 408 |
| `push_back` / 4 | 4,286 | 4,742 | 4,460 | 5.95% | 0.96× | 384 | 440 / 408 |
| `push_back` / 16 | 16,202 | 11,702 | 10,976 | 6.20% | 1.48× | 1,536 | 440 / 408 |

Fresh singleton/few-element queues still favor Core: a first plugin chunk allocates 408 B versus 96 B per Core node. Queue-record creation is outside the push measurement. At 16 items the chunk saves both instructions and allocation; reuse also changes the tradeoff. Peeks, forward iteration and full-boundary LIFO churn remain slower than Core in the 100k matrix despite improving versus the delivered plugin. Use complete application measurements for integration decisions.

## Measured experiments and decisions

1. **Accept endpoint code-generation cleanup.** Inline peeks bind the argument once. Pop loads the slots array once and reuses that managed reference for checked read and clearing. The initial unchanged-layout candidate reduced 100k front-pop instructions from 79,812,686 to 76,012,686. SDK bounds checks, object forwarding and pointer write barriers remain.
2. **Accept packed chunk metadata.** One Nat32 stores the start slot in its low five bits and count (0..32) above them. Updating one mutable field removes 32 B per chunk and reduces endpoint work. On top of the first candidate, FIFO improves from 131,868,063 to 118,680,429 instructions. The branchless packed front peek was about 0.99% slower than the simpler unchanged-layout candidate; the layout was accepted for broad endpoint/storage gains, not a claim that every isolated change wins.
3. **Reject branchless retained-empty peeks; retain an explicit zero-count guard.** The first shortcut made retained-empty back peeks 50 instructions per call slower than delivered. With one packed metadata load and the guard restored, both retained-empty peeks save 52 instructions per call. Nonempty guarded peeks spend a small extra amount versus the branchless packed experiment, but remain faster than delivered.
4. **Accept packed transient cursor state.** Store the next index and remaining count in one captured Nat32 rather than two mutable cells. Forward traversal improves from 32,273,713 to 29,307,931 instructions after chunk packing; clone also benefits. Iterator construction allocates 200 B, including closure/captured state, versus the delivered 232 B. Cached slots are still cleared immediately when a chunk is exhausted.

The [algorithm review](algorithm-research-round-2.md) compared fixed linked blocks with array rings, block directories and endpoint-index designs using primary implementation sources. The current circular-block deque keeps endpoint work bounded without resizing/copying all references. Native bulk builders and a special singleton representation remain possible later experiments; neither was needed for these measured gains.

## Empty queues and retention

The separate empty gate measures never-created, drained-from-front, drained-from-back and cleared queues, then validates reuse. All 16 cases × 2 fresh-actor trials passed, with zero allocation/reclamation during timed calls. Drained-front and drained-back results agree. Fresh/cleared peeks save six instructions per call; fresh/cleared pops are unchanged.

| Retained-empty operation, 1,024 calls | Delivered | Final | Saved per call |
|---|---:|---:|---:|
| `peek_front` | 326,993 | 273,745 | 52 |
| `peek_back` | 327,023 | 273,775 | 52 |
| `pop_front` | 327,053 | 279,949 | 46 |
| `pop_back` | 327,083 | 279,979 | 46 |

The [controlled-pressure memory probe](results/round2-memory-final/report.json) uses distinct 4 KiB payloads and closes the RTS allocation partition before comparing occupied heap with matched empty baselines. Allocation counters are not live-memory measurements.

| Occupied heap above matched empty baseline | Core | Delivered plugin | New plugin |
|---|---:|---:|---:|
| 4,096 distinct 4 KiB payloads | 17,432,576 B | 17,095,680 B | 17,091,584 B |
| One payload after draining, plus plugin spare | 4,256 B | 5,040 B | 4,976 B |
| Empty after draining | 0 B | 440 B | 408 B |
| After clear | 0 B | 0 B | 0 B |

The full queue has 128 chunks; its 4,096 B improvement is exactly 32 B per chunk. Three refill/clear cycles return to the exact empty baseline. Across 12,288 churn operations at 33 live entries, occupied heap does not grow and the spare retains no payloads or links. Both implementations reach 384 MiB linear-memory high-water because of deliberate collection pressure; that is unchanged and is not the live queue size. Gross allocation/reclamation includes this pressure and is not reported as operation allocation cost.

## Correctness and stable representation

The benchmark canister Wasm shrinks from 284,748 to 283,695 bytes (100,028 to 99,373 bytes gzipped). This is the combined benchmark artifact, not a universal size estimate for every application.

The public API is unchanged. All payload slots and links remain managed storage, with conservative Any physical writes for generic payloads. Metadata satisfies `start = meta & 31`, `count = meta >> 5`, `count <= 32`. A detached spare has zero metadata and cleared slots/links. The retained empty endpoint may retain its start bits, with count zero and all slots cleared.

This preproduction change replaces chunk `start`/`count` fields with `meta`, so it **changes the stable storage shape**. Existing queues from the previous experimental representation need explicit migration or recreation; no legacy adapter was added. New-format upgrades are tested separately from compatibility with the previous format.

The independent source audit found no confirmed correctness or memory-safety issue and independently checked 4,096 valid metadata transitions and 2,048 cursor start states. Three focused native fixtures passed before publication. Final independent validation passed four native fixtures, eight Ash checks and two actual upgrades with persisted packed-layout queues/spare reuse. The expansion includes 192 geometry scenarios (all 32 start offsets, sizes 31/32/33, both drain directions), peeks after every pop, and heterogeneous Any values/native exports across GC. Wrong-end and drained-peek mutation controls failed as intended. See [round-2 validation evidence](../../packages/fast/tests/ash/coverage/QueueCollection.round2.validation.json) and [test coverage](../../packages/fast/tests/ash/coverage/QueueCollection.md).

## Reproduction and provenance

- Compiler PR revision `92b1bdecbc7bc67fd51ad226f8d147d15494fc09`, original release RTS, ABI 1; no compiler/SDK changes in this round. Core Queue 2.6.2 is unchanged.
- Delivered and final matrices each cover 14 operations × 10 sizes (0,1,4,16,31,32,33,1k,10k,100k) × 3 trials × 2 implementations: 840 measured calls per matrix. Every repeated counter matched exactly, every timed call reported zero reclaimed bytes, and Core controls matched every candidate.
- A fresh canister is used for each implementation/case/trial, alternating implementation order. Configuration and four forced GC increments precede timing. Performance counters include dispatch/loop/wrapping Nat32 checksum and exclude reply encoding/end-message GC. Complete resulting arrays are checked against an independent JS model.
- Churn runs max(1,024,size) pairs; peeks run max(1,size) reads. Bulk counts are elements processed, not repeated API calls. Zero-size cases measure empty-result/dispatch overhead.
- All candidate source/module/native/Wasm artifacts are archived. Candidates build in private stages; shared production sources were never rolled back. Final published native `c6e8927021cbf3d5206c2c5d09378feb3f9d769a8913538610a3bc819cbb2ae7` and module `558f7ddcb66cd9b636b9449fc4d5dc180639baa69edaf37e90f3e43d74ba3ca8` exactly match the accepted measured candidate. Compiling the published inputs at the same harness paths produced byte-identical Wasm `2abdb973b1cefe30ffd91c75608c6f4a67e3d6960570ee3836df3b4cc91e104e`.
- Source hashes in native build metadata, compiler/RTS/Core hashes and runner hashes are checked. The full current-baseline control is [round2-control-full](results/round2-control-full/results.json), final is [round2-final](results/round2-final/results.json), and intermediate archives are `round2-peek-pop`, `round2-packed`, `round2-packed-guards`, and `round2-packed-cursor`. First-delivery results remain [historical](README.md).

```sh
python3 benchmarks/queue/build.py my-new-label
bun benchmarks/queue/run.mjs --label my-new-label --sizes 0,1,4,16,31,32,33,1000,10000,100000 --trials 3
bun benchmarks/queue/empty.mjs --variants my-new-label
bun benchmarks/queue/memory.mjs --out benchmarks/queue/_out/my-memory.json
python3 benchmarks/queue/summarize_round2.py
```

[All 140 matched instruction/allocation rows](ROUND-2-RESULTS.md).
