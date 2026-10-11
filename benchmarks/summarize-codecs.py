#!/usr/bin/env python3
"""Validate codec comparison trials, preserving explicitly recorded failures."""
import argparse
import csv
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('reports', nargs='+', type=Path)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--expected-trials', type=int, default=3)
parser.add_argument('--expected-cases', type=int, default=12)
parser.add_argument('--expected-failures', type=Path)
args = parser.parse_args()
failures = json.loads(args.expected_failures.read_text()) if args.expected_failures else []
expected_failures = {(item['workload'], item['phase']): item['message'] for item in failures}
assert len(expected_failures) == len(failures), 'Duplicate expected failures'
seen_failures, identities, versions, rows = set(), set(), set(), []
labels = ['serde', 'serde_core', 'native', 'plugin']


def natural(value):
    assert type(value) is int or (isinstance(value, str) and value.isascii() and value.isdecimal())
    value = int(value)
    assert value >= 0
    return value


for path in args.reports:
    report = json.loads(path.read_text())
    assert not report.get('fatal_error'), f'{path}: {report.get("fatal_error")}'
    assert report['trials'] == args.expected_trials, f'{path}: unexpected trial count'
    versions.add(report['pocket_ic_version'])
    failure_count = 0
    for case in report['cases']:
        name = case['name']
        assert name not in identities, f'Duplicate workload {name}'
        identities.add(name)
        assert case['family'] in {'json', 'cbor'}
        assert [phase['label'] for phase in case['phases']] == labels
        assert [phase['require_no_gc'] for phase in case['phases']] == [False, False, False, True]
        samples = {}
        for sample in case['measurements']:
            key = sample['trial'], sample['phase']
            assert key not in samples, f'{name}: duplicate sample {key}'
            samples[key] = sample
        assert set(samples) == {(trial, label) for trial in range(args.expected_trials) for label in labels}, \
            f'{name}: incomplete trial set'
        row = {'workload': name, 'family': case['family'], 'trials': args.expected_trials}
        for label in labels:
            group = [samples[trial, label] for trial in range(args.expected_trials)]
            errors = [sample for sample in group if 'error' in sample]
            expected = expected_failures.get((name, label))
            if errors:
                assert len(errors) == len(group) and expected, f'{name}/{label}: unexpected failure'
                assert all(expected in sample['error'] for sample in errors), f'{name}/{label}: wrong failure'
                failure_count += len(errors)
                seen_failures.add((name, label))
                row[f'{label}_status'] = expected
                for field in ['instructions', 'instructions_min', 'instructions_max', 'allocated_bytes',
                              'reclaimed_bytes', 'output_bytes']:
                    row[f'{label}_{field}'] = ''
                continue
            assert expected is None, f'{name}/{label}: declared failure now succeeds; update the report'
            row[f'{label}_status'] = 'ok'
            for sample in group:
                for field in ['instructions', 'allocated_bytes', 'reclaimed_bytes', 'output_bytes']:
                    sample[field] = natural(sample[field])
                assert sample['instructions'] > 0
                digest = sample['output_sha256']
                assert len(digest) == 64 and all(c in '0123456789abcdef' for c in digest)
                if label == 'plugin':
                    assert sample['reclaimed_bytes'] == 0, f'{name}: plugin collected during measurement'
            assert len({(sample['output_sha256'], sample['output_bytes']) for sample in group}) == 1, \
                f'{name}/{label}: outputs differ across trials'
            for field in ['instructions', 'allocated_bytes', 'reclaimed_bytes', 'output_bytes']:
                row[f'{label}_{field}'] = statistics.median(sample[field] for sample in group)
            row[f'{label}_instructions_min'] = min(sample['instructions'] for sample in group)
            row[f'{label}_instructions_max'] = max(sample['instructions'] for sample in group)
        available = [label for label in labels[:-1] if row[f'{label}_status'] == 'ok']
        best = min(available, key=lambda label: row[f'{label}_instructions'])
        row['lowest_cost_native'] = best
        row['lowest_native_over_plugin'] = row[f'{best}_instructions'] / row['plugin_instructions']
        rows.append(row)
    assert failure_count == report['failed_measurements'], f'{path}: inconsistent failure count'

assert len(versions) == 1, 'PocketIC versions differ'
assert seen_failures == set(expected_failures), 'Missing declared failure workloads'
assert len(rows) == args.expected_cases, f'Expected {args.expected_cases} cases, got {len(rows)}'
args.out.parent.mkdir(parents=True, exist_ok=True)
with args.out.open('w', newline='') as output:
    writer = csv.DictWriter(output, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)

print('| Workload | serde 3.5.0 | serde-core 0.2.1 | json 1.4.0 / cbor 4.1.0 | Plugin | Lowest native/plugin |')
print('| --- | ---: | ---: | ---: | ---: | ---: |')
for row in rows:
    cells = [f'{row[label + "_instructions"]:,}' if row[label + '_status'] == 'ok' else 'stack overflow'
             for label in labels]
    print(f'| {row["workload"]} | ' + ' | '.join(cells) + f' | {row["lowest_native_over_plugin"]:.2f}× |')
