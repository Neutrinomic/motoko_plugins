#!/usr/bin/env python3
"""Validate all paired trials and regenerate CBOR optimization CSV tables."""
import csv
import json
from pathlib import Path

root = Path(__file__).resolve().parent
rows = []
for suffix in ('', '-edges', '-errors'):
    before = json.loads((root / f'baseline{suffix}.json').read_text())
    after = json.loads((root / f'final{suffix}.json').read_text())
    for key in ('source_sha256', 'cases_sha256', 'runner_sha256'):
        assert before[key] == after[key], (suffix, key)
    assert before['failed_measurements'] == after['failed_measurements'] == 0
    assert before['trials'] == after['trials'] == 3
    assert [c['name'] for c in before['cases']] == [c['name'] for c in after['cases']]
    for bcase, acase in zip(before['cases'], after['cases']):
        for phase in bcase['phases']:
            label = phase['label']
            bs = [m for m in bcase['measurements'] if m['phase'] == label]
            ats = [m for m in acase['measurements'] if m['phase'] == label]
            assert [m['trial'] for m in bs] == [m['trial'] for m in ats] == [0, 1, 2]
            for key in ('instructions', 'allocated_bytes', 'reclaimed_bytes', 'output_sha256'):
                assert len({m[key] for m in bs}) == len({m[key] for m in ats}) == 1
            assert bs[0]['output_sha256'] == ats[0]['output_sha256']
            if label == 'plugin':
                assert bs[0]['reclaimed_bytes'] == ats[0]['reclaimed_bytes'] == 0
            bi, ai = bs[0]['instructions'], ats[0]['instructions']
            ba, aa = bs[0]['allocated_bytes'], ats[0]['allocated_bytes']
            rows.append([bcase['name'], label, bi, ai, f'{100*(ai/bi-1):.2f}',
                         ba, aa, f'{100*(aa/ba-1):.2f}'])

with (root / 'summary.csv').open('w') as output:
    writer = csv.writer(output, lineterminator='\n')
    writer.writerow(['workload', 'implementation', 'baseline_instructions', 'final_instructions',
                     'instructions_change_percent', 'baseline_allocated_bytes',
                     'final_allocated_bytes', 'allocation_change_percent'])
    writer.writerows(rows)
print(f'Validated {len(rows)} paired measurements, each with three identical trials.')
for row in rows:
    if row[1] == 'plugin':
        name, _, bi, ai, change, ba, aa, _ = row
        print(f'| {name.removeprefix("cbor-")} | {bi:,} → {ai:,} | {change}% | {ba:,} → {aa:,} |')
