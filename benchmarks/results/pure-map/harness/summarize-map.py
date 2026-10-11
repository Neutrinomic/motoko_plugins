#!/usr/bin/env python3
"""Validate complete map trials and print raw and per-operation cost summaries."""
import argparse
import csv
import hashlib
import json
import statistics
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('reports', nargs='+', type=Path)
parser.add_argument('--cases', required=True, type=Path)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--expected-trials', type=int, default=3)
args = parser.parse_args()
manifest = json.loads(args.cases.read_text())
specs = {case['name']: case for case in manifest['cases']}
assert len(specs) == len(manifest['cases']), 'Duplicate manifest case names'
identities, seen, rows = set(), set(), []
labels = ('core', 'plugin_custom', 'plugin_static')
expected_digest = hashlib.sha256(b'ok').hexdigest()


def natural(value):
    assert type(value) is int or (isinstance(value, str) and value.isascii() and value.isdecimal())
    result = int(value)
    assert result >= 0
    return result


for path in args.reports:
    report = json.loads(path.read_text())
    assert not report.get('fatal_error'), report.get('fatal_error')
    assert report['failed_measurements'] == 0, f'{path}: failed measurements'
    assert report['trials'] == args.expected_trials, f'{path}: wrong trial count'
    assert report['cases_sha256'] == hashlib.sha256(args.cases.read_bytes()).hexdigest(), \
        f'{path}: report was measured with a different manifest'
    identities.add((report['wasm_sha256'], report['source_sha256'], report['cases_sha256'],
                    report['runner_sha256'], report['pocket_ic_version']))
    for case in report['cases']:
        name = case['name']
        assert name in specs and name not in seen, f'{name}: unexpected or duplicate case'
        seen.add(name)
        spec = specs[name]
        assert case['phases'] == spec['phases'], f'{name}: different phase protocol'
        phases = [phase['label'] for phase in spec['phases']]
        count = natural(spec['operations_per_phase'])
        assert count > 0
        samples = {(sample['trial'], sample['phase']): sample for sample in case['measurements']}
        assert len(samples) == len(case['measurements']), f'{name}: duplicate measurements'
        assert set(samples) == {(trial, phase) for trial in range(args.expected_trials) for phase in phases}, \
            f'{name}: missing trials/phases'
        row = {'workload': name, 'map_size': spec['map_size'], 'operation': spec['operation'],
               'operations_per_phase': count, 'trials': args.expected_trials}
        for label in labels:
            fields = ('instructions', 'allocated_bytes', 'reclaimed_bytes')
            if label not in phases:
                for field in fields:
                    row[f'{label}_{field}'] = ''
                    row[f'{label}_{field}_per_op'] = ''
                row[f'{label}_instructions_min'] = ''
                row[f'{label}_instructions_max'] = ''
                continue
            group = [samples[trial, label] for trial in range(args.expected_trials)]
            for sample in group:
                assert 'error' not in sample, f'{name}/{label}: {sample.get("error")}'
                assert sample['output_sha256'] == expected_digest and natural(sample['output_bytes']) == 2
                for field in fields:
                    sample[field] = natural(sample[field])
                assert sample['instructions'] > 0
            for field in fields:
                value = statistics.median(sample[field] for sample in group)
                row[f'{label}_{field}'] = value
                row[f'{label}_{field}_per_op'] = value / count
            row[f'{label}_instructions_min'] = min(sample['instructions'] for sample in group)
            row[f'{label}_instructions_max'] = max(sample['instructions'] for sample in group)
        row['core_over_custom'] = row['core_instructions'] / row['plugin_custom_instructions']
        row['core_over_static'] = (row['core_instructions'] / row['plugin_static_instructions']
                                   if row['plugin_static_instructions'] != '' else '')
        rows.append(row)

assert seen == set(specs), f'Missing cases: {set(specs) - seen}'
assert len(identities) == 1, 'Cannot combine different compiler/runner/manifest snapshots'
args.out.parent.mkdir(parents=True, exist_ok=True)
with args.out.open('w', newline='') as output:
    writer = csv.DictWriter(output, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print('| Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core/callback | Core/scalar |')
print('| --- | ---: | ---: | ---: | ---: | ---: | ---: |')
for row in rows:
    counts = [f'{row[label + "_instructions_per_op"]:,.2f}'
              if row[label + '_instructions_per_op'] != '' else '—' for label in labels]
    ratio = f'{row["core_over_static"]:.2f}×' if row['core_over_static'] != '' else '—'
    print(f'| {row["operation"]} | {row["map_size"]:,} | ' + ' | '.join(counts) +
          f' | {row["core_over_custom"]:.2f}× | {ratio} |')
print('\nRaw batch totals, allocation/op, reclamation/op, and trial ranges are in ' + str(args.out))
