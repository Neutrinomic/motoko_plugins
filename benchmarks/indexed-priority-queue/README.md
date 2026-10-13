# Indexed priority queue performance

PocketIC instruction and allocation comparisons for `mo:fast/IndexedPriorityQueue`, Core 2.6.2 `PriorityQueue`, Core `Map`, and `mo:fast/Map`. The queue is a minimum heap; the Core priority queue comparator is reversed to match. Maps use a priority-key index for cancellation/rescheduling. Core PriorityQueue has no equivalent handle operations, shown as —.

All table operations run 256 times against a prefilled queue. Priorities are distinct; the custom deadline comparator orders `{at : Int; ticket : Nat}`. Setup inserts descending priorities outside the measured section; these are specific operation workloads, not an application throughput prediction.

Nat and Int comparators use compiler-proven scalar dispatch. Composite deadlines use a normal Motoko callback. The latter also incur record construction/extraction costs, so comparing key types does not isolate callback overhead alone.

Push appends priorities above the existing range. Remove and reschedule target the first inserted handles (the largest original priorities). Churn inserts a new minimum and immediately pops it. These are deterministic scenarios, not randomized average-case claims.

| Priority / existing entries / operation | Core PriorityQueue instructions | Core Map instructions | fast Map instructions | IndexedPriorityQueue instructions |
|---|---:|---:|---:|---:|
| nat / 1,000 / peekPriority | 213,531 | 1,258,779 | 430,875 | 160,539 |
| nat / 1,000 / get | — | 1,246,102 | 542,918 | 201,499 |
| nat / 1,000 / push | 588,652 | 1,929,756 | 880,142 | 520,668 |
| nat / 1,000 / pop | 3,923,952 | 4,869,966 | 1,548,873 | 1,281,977 |
| nat / 1,000 / remove | — | 2,178,411 | 851,313 | 565,767 |
| nat / 1,000 / reschedule | — | 4,941,267 | 1,981,661 | 372,285 |
| nat / 1,000 / churn | 6,565,915 | 7,704,347 | 2,620,699 | 2,299,675 |
| nat / 10,000 / peekPriority | 213,531 | 1,426,459 | 538,651 | 160,539 |
| nat / 10,000 / get | — | 1,753,494 | 719,046 | 201,499 |
| nat / 10,000 / push | 567,089 | 2,475,804 | 1,088,782 | 422,939 |
| nat / 10,000 / pop | 5,582,368 | 5,679,749 | 1,828,556 | 1,724,137 |
| nat / 10,000 / remove | — | 2,863,008 | 1,059,811 | 628,935 |
| nat / 10,000 / reschedule | — | 6,171,912 | 2,389,401 | 369,435 |
| nat / 10,000 / churn | 9,218,331 | 7,979,547 | 2,789,659 | 3,035,419 |
| nat / 100,000 / peekPriority | 213,531 | 1,426,459 | 538,651 | 160,539 |
| nat / 100,000 / get | — | 2,016,150 | 805,830 | 201,499 |
| nat / 100,000 / push | 566,310 | 2,738,460 | 1,175,566 | 422,939 |
| nat / 100,000 / pop | 6,828,679 | 5,953,931 | 1,917,504 | 2,055,451 |
| nat / 100,000 / remove | — | 3,137,778 | 1,144,529 | 717,856 |
| nat / 100,000 / reschedule | — | 6,709,338 | 2,564,197 | 369,435 |
| nat / 100,000 / churn | 11,210,779 | 8,540,187 | 2,967,835 | 3,579,163 |
| deadline / 10,000 / peekPriority | 220,443 | 1,433,371 | 545,563 | 172,571 |
| deadline / 10,000 / get | — | 2,210,806 | 1,340,535 | 201,499 |
| deadline / 10,000 / pop | 6,363,927 | 6,029,921 | 2,433,004 | 3,049,363 |
| deadline / 10,000 / remove | — | 3,391,312 | 1,778,291 | 770,008 |
| deadline / 10,000 / reschedule | — | 7,399,599 | 3,809,178 | 466,971 |
| deadline / 10,000 / churn | 10,619,675 | 8,828,187 | 4,141,083 | 5,431,067 |

Indexed handles make get and reschedule substantially cheaper in these scenarios, but the existing fast Map can be cheaper for pop and churn: at 100,000 Nat entries, IPQ pop takes 7.2% more instructions; with 10,000 composite deadlines, pop takes 25.3% more. Choose by the complete workload.

Allocation counts include the return value required by each operation. `IndexedPriorityQueue.peek` and `get` return fresh `(priority, value)` pairs (40 bytes in these cases); `peekPriority` avoids that pair. Active handles retain their queue; removal and clear detach them. Clear is O(n), because it invalidates all handles, unlike Core PriorityQueue/Map clear. At 100,000 entries, a single clear costs 12,301,318 IPQ instructions versus 914 for fast Map (these clear figures are one call, not 256).

| Nat / 10,000 existing entries / operation | Core PriorityQueue allocated bytes | Core Map allocated bytes | fast Map allocated bytes | IndexedPriorityQueue allocated bytes |
|---|---:|---:|---:|---:|
| peek | 0 | 159,744 | 0 | 10,240 |
| peekPriority | 0 | 159,744 | 0 | 0 |
| get | — | 42,464 | 10,240 | 10,240 |
| push | 22,576 | 81,984 | 15,760 | 34,816 |
| pop | 250,928 | 294,560 | 0 | 10,240 |
| remove | — | 145,168 | 10,240 | 10,240 |
| reschedule | — | 255,672 | 25,632 | 12,288 |
| replace | — | 255,672 | 25,632 | 22,528 |
| churn | 399,360 | 354,304 | 10,240 | 45,056 |

Memory observations below are after setup and before the measured operation: the RTS heap delta after four requested GC increments and the Wasm memory high-water. The original RTS may leave open partitions uncollected, so **the heap delta is not a live retained-heap measurement**. It includes handle/index arrays and prior setup garbage. Core PriorityQueue has no handle index and therefore implements fewer capabilities. Separate GC and stale-handle reachability tests are described in [test coverage](../../packages/fast/tests/ash/coverage/IndexedPriorityQueue.md). GC histories also differ: Core PriorityQueue had reclaimed 57,161,664 bytes at these snapshots, while the other three had reclaimed zero.

| Nat / 100,000 entries | Observed heap delta after GC requests | Wasm memory bytes |
|---|---:|---:|
| core-pq | 6,531,112 | 201,326,592 |
| core-map | 33,388,280 | 134,217,728 |
| fast-map | 7,440,848 | 134,217,728 |
| plugin | 16,579,360 | 134,217,728 |

Three measured optimization passes and their accepted/rejected tradeoffs are in [OPTIMIZATION.md](OPTIMIZATION.md). Final `peekPriority` is a separate small API addition justified by Reactor deadline lookahead; it adds no stored state. The compiler/SDK and ABI version were unchanged.

The final comparison contains 514 checked calls across 418 implementation/key/size/operation combinations. Every case validates the measured result and drains remaining entries in sorted order, checking exact count and sum. Sizes include 0, 1, 32, 1,000, 10,000 and 100,000; the raw results contain individual operations and repetition counts. Tables use the median of available observations: 402 combinations have one trial; 16 headline combinations at 10,000 entries have the original trial plus two three-trial blocks. Every repeated instruction/allocation counter matches exactly.

Measurement uses fresh canisters, fixed source/import/plugin paths, explicit compiler and original RTS hashes, frozen native artifacts, and bounded setup messages. Performance counters cover the operation loop and adapter overhead; setup, replies and message-end GC are excluded. Allocation and reclaimed-byte deltas are separate. No instruction-limit overrides were used.

One completed repeated run logged a PocketIC server shutdown error after all results had been written. The 48-case block was rerun with clean shutdown; every instruction/allocation result matched exactly. Both raw runs are retained.

Reproduce (the target directory must not already exist):

```sh
python3 benchmarks/indexed-priority-queue/build.py --phase reproduced
bun benchmarks/indexed-priority-queue/run.mjs --phase reproduced
```

Raw evidence: [build manifest](results/final/build.json), [0–10,000 Nat/deadline cases](results/final/results.json), [100,000 Nat cases](results/final/results-large.json), [Int cases](results/final/results-int.json), [repeated headline cases](results/final/results-repeated.json), [repeat confirmation](results/final/results-repeated-confirmation.json).
