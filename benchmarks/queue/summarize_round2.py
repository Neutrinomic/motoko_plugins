#!/usr/bin/env python3
"""Generate round-2 Queue tables without changing first-delivery evidence."""
import hashlib
import gzip
import json
from pathlib import Path

here = Path(__file__).resolve().parent
operations = ['push_back', 'push_front', 'pop_front', 'pop_back', 'peek_front', 'peek_back',
              'fifo_churn', 'lifo_churn', 'both_ends_churn', 'values', 'reverse_values',
              'from_array', 'to_array', 'clone']
sizes = [0, 1, 4, 16, 31, 32, 33, 1000, 10000, 100000]

def load(label, complete=False):
    directory = here / 'results' / label
    report = json.loads((directory / 'results.json').read_text())
    rows = {(r['operation'], r['size']): r for r in report['cases']}
    if complete:
        assert set(rows) == {(op, n) for op in operations for n in sizes}, label
        assert report['trials'] == 3, label
        for row in rows.values():
            assert len(row['measurements']) == 3
            for impl in ['core', 'fast']:
                assert len({json.dumps(m[impl], sort_keys=True) for m in row['measurements']}) == 1
                assert row[impl]['reclaimed'] == 0
    build = report['build']
    for path, expected in build['archive_sha256'].items():
        assert hashlib.sha256((directory / path).read_bytes()).hexdigest() == expected, (label, path)
    assert report['harness_sha256'] == build['archive_sha256']['sources/run.mjs']
    return report, rows

control, before = load('round2-control-full', True)
final, after = load('round2-final', True)
for label in ['round2-baseline', 'round2-peek-pop', 'round2-packed',
              'round2-packed-guards', 'round2-packed-cursor']:
    _, rows = load(label)
    for key, row in rows.items():
        assert row['core'] == before[key]['core'], (label, key, 'Core control')
for key, row in after.items():
    assert row['core'] == before[key]['core'], key
    assert row['fast']['checksum'] == before[key]['fast']['checksum']
    assert row['fast']['size'] == before[key]['fast']['size']
    assert row['fast']['operations'] == before[key]['fast']['operations']


def table(keys):
    lines = ['| Operation / size | Core instructions | Delivered plugin | New plugin | Plugin reduction | Core / new | Core allocated B | Delivered / new allocated B |',
             '|---|---:|---:|---:|---:|---:|---:|---:|']
    for key in keys:
        old, new, core = before[key]['fast'], after[key]['fast'], after[key]['core']
        reduction = 100 * (old['instructions'] - new['instructions']) / old['instructions']
        lines.append(f'| `{key[0]}` / {key[1]:,} | {core["instructions"]:,} | {old["instructions"]:,} | {new["instructions"]:,} | {reduction:.2f}% | {core["instructions"] / new["instructions"]:.2f}× | {core["allocated"]:,} | {old["allocated"]:,} / {new["allocated"]:,} |')
    return '\n'.join(lines)

lines = ['# Queue round 2: full measured results', '',
         'Current delivered Queue versus the newly optimized Queue and unchanged Core Queue 2.6.2. '
         'Three fresh-canister trials for each implementation in each 140-case matrix; every instruction/allocation sample was identical. '
         'Reduction is relative to the delivered plugin, and a negative reduction is a regression. '
         'A Core/new ratio above one means fewer plugin instructions. Allocation is not retained memory. '
         'See [method, decisions, and retained memory](OPTIMIZATION-ROUND-2.md).', '']
for size in sizes:
    lines += [f'## Size {size:,}', '', table([(op, size) for op in operations]), '']
(here / 'ROUND-2-RESULTS.md').write_text('\n'.join(lines))

headlines = table([(op, 100000) for op in operations])
small = table([('push_back', n) for n in [1, 4, 16]])
regressions = [(op, n, before[op,n]['fast']['instructions'], after[op,n]['fast']['instructions'])
               for op,n in before if after[op,n]['fast']['instructions'] > before[op,n]['fast']['instructions']]
if regressions:
    regression_text = 'Small regressions versus the delivered plugin are retained in the full table: ' + '; '.join(
        f'`{op}`/{n}: {old:,} → {new:,} instructions ({100*(new-old)/old:.2f}% more)' for op,n,old,new in regressions) + '.'
else:
    regression_text = 'None of the 140 measured cases regressed in instruction count versus the delivered plugin.'

empty = {}
for label in ['round2-baseline', 'round2-peek-pop', 'round2-final']:
    report = json.loads((here/'results'/label/'empty-results.json').read_text())
    empty[label] = {(r['state'],r['operation']): r for r in report['cases']}
    for row in report['cases']:
        assert len(row['measurements']) == 2
        assert len(set(row['instructions'])) == 1
        assert all(m['allocated'] == 0 and m['reclaimed'] == 0 for m in row['measurements'])
empty_lines = ['| Retained-empty operation, 1,024 calls | Delivered | Final | Saved per call |', '|---|---:|---:|---:|']
for op in ['peek_front', 'peek_back', 'pop_front', 'pop_back']:
    a=empty['round2-baseline']['drained_from_front',op]['instructions'][0]
    b=empty['round2-final']['drained_from_front',op]['instructions'][0]
    empty_lines.append(f'| `{op}` | {a:,} | {b:,} | {(a-b)/1024:.0f} |')

mem = {}
for label in ['memory-final','round2-memory-final']:
    report = json.loads((here/'results'/label/'report.json').read_text())
    mem[label] = {s['implementation']:{c['name']:c['after'] for c in s['checkpoints']} for s in report['samples']}
    assert set(mem[label]) == {'fast','core'}
    for impl, checkpoints in mem[label].items():
        assert len(checkpoints) == 16
        baseline = checkpoints['empty_initial']['heap']
        for key in ['cleared_empty','clear_0','clear_1','clear_2','final_empty']:
            assert checkpoints[key]['heap'] == baseline, (label,impl,key)
        assert all(checkpoints[k]['heap'] == checkpoints['churn_start']['heap'] for k in ['churn_0','churn_1','churn_2'])

def heap(label, impl, checkpoint):
    rows=mem[label][impl]
    return rows[checkpoint]['heap']-rows['empty_initial']['heap']
for key in mem['memory-final']['core']:
    assert heap('memory-final','core',key) == heap('round2-memory-final','core',key), key

mem_lines=['| Occupied heap above matched empty baseline | Core | Delivered plugin | New plugin |','|---|---:|---:|---:|']
for title,key in [('4,096 distinct 4 KiB payloads','full'),('One payload after draining, plus plugin spare','drained_to_one'),('Empty after draining','drained_to_zero'),('After clear','cleared_empty')]:
    values=[heap('round2-memory-final','core',key),heap('memory-final','fast',key),heap('round2-memory-final','fast',key)]
    mem_lines.append('| '+title+' | '+' | '.join(f'{n:,} B' for n in values)+' |')

old_wasm=(here/'results/round2-control-full/main.wasm').read_bytes()
new_wasm=(here/'results/round2-final/main.wasm').read_bytes()
text=f'''# Queue optimization round 2

The new Queue reduces instructions across the common endpoint, churn and traversal workloads while preserving bounded chunk reuse. Compared with the **already delivered plugin**, 100k-element FIFO churn uses 12.52% fewer instructions, front pops use 16.65% fewer, and forward traversal uses 9.50% fewer. Chunks shrink from 440 to 408 allocated bytes and iterator construction from 232 to 200 bytes. Core Queue remains preferable for fresh singleton/few-element queues and several read-heavy operations.

This compares complete modules. Core Queue already has O(1) endpoint operations. Packing metadata is a representation improvement also available to a Motoko implementation; native code generation is responsible for the emitted endpoint operations and direct array export, not all storage savings.

## Matched instruction and allocation results

All totals include the measured loop and checksum. Push/pop/peek totals below process 100,000 operations; churn totals process 100,000 push/pop pairs; traversal and bulk totals process 100,000 elements. Setup is outside measurement.

{headlines}

{regression_text}

{small}

Fresh singleton/few-element queues still favor Core: a first plugin chunk allocates 408 B versus 96 B per Core node. Queue-record creation is outside the push measurement. At 16 items the chunk saves both instructions and allocation; reuse also changes the tradeoff. Peeks, forward iteration and full-boundary LIFO churn remain slower than Core in the 100k matrix despite improving versus the delivered plugin. Use complete application measurements for integration decisions.

## Measured experiments and decisions

1. **Accept endpoint code-generation cleanup.** Inline peeks bind the argument once. Pop loads the slots array once and reuses that managed reference for checked read and clearing. The initial unchanged-layout candidate reduced 100k front-pop instructions from 79,812,686 to 76,012,686. SDK bounds checks, object forwarding and pointer write barriers remain.
2. **Accept packed chunk metadata.** One Nat32 stores the start slot in its low five bits and count (0..32) above them. Updating one mutable field removes 32 B per chunk and reduces endpoint work. On top of the first candidate, FIFO improves from 131,868,063 to 118,680,429 instructions. The branchless packed front peek was about 0.99% slower than the simpler unchanged-layout candidate; the layout was accepted for broad endpoint/storage gains, not a claim that every isolated change wins.
3. **Reject branchless retained-empty peeks; retain an explicit zero-count guard.** The first shortcut made retained-empty back peeks 50 instructions per call slower than delivered. With one packed metadata load and the guard restored, both retained-empty peeks save 52 instructions per call. Nonempty guarded peeks spend a small extra amount versus the branchless packed experiment, but remain faster than delivered.
4. **Accept packed transient cursor state.** Store the next index and remaining count in one captured Nat32 rather than two mutable cells. Forward traversal improves from 32,273,713 to 29,307,931 instructions after chunk packing; clone also benefits. Iterator construction allocates 200 B, including closure/captured state, versus the delivered 232 B. Cached slots are still cleared immediately when a chunk is exhausted.

The [algorithm review](algorithm-research-round-2.md) compared fixed linked blocks with array rings, block directories and endpoint-index designs using primary implementation sources. The current circular-block deque keeps endpoint work bounded without resizing/copying all references. Native bulk builders and a special singleton representation remain possible later experiments; neither was needed for these measured gains.

## Empty queues and retention

The separate empty gate measures never-created, drained-from-front, drained-from-back and cleared queues, then validates reuse. All 16 cases × 2 fresh-actor trials passed, with zero allocation/reclamation during timed calls. Drained-front and drained-back results agree. Fresh/cleared peeks save six instructions per call; fresh/cleared pops are unchanged.

{chr(10).join(empty_lines)}

The [controlled-pressure memory probe](results/round2-memory-final/report.json) uses distinct 4 KiB payloads and closes the RTS allocation partition before comparing occupied heap with matched empty baselines. Allocation counters are not live-memory measurements.

{chr(10).join(mem_lines)}

The full queue has 128 chunks; its 4,096 B improvement is exactly 32 B per chunk. Three refill/clear cycles return to the exact empty baseline. Across 12,288 churn operations at 33 live entries, occupied heap does not grow and the spare retains no payloads or links. Both implementations reach 384 MiB linear-memory high-water because of deliberate collection pressure; that is unchanged and is not the live queue size. Gross allocation/reclamation includes this pressure and is not reported as operation allocation cost.

## Correctness and stable representation

The benchmark canister Wasm shrinks from {len(old_wasm):,} to {len(new_wasm):,} bytes ({len(gzip.compress(old_wasm, mtime=0)):,} to {len(gzip.compress(new_wasm, mtime=0)):,} bytes gzipped). This is the combined benchmark artifact, not a universal size estimate for every application.

The public API is unchanged. All payload slots and links remain managed storage, with conservative Any physical writes for generic payloads. Metadata satisfies `start = meta & 31`, `count = meta >> 5`, `count <= 32`. A detached spare has zero metadata and cleared slots/links. The retained empty endpoint may retain its start bits, with count zero and all slots cleared.

This preproduction change replaces chunk `start`/`count` fields with `meta`, so it **changes the stable storage shape**. Existing queues from the previous experimental representation need explicit migration or recreation; no legacy adapter was added. New-format upgrades are tested separately from compatibility with the previous format.

The independent source audit found no confirmed correctness or memory-safety issue and independently checked 4,096 valid metadata transitions and 2,048 cursor start states. Three focused native fixtures passed before publication. Final independent validation passed four native fixtures, eight Ash checks and two actual upgrades with persisted packed-layout queues/spare reuse. The expansion includes 192 geometry scenarios (all 32 start offsets, sizes 31/32/33, both drain directions), peeks after every pop, and heterogeneous Any values/native exports across GC. Wrong-end and drained-peek mutation controls failed as intended. See [round-2 validation evidence](../../packages/fast/tests/ash/coverage/QueueCollection.round2.validation.json) and [test coverage](../../packages/fast/tests/ash/coverage/QueueCollection.md).

## Reproduction and provenance

- Compiler PR revision `92b1bdecbc7bc67fd51ad226f8d147d15494fc09`, original release RTS, ABI 1; no compiler/SDK changes in this round. Core Queue 2.6.2 is unchanged.
- Delivered and final matrices each cover 14 operations × 10 sizes (0,1,4,16,31,32,33,1k,10k,100k) × 3 trials × 2 implementations: 840 measured calls per matrix. Every repeated counter matched exactly, every timed call reported zero reclaimed bytes, and Core controls matched every candidate.
- A fresh canister is used for each implementation/case/trial, alternating implementation order. Configuration and four forced GC increments precede timing. Performance counters include dispatch/loop/wrapping Nat32 checksum and exclude reply encoding/end-message GC. Complete resulting arrays are checked against an independent JS model.
- Churn runs max(1,024,size) pairs; peeks run max(1,size) reads. Bulk counts are elements processed, not repeated API calls. Zero-size cases measure empty-result/dispatch overhead.
- All candidate source/module/native/Wasm artifacts are archived. Candidates build in private stages; shared production sources were never rolled back. Final published native `{final['build']['archive_sha256']['dist/plugin.cmxs']}` and module `{final['build']['archive_sha256']['sources/Queue.mo']}` exactly match the accepted measured candidate. Compiling the published inputs at the same harness paths produced byte-identical Wasm `{final['build']['archive_sha256']['main.wasm']}`.
- Source hashes in native build metadata, compiler/RTS/Core hashes and runner hashes are checked. The full current-baseline control is [round2-control-full](results/round2-control-full/results.json), final is [round2-final](results/round2-final/results.json), and intermediate archives are `round2-peek-pop`, `round2-packed`, `round2-packed-guards`, and `round2-packed-cursor`. First-delivery results remain [historical](README.md).

```sh
python3 benchmarks/queue/build.py my-new-label
bun benchmarks/queue/run.mjs --label my-new-label --sizes 0,1,4,16,31,32,33,1000,10000,100000 --trials 3
bun benchmarks/queue/empty.mjs --variants my-new-label
bun benchmarks/queue/memory.mjs --out benchmarks/queue/_out/my-memory.json
python3 benchmarks/queue/summarize_round2.py
```

[All 140 matched instruction/allocation rows](ROUND-2-RESULTS.md).
'''
(here/'OPTIMIZATION-ROUND-2.md').write_text(text)
print('Round-2 tables/report verified and written. Regression cases:',len(regressions))
