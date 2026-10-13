#!/usr/bin/env python3
"""Generate readable Queue results from the complete frozen PocketIC measurements."""
import json
from pathlib import Path

here = Path(__file__).resolve().parent

def read(label):
    report = json.loads((here / 'results' / label / 'results.json').read_text())
    return report, {(row['operation'], row['size']): row for row in report['cases']}

final, rows = read('final')
assert len(rows) == 140 and final['trials'] == 3, 'final full matrix is incomplete'
assert all(len(row['measurements']) == 3 for row in rows.values())
assert all(len({(m[impl]['instructions'], m[impl]['allocated'], m[impl]['checksum'], m[impl]['size'])
                    for m in row['measurements']}) == 1 for row in rows.values() for impl in ['core', 'fast']), \
    'measurements are not identical; report sample variation explicitly before publishing'

def table(selections, include_size=True):
    label = 'Operation / workload size' if include_size else 'Operation'
    lines = [f'| {label} | Core instructions | Plugin instructions | Core / plugin | Core allocated B | Plugin allocated B |',
             '|---|---:|---:|---:|---:|---:|']
    for operation, size in selections:
        row = rows[operation, size]
        text = f'`{operation}` / {size:,}' if include_size else f'`{operation}`'
        c, f = row['core'], row['fast']
        lines.append(f'| {text} | {c["instructions"]:,} | {f["instructions"]:,} | {c["instructions"] / f["instructions"]:.2f}× | {c["allocated"]:,} | {f["allocated"]:,} |')
    return '\n'.join(lines)

operations = ['push_back', 'push_front', 'pop_front', 'pop_back', 'peek_front', 'peek_back',
              'fifo_churn', 'lifo_churn', 'both_ends_churn', 'values', 'reverse_values', 'from_array', 'to_array', 'clone']
full = ['# Queue: full instruction and allocation results', '',
        'Core Queue 2.6.2 versus the final plugin. Three fresh-canister trials per implementation/case; every instruction and allocation count matched across all three trials. '
        'These are whole measured-operation totals, including the benchmark loop and checksum. '
        'A ratio above 1 means fewer plugin instructions. Allocation is not live memory. '
        'See [methodology and retained-memory results](README.md).', '']
for size in [0, 1, 4, 16, 31, 32, 33, 1000, 10000, 100000]:
    full += [f'## Size {size:,}', '', table([(operation, size) for operation in operations], False), '']
(here / 'RESULTS.md').write_text('\n'.join(full))

phase1, r1 = read('baseline-final')
phase1a, r1a = read('pass1-metadata')
phase1b, r1b = read('pass1-private-invariants')
phase2, r2 = read('pass2-spare')
phase3before, r3b = read('pass3-control')
phase3cursor, r3c = read('pass3-cursor')
phase3after, r3a = read('pass3-native-array')
for candidate in [r1a, r1b, r2, r3b, r3c, r3a, rows]:
    for key, row in candidate.items():
        assert row['core'] == r1[key]['core'], f'Core control changed between candidates: {key}'
pass_rows = []
for title, operation, before, after in [
    ('1a: cache endpoint metadata', 'push_back', r1, r1a),
    ('1b: keep private invariant validation out of hot operations', 'push_back', r1a, r1b),
    ('2: reuse one cleared spare chunk', 'fifo_churn', r1b, r2),
    ('2: full-chunk LIFO boundary', 'lifo_churn', r1b, r2),
    ('3a: cache chunk traversal state', 'values', r3b, r3c),
    ('3a: clone via improved cursor', 'clone', r3b, r3c),
    ('3b: export arrays with a native loop', 'to_array', r3c, r3a),
]:
    old = before[operation, 100000]['fast']
    new = after[operation, 100000]['fast']
    pass_rows.append(f'| {title} | `{operation}` | {old["instructions"]:,} → {new["instructions"]:,} | {old["allocated"]:,} → {new["allocated"]:,} |')

headlines = table([(op, 100000) for op in ['push_back', 'fifo_churn', 'to_array', 'clone', 'reverse_values']])
tradeoffs = table([('push_back', 1), ('push_back', 4), ('push_back', 16), ('peek_front', 100000),
                   ('pop_front', 100000), ('lifo_churn', 100000), ('values', 100000)])
readme = f'''# Queue performance — first delivery (historical)

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

{headlines}

`push_back` means 100,000 pushes into an initially empty queue. `fifo_churn`
means 100,000 push-back/pop-front pairs in a queue initially holding 100,000
elements. Traversal/export/clone process all 100,000 elements. Payloads remain
ordinary managed Motoko values; cloning shares payload references.

## Small queues and slower operations

{tradeoffs}

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
{chr(10).join(pass_rows)}

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
'''
(here / 'README.md').write_text(readme)
print(here / 'README.md')
