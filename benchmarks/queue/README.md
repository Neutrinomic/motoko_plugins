# Queue performance — first delivery (historical)

The current implementation and new measurements are documented in
[optimization round 2](OPTIMIZATION-ROUND-2.md). The tables below preserve the
first delivery and its three measured optimization passes.

The chunked `mo:fast/Queue` reduces allocation in sustained queues and speeds up
bulk array export. Core Queue 2.6.2 already has O(1) endpoint operations; these
results measure lower storage/operation costs, not an asymptotic improvement.
The plugin is **not faster for every operation or every queue size**.
This compares the delivered modules as a whole: storage savings come from the
chunked representation, which could also be implemented in Motoko. The isolated
native-array-export pass below measures the additional benefit of its generated
Wasm loop on the same queue representation.

| Operation / workload size | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` / 100,000 | 99,300,314 | 64,828,362 | 1.53× | 9,600,000 | 1,375,000 |
| `fifo_churn` / 100,000 | 167,500,519 | 135,668,063 | 1.23× | 9,600,000 | 440 |
| `to_array` / 100,000 | 27,201,860 | 8,785,756 | 3.10× | 800,160 | 800,024 |
| `clone` / 100,000 | 105,302,036 | 76,312,160 | 1.38× | 9,600,216 | 1,375,384 |
| `reverse_values` / 100,000 | 53,901,733 | 32,401,868 | 1.66× | 4,000,192 | 232 |

`push_back` means 100,000 pushes into an initially empty queue. `fifo_churn`
means 100,000 push-back/pop-front pairs in a queue initially holding 100,000
elements. Traversal/export/clone process all 100,000 elements. Payloads remain
ordinary managed Motoko values; cloning shares payload references.

## Small queues and slower operations

| Operation / workload size | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |
|---|---:|---:|---:|---:|---:|
| `push_back` / 1 | 1,307 | 3,002 | 0.44× | 96 | 440 |
| `push_back` / 4 | 4,286 | 4,742 | 0.90× | 384 | 440 |
| `push_back` / 16 | 16,202 | 11,702 | 1.38× | 1,536 | 440 |
| `peek_front` / 100,000 | 35,500,459 | 46,800,466 | 0.76× | 0 | 0 |
| `pop_front` / 100,000 | 71,200,385 | 79,812,686 | 0.89× | 0 | 0 |
| `lifo_churn` / 100,000 | 167,500,549 | 187,702,468 | 0.89× | 9,600,000 | 440 |
| `values` / 100,000 | 26,901,159 | 32,383,088 | 0.83× | 96 | 232 |

The first lazy 32-slot chunk costs 440 allocated bytes, versus 96 bytes for one
Core queue node. Queue-record creation is outside the `push_back` measurement.
Short-lived singleton/few-element queues should generally remain Core queues;
the allocation saving starts after enough elements or repeated reuse. A warm
singleton undergoing 1,024 push/pop pairs allocates zero plugin bytes versus
98,304 Core bytes. `peek`, `pop`, forward iteration, and LIFO churn exactly at a
full-chunk boundary still cost more instructions in this benchmark. Integration
choices should follow complete workload measurements.

## Memory and reclamation

The [separate multi-message retention probe](results/memory-final/report.json)
uses 4,096 unique 4 KiB payloads, three refill/clear cycles, and 12,288 churn
operations at 33 live entries. All slot clearing, spare-link, payload-content,
and ordering assertions passed.

| Measurement | Core Queue | Plugin Queue |
|---|---:|---:|
| Full occupied heap above matched empty baseline | 17,432,576 B | 17,095,680 B |
| Storage nodes when full | 4,096 | 128 |
| One payload retained after draining, above baseline | 4,256 B | 5,040 B |
| Empty after draining, above baseline | 0 B | 440 B |
| Empty after `clear`, above baseline | 0 B | 0 B |
| Occupied-heap growth across steady churn | 0 B | 0 B |
| Linear-memory high-water during retention probe | 384 MiB | 384 MiB |

With identical payloads, the plugin used 336,896 fewer occupied heap bytes.
Every refill/clear cycle returned exactly to its matched empty baseline. At
most one cleared spare chunk is retained; `clear` releases it. The RTS allocation
partition must first be closed with controlled scratch pressure before forced
collection gives comparable occupied-heap measurements. Raw heap includes
runtime/scratch overhead, so the table uses differences from a matched empty
baseline. The common 384 MiB linear-memory high-water reflects this deliberate
pressure; it does not mean either live queue needs 384 MiB. The probe's roughly
2 GB gross allocation/reclamation totals also include that pressure and are
cleanup evidence, not per-operation allocation costs.

## Three measured optimization passes

Each candidate has an immutable source/plugin/Wasm archive and a PocketIC result
file. All changes below were accepted; phase 1 and phase 3 each tested a smaller
candidate before the complete pass. Native correctness tests were rerun after
each accepted pass. The final independent source audit found no confirmed
correctness or memory-safety issue. The final independent test round passed
four native fixtures, eight Ash checks and two real upgrades. It covers
nested-null/Any values, closures and mutable aliases, native array exports
across GC, 128 alternating endpoint/spare cycles, and retained exhausted
iterators after clear/GC; see
[validation evidence](../../packages/fast/tests/ash/coverage/QueueCollection.validation.json).

| Pass | Operation at 100,000 elements/pairs | Plugin instructions, before → after | Allocated bytes, before → after |
|---|---|---:|---:|
| 1a: cache endpoint metadata | `push_back` | 79,459,666 → 70,072,162 | 1,375,000 → 1,375,000 |
| 1b: keep private invariant validation out of hot operations | `push_back` | 70,072,162 → 64,672,162 | 1,375,000 → 1,375,000 |
| 2: reuse one cleared spare chunk | `fifo_churn` | 141,134,901 → 135,668,063 | 1,375,000 → 440 |
| 2: full-chunk LIFO boundary | `lifo_churn` | 362,700,556 → 187,702,468 | 44,000,000 → 440 |
| 3a: cache chunk traversal state | `values` | 74,904,691 → 32,383,088 | 168 → 232 |
| 3a: clone via improved cursor | `clone` | 118,833,763 → 76,312,160 | 1,375,320 → 1,375,384 |
| 3b: export arrays with a native loop | `to_array` | 31,583,727 → 8,785,756 | 800,296 → 800,024 |

Pass 1 keeps SDK array bounds checks, forwarding barriers and write barriers;
only repeated private-layout assertions move out of normal operations.
`assertValid` remains available explicitly. Pass 2 adds one optional spare field
(32 bytes in an empty queue record), trading a small fixed cost and slightly
more chunk-transition work for bounded reuse instead of repeated chunk
allocation. Pass 3 makes the iterator retain per-chunk Nat32 cursor state and
adds two native array-export operations; it does not add a public iterator
representation, callback protocol, or SDK changes. Constructing an iterator allocates
168 to 232 bytes (including the closure and captured state), while native export allocates only its result array.

Isolated pass-3 comparisons use [pass3-control](results/pass3-control/results.json),
a private build from the accepted pass-2 snapshot. No shared implementation was
rolled back during testing. Earlier `baseline`/`baseline-1` directories were
exploratory and are excluded: their unbounded checksum allocated big integers
at large sizes. The corrected control is
[baseline-final](results/baseline-final/results.json).

## Method and reproduction

- Compiler: Motoko plugin PR revision `92b1bdecbc7bc67fd51ad226f8d147d15494fc09`,
  original release RTS, ABI 1; no GC experiment or compiler modification.
- Baseline: Core Queue **2.6.2**. The same Wasm canister contains both modules.
- Final matrix: 14 operations × 10 sizes (0, 1, 4, 16, 31, 32, 33, 1k, 10k,
  100k) × 3 trials × 2 implementations = **840 measured calls**. All three
  instruction/allocation samples were identical for each case. Core control
  measurements also matched every optimization candidate exactly.
- Fresh canister per implementation/case/trial; implementation order alternates.
  Setup and four forced GC increments happen before each timed operation.
- Measurements use `Prim.performanceCounter(0)` and total-allocation deltas;
  they include dispatch, loops and a wrapping Nat32 checksum, and exclude reply
  encoding and end-of-message GC. Every timed call reports zero reclaimed bytes.
- Every case checks its checksum, size, and entire resulting queue against an
  independent JavaScript deque model. Allocation bytes are not retained heap.
- `fifo_churn`, `lifo_churn`, and `both_ends_churn` run max(1,024, size) push/pop
  pairs. `peek` repeats max(1, size) reads; array/traversal/clone counts are
  elements processed by one bulk call. Zero-length cases measure dispatch and
  empty-result overhead rather than per-element performance.
- Builds stage fixed-path copies of the module, plugin and source before
  compiling, verify source hashes against plugin build metadata, and verify
  compiler/RTS/Core inputs did not change. Raw reports contain all hashes,
  commands, PocketIC version/hash, and the actual runner hash.

```sh
# Build native plugin first using the repository's normal scoped build command.
python3 benchmarks/queue/build.py my-run
bun benchmarks/queue/run.mjs --label my-run --trials 3
bun benchmarks/queue/memory.mjs --out benchmarks/queue/_out/my-memory.json
python3 benchmarks/queue/summarize.py
```

See [all 140 result rows](RESULTS.md), [raw final measurements](results/final/results.json),
[final build provenance](results/final/build.json), and
[retention probe provenance](results/memory-final/report.json).
