#!/usr/bin/env python3
"""Recreate the round-two summary from validated final benchmark evidence."""
import json
import subprocess
from pathlib import Path

here = Path(__file__).resolve().parent
subprocess.run(['python3', str(here/'verify_semantics.py'), str(here/'results/final-baseline'), str(here/'results/final')], check=True)
subprocess.run(['python3', str(here/'compare.py'), 'final-baseline', 'final', '--csv', str(here/'results/final-comparison.csv')], check=True)
before = json.loads((here/'results/final-baseline/results.json').read_text())
after = json.loads((here/'results/final/results.json').read_text())
old = {(row['capacity'], row['operation']): row for row in before['cases']}
assert len(old) == len(after['cases']) == 126
lines = ['# HistoryRing: additional measured optimization round', '',
'The final plugin uses fewer instructions for append, overwrite, lookup, paging,',
'and partial drops than the **previously delivered plugin**. This baseline is',
'generator `26762844…`, not the original implementation before round one.',
'The accepted generator is `30b20a89…`; no compiler, SDK, public module, or ABI',
'change was needed. [Candidate decisions and regressions](OPTIMIZATION.md) preserve',
'the four cumulative experiments.', '',
'Both final builds completed **126 cases × three trials** at capacities',
'0, 1, 64, 65, 129, 1,000, and 100,000. Each sample uses fresh canisters.',
'The table reports median instruction counts; allocation means bytes newly',
'allocated inside the measured loop, not retained heap. Pages return up to the',
'stated length. Full results include quarter/full/zero/wrapped drops, one-entry',
'and 64-entry pages, and all small-capacity cases in',
'[final-comparison.csv](results/final-comparison.csv).', '',
'| Capacity | Operation | Count | Core instructions | Previous plugin | Final plugin | Plugin reduction | Core / final allocation |',
'|---:|---|---:|---:|---:|---:|---:|---:|']
selected = {'append', 'overwrite', 'get_middle', 'page_tail_32', 'page_tail_1024', 'drop_half', 'drop_wrapped_half', 'pop_all'}
for row in after['cases']:
    if row['capacity'] not in (1000, 100000) or row['operation'] not in selected:
        continue
    p, c = row['plugin'], row['core']; original = old[row['capacity'], row['operation']]['plugin']
    reduction = 100 * (original['instructions'] - p['instructions']) / original['instructions']
    lines.append(f"| {row['capacity']:,} | {row['operation']} | {p['operations']:,} | {c['instructions']:,} | {original['instructions']:,} | {p['instructions']:,} | {reduction:.2f}% | {c['allocated']:,} / {p['allocated']:,} B |")
lines += ['',
'Core 2.6.2 uses a linked Queue. Its page baseline deliberately follows the',
'forward-cursor pattern from Takt Trace; these timings are **not a comparison',
'against the best suffix-only Core implementation**. `reverseValues` can avoid',
'scanning the prefix for suffix pages, and `peekBack` is O(1) for one entry.',
'Indexed lookup and pages also benefit from a different data structure, so the',
'large Core ratios must not be attributed to native code alone. Core full-drop',
'rows use repeated popFront; callers can instead use clear when removing every',
'entry. Capacity-zero append-and-trim can likewise be bypassed when retention',
'is disabled. Neither special case is headline speedup evidence.', '',
'There are small regressions: nonempty one-entry pages add 16–23 instructions',
'per call, nonzero full drops add 19, and capacity-zero appends add one.',
'Pop performance is unchanged and remains slower than Core in this matrix.',
'Tiny first appends and empty pages also remain slower than Core. Empty drops',
'now allocate zero bytes instead of 24; nonempty bulk operations keep their',
'previous allocation costs.', '', '## Correctness and retention', '',
'After every timed call and memory sample, an independent query checks every',
'retained value against its exact absolute sequence, checks iterator length, and',
'asserts that occupied physical plugin slots equal logical size. This catches',
'wrong retained order and stale payload references after wrapped/chunk drops.',
'Checksums, sequence bounds, operation counts, archive hashes, and complete trial',
'sets are also checked by [verify_semantics.py](verify_semantics.py). Core costs',
'and allocation match exactly between final baseline and final candidate.', '',
'The separate 64-batch retention probe appends 65,536 fresh 1 KiB Blobs at',
'capacity 1,024. All nonempty checkpoints retain exactly 1,024 payloads /',
'1,048,576 bytes.',
'After a 512-entry partial drop and eight GC increments, every remaining byte',
'is validated and the plugin has exactly 512 occupied slots / 524,288 payload',
'bytes. Clearing then leaves zero directory entries, chunks, occupied slots, or',
'payload bytes. Core byte checksums and sequence results agree.', '',
'| After 64 batches | Core Queue | Previous plugin | Final plugin |',
'|---|---:|---:|---:|']
churn_before = {row['implementation']: row for row in before['churn']}
churn_after = {row['implementation']: row for row in after['churn']}
rows = [churn_after['core'], churn_before['plugin'], churn_after['plugin']]
for label, key in [('Retained entries', 'size'), ('Total allocation since install (B)', 'allocated'), ('Reclaimed by GC (B)', 'reclaimed'), ('Current managed heap (B)', 'heap'), ('Wasm memory high-water (B)', 'memory'), ('Historical post-GC heap high-water (B)', 'maxLive')]:
    values = [row['checkpoints'][-1]['memory'][key] for row in rows]
    lines.append('| ' + label + ' | ' + ' | '.join(f'{value:,}' for value in values) + ' |')
lines += ['',
'Payload construction dominates total allocation in this probe. Current heap',
'includes uncollected partition garbage; fixed GC increments do not establish',
'exact live bytes. Wasm memory and `maxLive` are historical high-water counters.',
'The occupied-slot/payload-byte checks establish retention independently of',
'GC timing. Partial drops retain the directory high-water length; clear releases',
'it. Raw `storage` fields in Core rows inspect its unused plugin ring and must',
'not be interpreted as Core storage usage.', '',
'Independent published-build validation passed four native fixtures, eight Ash',
'tests, and two upgrades, including 405 drop/refill cases, page/chunk boundaries,',
'large sequences, nullable payloads, and mutation during incremental GC.',
'See [validation evidence](../../../packages/fast/tests/ash/coverage/HistoryRing-validation-round2.json)',
'and the [harness audit](HARNESS_AUDIT.md). The benchmark oracle complements those',
'model tests; additive timed checksums alone do not certify returned page/pop',
'order.', '', '## Build provenance and reproduction', '',
'Compiler `92b1bdecb`, the original release RTS, Core 2.6.2, ABI 1, PocketIC 10,',
'and the Ash transport are pinned by hashes. Source/module/compiler/harness',
'paths remain fixed across the final comparison; only plugin source/artifacts',
'and emitted Wasm differ. Build inputs are checked before/after compilation,',
'and archived plugin sources match their build manifests. The runner validates',
'its own hash and the exact archived Wasm before installation.', '',
'The measured private native plugin is `71ca3734…`; the published native plugin',
'is `f71c15ec…`. They share generator `30b20a89…` and emit **byte-identical**',
'benchmark Wasm `1d89bd04…`. [Publication evidence](results/published-equivalence/equivalence.json)',
'archives both identities rather than treating the private native artifact as',
'installed. [Final results](results/final/results.json) and',
'[matched current-plugin baseline](results/final-baseline/results.json) retain',
'all raw samples, memory checkpoints, sources, artifacts, and build commands.', '',
'Measurement includes dispatch, counters, and loop/checksum overhead; setup,',
'reply encoding, end-of-message GC, and the exact-state oracle are excluded.',
'No measured call reclaimed memory synchronously. Wrapping Nat32 checksums avoid',
'bigint allocation at 100,000 entries. Timed sequence numbers stay compact;',
'large-sequence correctness is tested separately.', '',
'To measure an already built plugin repository in a new immutable stage:', '', '```sh',
'python3 benchmarks/history-ring/round2/build.py --stage my-run --plugin-root .',
'bun benchmarks/history-ring/round2/run.mjs --stage my-run --trials 3 --sizes 0,1,64,65,129,1000,100000 --churn yes',
'python3 benchmarks/history-ring/round2/verify_semantics.py benchmarks/history-ring/round2/results/my-run',
'```', '',
'`write_report.py` regenerates this summary and the final comparison CSV from',
'the validated immutable `final-baseline` and `final` reports.', '']
(here/'README.md').write_text('\n'.join(lines))
summary = {'cases_per_stage':len(after['cases']), 'trials':after['trials'], 'baseline_generator_sha256':before['build']['archive']['plugin/compiler/generator.ml']['sha256'], 'final_generator_sha256':after['build']['archive']['plugin/compiler/generator.ml']['sha256'], 'selected':[], 'retention': {'baseline':churn_before, 'final':churn_after}}
for row in after['cases']:
    if row['capacity'] in (1000,100000) and row['operation'] in selected:
        original=old[row['capacity'],row['operation']]['plugin']
        summary['selected'].append({'capacity':row['capacity'],'operation':row['operation'],'count':row['plugin']['operations'],'core':row['core']['instructions'],'previous_plugin':original['instructions'],'final_plugin':row['plugin']['instructions'],'core_allocated':row['core']['allocated'],'plugin_allocated':row['plugin']['allocated']})
(here/'results/summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(here/'README.md')
