# IndexedPriorityQueue: three measured optimization passes

Two changes were retained: caching heap entries during repair, and moving entries through a hole when the compiler proves the comparator is a built-in scalar comparator. Together they reduce Nat pop instructions by **24.75–27.45%** and Nat churn by **27.04–29.88%** in this matrix, with unchanged allocation. Composite deadline callbacks improve by **7.78–8.30%** for pop and **7.98–8.58%** for churn. Push, reschedule and replace have small regressions, shown below.

The corrected baseline already contains the native/reference comparator parity fix. That correctness fix is not counted as an optimization. The subsequent `peekPriority` addition and the final comparison against Core libraries are separate from these three passes.

| Pass | Change | Decision and measured tradeoff |
|---|---|---|
| 1 | Mutable priority/value fields inside each heap entry | **Rejected.** Saves 48 allocated bytes per reschedule/replace, but adds 48 bytes per created entry; push costs 11.36–16.67% more instructions, pop 3.44–4.94% more, and churn 4.13–6.03% more. |
| 2 | Cache moving, parent and child entries instead of repeatedly loading them | **Accepted, based on the original immutable-entry baseline.** Pop improves 7.78–11.75%, churn 7.98–11.85%; allocation is unchanged. Keeps complete swaps and the existing callback observation points. |
| 3 | Move one ancestor/child per sift step and write the moving entry at its final position | **Accepted on top of pass 2, only for proven scalar comparators.** Nat pop improves another 15.61–17.80%, churn another 18.10–20.45%; allocation is unchanged. Custom callbacks retain complete swaps and are instruction-for-instruction unchanged in this matrix. |

Each run contains the same **24 cases**: Nat and composite `{at; ticket}` priorities, 1,000 and 10,000 starting entries, six operations, 256 iterations per case, one trial. A fresh canister is filled with descending unique priorities outside the measured loop. Measurements use `performanceCounter(0)` and allocation deltas, including loop/adapter overhead and excluding reply encoding and end-of-message GC. Churn is one push plus one pop per iteration. Every case checks the measured checksum and then drains in sorted order, checking exact count and value sum; all 96 cases passed.

These are deterministic instruction measurements for this workload, not a latency or statistical throughput study. The push case appends larger priorities, so it usually requires no upward movement. The reschedule case moves selected large priorities upward in value; it is not a worst-case downward or upward repair benchmark.

## Instruction costs for every case

Negative percentages mean fewer instructions. Pass 1 and pass 2 compare with baseline; pass 3 compares with pass 2 because pass 1 was reverted. The final column compares the accepted pass 3 result with baseline. Per-iteration values are batch totals divided by 256.

| Key | Entries | Operation | Baseline instructions/iteration | Pass 1 Δ | Pass 2 Δ | Pass 3 Δ | Accepted total Δ |
|---|---:|---|---:|---:|---:|---:|---:|
| nat | 1,000 | push | 2,025.86 | +13.53% | +0.15% | +0.25% | +0.39% |
| nat | 1,000 | pop | 6,654.40 | +4.73% | -10.83% | -15.61% | -24.75% |
| nat | 1,000 | remove | 2,314.51 | +2.39% | -2.06% | -2.51% | -4.51% |
| nat | 1,000 | reschedule | 1,422.05 | -14.72% | +1.91% | +0.35% | +2.26% |
| nat | 1,000 | replace | 1,756.05 | -5.71% | +1.55% | +0.28% | +1.83% |
| nat | 1,000 | churn | 12,313.11 | +6.03% | -10.92% | -18.10% | -27.04% |
| nat | 10,000 | push | 1,644.11 | +16.67% | +0.18% | +0.30% | +0.49% |
| nat | 10,000 | pop | 9,283.28 | +4.94% | -11.75% | -17.80% | -27.45% |
| nat | 10,000 | remove | 2,705.97 | +2.60% | -3.96% | -5.47% | -9.21% |
| nat | 10,000 | reschedule | 1,409.11 | -14.90% | +2.06% | +0.35% | +2.41% |
| nat | 10,000 | replace | 1,743.11 | -5.79% | +1.66% | +0.28% | +1.95% |
| nat | 10,000 | churn | 16,909.11 | +5.67% | -11.85% | -20.45% | -29.88% |
| deadline | 1,000 | push | 2,411.86 | +11.36% | +0.12% | 0.00% | +0.12% |
| deadline | 1,000 | pop | 9,166.10 | +3.44% | -7.78% | 0.00% | -7.78% |
| deadline | 1,000 | remove | 2,622.07 | +2.11% | -1.82% | 0.00% | -1.82% |
| deadline | 1,000 | reschedule | 1,814.32 | -11.54% | +1.50% | 0.00% | +1.50% |
| deadline | 1,000 | replace | 2,148.32 | -4.67% | +1.27% | 0.00% | +1.27% |
| deadline | 1,000 | churn | 16,761.11 | +4.43% | -7.98% | 0.00% | -7.98% |
| deadline | 10,000 | push | 2,030.11 | +13.50% | +0.15% | 0.00% | +0.15% |
| deadline | 10,000 | pop | 12,989.94 | +3.53% | -8.30% | 0.00% | -8.30% |
| deadline | 10,000 | remove | 3,115.01 | +2.26% | -3.44% | 0.00% | -3.44% |
| deadline | 10,000 | reschedule | 1,795.11 | -11.70% | +1.62% | 0.00% | +1.62% |
| deadline | 10,000 | replace | 2,129.11 | -4.74% | +1.36% | 0.00% | +1.36% |
| deadline | 10,000 | churn | 23,206.11 | +4.13% | -8.58% | 0.00% | -8.58% |

## Allocation and heap observations

Allocated bytes per iteration are below. Each cell is **baseline → rejected pass 1**. Both accepted passes have exactly the baseline allocation in all 24 cases. The larger push allocation at 1,000 entries includes crossing a heap-array capacity boundary during the batch. Deadline operations also allocate their composite priority records.

| Key | Entries | Push | Pop | Remove | Reschedule | Replace | Churn |
|---|---:|---:|---:|---:|---:|---:|---:|
| nat | 1,000 | 200.09 → 248.09 | 40 → 40 | 40 → 40 | 48 → 0 | 88 → 40 | 176 → 224 |
| nat | 10,000 | 136 → 184 | 40 → 40 | 40 → 40 | 48 → 0 | 88 → 40 | 176 → 224 |
| deadline | 1,000 | 240.09 → 288.09 | 40 → 40 | 40 → 40 | 88 → 40 | 128 → 80 | 216 → 264 |
| deadline | 10,000 | 176 → 224 | 40 → 40 | 40 → 40 | 88 → 40 | 128 → 80 | 216 → 264 |

Before-operation heap growth relative to the empty canister:

| Key | Entries | Baseline / pass 2 / pass 3 bytes | Rejected pass 1 bytes | Difference |
|---|---:|---:|---:|---:|
| nat | 1,000 | 233,016 | 281,016 | +48,000 |
| nat | 10,000 | 1,775,640 | 2,255,640 | +480,000 |
| deadline | 1,000 | 273,016 | 321,016 | +48,000 |
| deadline | 10,000 | 2,175,640 | 2,655,640 | +480,000 |

The extra observed growth in pass 1 is exactly **48 bytes per inserted entry**. Four GC-trigger messages were requested before snapshots, but every recorded reclaimed counter remained zero. These figures therefore describe observed heap growth, including garbage and harness state; they do **not** establish retained live heap after collection. All four versions report the same 128 MiB Wasm memory high-water value. Separate GC/retention tests are needed for payload-release guarantees.

## Reproduction and provenance

The archived build manifests contain compiler commands and full SHA-256 digests for the compiler, RTS, imported modules, plugin artifacts, source snapshots and Wasm outputs. All recorded files and their digests were rechecked when producing this report. The build stages use the same absolute source/import paths across phases. Pass 1 strengthened archive/build-input verification; pass 3 added recording of the executed runner digest. Neither harness change alters the measured actor operations.

- Compiler: `Motoko compiler (source 2.0.0-14-g92b1bdecb)`, SHA-256 `4eb5e547d8772ccc25fcea56f1b97b100415b6e2b0edb891e2d06832a55dd2bc`.
- Release RTS: SHA-256 `8456e47e527bbd584ee2d5d867b0c93f5596d2bcdaa87bba53c04281562c820f`.
- PocketIC 10.0.0: SHA-256 `6303d3418bb20eb3b67e21cecbe68cc450b08dcbf2ec0896d831da4ccca6a990`; Bun 1.2.13; `@dfinity/pic` 0.16.1; Core 2.6.2.

| Version | Raw results | Build manifest | Generator SHA-256 prefix | Results SHA-256 prefix |
|---|---|---|---|---|
| baseline | [JSON](results/baseline/results.json) | [JSON](results/baseline/build.json) | `c708e7310ba82f42` | `64d8a8751bb2b89a` |
| pass1-mutable-entry | [JSON](results/pass1-mutable-entry/results.json) | [JSON](results/pass1-mutable-entry/build.json) | `8a9c90840ca8aeff` | `d1ac20c9adc28988` |
| pass2-cache-entries | [JSON](results/pass2-cache-entries/results.json) | [JSON](results/pass2-cache-entries/build.json) | `4f3cd0dd1e632223` | `65616b8e60dbb256` |
| pass3-scalar-hole | [JSON](results/pass3-scalar-hole/results.json) | [JSON](results/pass3-scalar-hole/build.json) | `17111b2df0f85cb8` | `ff51af8bbc5fad88` |

Use each phase's archived `harness/build.py`, `harness/run.mjs`, `source/`, `imports/` and `artifacts/` together to reproduce that implementation. The final matrix uses the current sources and has its own provenance; do not rebuild an older phase from the current plugin and label it as its archived baseline.
