#!/usr/bin/env python3
"""Summarize completed PocketIC runs; exact inputs remain in results/final."""
import json
from pathlib import Path
from statistics import median

here = Path(__file__).resolve().parent
rows = []
for path in sorted((here/'results/final').glob('results*.json')):
    report=json.loads(path.read_text())
    options=report['options']
    expected=0
    for entry in report['build']['cases']:
        if entry['variant'] not in options['variants'].split(',') or entry['key'] not in options['keys'].split(','): continue
        for n in map(int,options['sizes'].split(',')):
            for op in options['operations'].split(','):
                handle_op=op in ('get','remove','reschedule','replace')
                if (entry['variant']=='core-pq' or n==0) and handle_op: continue
                expected+=int(options['trials'])
    if len(report['cases'])!=expected:
        raise ValueError(f'{path.name} is incomplete: {len(report["cases"])}/{expected}')
    rows.extend(report['cases'])
groups = {}
for row in rows:
    key = (row['key'], row['size'], row['operation'], row['variant'])
    groups.setdefault(key, []).append(row)


def metric(key, field):
    items = groups.get(key)
    return None if not items else median(item['result'][field] for item in items)


lines = ['# Indexed priority queue performance', '',
    'PocketIC instruction and allocation comparisons for `mo:fast/IndexedPriorityQueue`, '
    'Core 2.6.2 `PriorityQueue`, Core `Map`, and `mo:fast/Map`. The queue is a minimum '
    'heap; the Core priority queue comparator is reversed to match. Maps use a '
    'priority-key index for cancellation/rescheduling. Core PriorityQueue has no '
    'equivalent handle operations, shown as —.', '',
    'All table operations run 256 times against a prefilled queue. Priorities are '
    'distinct; the custom deadline comparator orders `{at : Int; ticket : Nat}`. '
    'Setup inserts descending priorities outside the measured section; these are '
    'specific operation workloads, not an application throughput prediction.', '',
    'Nat and Int comparators use compiler-proven scalar dispatch. Composite '
    'deadlines use a normal Motoko callback. The latter also incur record '
    'construction/extraction costs, so comparing key types does not isolate '
    'callback overhead alone.', '',
    'Push appends priorities above the existing range. Remove and reschedule '
    'target the first inserted handles (the largest original priorities). Churn '
    'inserts a new minimum and immediately pops it. These are deterministic '
    'scenarios, not randomized average-case claims.', '',
    '| Priority / existing entries / operation | Core PriorityQueue instructions | Core Map instructions | fast Map instructions | IndexedPriorityQueue instructions |',
    '|---|---:|---:|---:|---:|']
selection = [('nat', n, operation) for n in (1000,10000,100000)
             for operation in ('peekPriority','get','push','pop','remove','reschedule','churn')]
selection += [('deadline',10000,operation) for operation in ('peekPriority','get','pop','remove','reschedule','churn')]
for key, n, operation in selection:
    numbers = [metric((key,n,operation,v),'instructions') for v in ('core-pq','core-map','fast-map','plugin')]
    if not any(value is not None for value in numbers): continue
    cells = ['—' if value is None else f'{value:,.0f}' for value in numbers]
    lines.append(f'| {key} / {n:,} / {operation} | '+' | '.join(cells)+' |')
lines += ['', 'Indexed handles make get and reschedule substantially cheaper in these '
    'scenarios, but the existing fast Map can be cheaper for pop and churn: at '
    '100,000 Nat entries, IPQ pop takes 7.2% more instructions; with 10,000 '
    'composite deadlines, pop takes 25.3% more. Choose by the complete workload.', '',
    'Allocation counts include the return value required by each operation. '
    '`IndexedPriorityQueue.peek` and `get` return fresh `(priority, value)` pairs (40 bytes in these '
    'cases); `peekPriority` avoids that pair. Active handles retain their queue; '
    'removal and clear detach them. Clear is O(n), because it invalidates all '
    'handles, unlike Core PriorityQueue/Map clear. At 100,000 entries, a single '
    'clear costs 12,301,318 IPQ instructions versus 914 for fast Map '
    '(these clear figures are one call, not 256).', '',
    '| Nat / 10,000 existing entries / operation | Core PriorityQueue allocated bytes | Core Map allocated bytes | fast Map allocated bytes | IndexedPriorityQueue allocated bytes |',
    '|---|---:|---:|---:|---:|']
for operation in ('peek','peekPriority','get','push','pop','remove','reschedule','replace','churn'):
    numbers = [metric(('nat',10000,operation,v),'allocated') for v in ('core-pq','core-map','fast-map','plugin')]
    if not any(value is not None for value in numbers): continue
    lines.append(f'| {operation} | '+' | '.join('—' if value is None else f'{value:,.0f}' for value in numbers)+' |')
lines += ['', 'Memory observations below are after setup and before the measured '
    'operation: the RTS heap delta after four requested GC increments and '
    'the Wasm memory high-water. The original RTS may leave open '
    'partitions uncollected, so **the heap delta is not a live retained-heap '
    'measurement**. It includes handle/index arrays and prior setup garbage. '
    'Core PriorityQueue has no handle index and therefore implements fewer '
    'capabilities. Separate GC and stale-handle reachability tests are described '
    'in [test coverage](../../packages/fast/tests/ash/coverage/IndexedPriorityQueue.md). '
    'GC histories also differ: Core PriorityQueue had reclaimed 57,161,664 bytes '
    'at these snapshots, while the other three had reclaimed zero.', '',
    '| Nat / 100,000 entries | Observed heap delta after GC requests | Wasm memory bytes |',
    '|---|---:|---:|']
for variant in ('core-pq','core-map','fast-map','plugin'):
    items=groups.get(('nat',100000,'peekPriority',variant))
    if items:
        row=items[0]
        lines.append(f'| {variant} | {row["heap_delta_before_gc"]:,} | {row["before"]["memory"]:,} |')
lines += ['', 'Three measured optimization passes and their accepted/rejected tradeoffs '
    'are in [OPTIMIZATION.md](OPTIMIZATION.md). Final `peekPriority` is a separate '
    'small API addition justified by Reactor deadline lookahead; it adds no stored '
    'state. The compiler/SDK and ABI version were unchanged.', '',
    f'The final comparison contains {len(rows):,} checked calls across {len(groups):,} '
    'implementation/key/size/operation combinations. Every case validates the '
    'measured result and drains remaining entries in sorted order, checking exact '
    'count and sum. Sizes include 0, 1, 32, 1,000, 10,000 and 100,000; the raw '
    'results contain individual operations and repetition counts. Tables use '
    'the median of available observations: 402 combinations have one trial; '
    '16 headline combinations at 10,000 entries have the original trial plus '
    'two three-trial blocks. Every repeated instruction/allocation counter '
    'matches exactly.', '',
    'Measurement uses fresh canisters, fixed source/import/plugin paths, explicit '
    'compiler and original RTS hashes, frozen native artifacts, and bounded '
    'setup messages. Performance counters cover the operation loop and adapter '
    'overhead; setup, replies and message-end GC are excluded. Allocation and '
    'reclaimed-byte deltas are separate. No instruction-limit overrides were used.', '',
    'One completed repeated run logged a PocketIC server shutdown error after '
    'all results had been written. The 48-case block was rerun with clean '
    'shutdown; every instruction/allocation result matched exactly. Both raw '
    'runs are retained.', '',
    'Reproduce (the target directory must not already exist):', '',
    '```sh', 'python3 benchmarks/indexed-priority-queue/build.py --phase reproduced',
    'bun benchmarks/indexed-priority-queue/run.mjs --phase reproduced', '```', '',
    'Raw evidence: [build manifest](results/final/build.json), '
    '[0–10,000 Nat/deadline cases](results/final/results.json), '
    '[100,000 Nat cases](results/final/results-large.json), '
    '[Int cases](results/final/results-int.json), '
    '[repeated headline cases](results/final/results-repeated.json), '
    '[repeat confirmation](results/final/results-repeated-confirmation.json).', '']
(here/'README.md').write_text('\n'.join(lines))
print(f'{len(rows)} cases in {len(groups)} combinations')
