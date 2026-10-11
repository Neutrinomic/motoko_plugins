#!/usr/bin/env python3
"""Validate complete paired JSON trials and regenerate summary.csv."""
import csv
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
provenance = json.loads((root / 'provenance.json').read_text())
for version in ('baseline', 'final'):
    package = json.loads((root / f'package-{version}.json').read_text())
    assert package['motoko_revision'] == provenance['compiler_revision']
    assert package['moc_sha256'] == provenance['compiler_sha256']
rows = []
for suite, count in [('plugin', 15), ('native', 6), ('numbers', 16)]:
    manifest = json.loads((root / suite / 'cases.json').read_text())
    expected = {case['name']: case for case in manifest['cases']}
    assert len(expected) == len(manifest['cases']) == count
    reports = [json.loads((root / suite / f'{version}.json').read_text())
               for version in ('baseline', 'final')]
    assert len({report['pocket_ic_version'] for report in reports}) == 1
    assert all(report['trials'] == 3 and not report.get('fatal_error') for report in reports)
    for field, path in [('source_sha256', root / suite / 'main.mo'),
                        ('cases_sha256', root / suite / 'cases.json'),
                        ('runner_sha256', root / 'run.mjs')]:
        assert all(report[field] == sha(path) for report in reports), (suite, field)
    for version, report in zip(('baseline', 'final'), reports):
        actor = provenance['actors'][suite][version]
        assert report['wasm_sha256'] == actor['sha256']
        assert report['wasm_bytes'] == actor['bytes']
    cases = [{case['name']: case for case in report['cases']} for report in reports]
    assert all(len(report['cases']) == len(group) == count for report, group in zip(reports, cases))
    assert all(group.keys() == expected.keys() for group in cases)
    failures = [0, 0]
    for name, spec in expected.items():
        phases = [phase['label'] for phase in spec['phases']]
        groups = []
        for group in cases:
            case = group[name]
            assert case['phases'] == spec['phases']
            samples = {(sample['trial'], sample['phase']): sample for sample in case['measurements']}
            assert len(samples) == len(case['measurements']) == 3 * len(phases)
            assert samples.keys() == {(trial, phase) for trial in range(3) for phase in phases}
            groups.append(samples)
        for phase in phases:
            failed = suite == 'native' and name == 'json-text-64k-decode' and phase in ('serde', 'serde_core')
            row = {'suite': suite, 'workload': name, 'phase': phase,
                   'status': 'stack overflow' if failed else 'ok'}
            samples = [[group[trial, phase] for trial in range(3)] for group in groups]
            if failed:
                for version, group in enumerate(samples):
                    assert all('stack overflow' in sample.get('error', '') for sample in group)
                    failures[version] += 3
            else:
                assert all('error' not in sample for group in samples for sample in group), (suite, name, phase)
                for field in ('output_sha256', 'output_bytes'):
                    assert len({sample[field] for group in samples for sample in group}) == 1, (suite, name, phase, field)
                for version, group in zip(('baseline', 'final'), samples):
                    for field in ('instructions', 'allocated_bytes', 'reclaimed_bytes'):
                        values = {int(sample[field]) for sample in group}
                        assert len(values) == 1, (suite, name, phase, field)
                        row[f'{version}_{field}'] = values.pop()
                    assert row[f'{version}_reclaimed_bytes'] == 0
                row['instructions_reduction_percent'] = 100 * (1 - row['final_instructions'] / row['baseline_instructions'])
                row['allocated_delta_bytes'] = row['final_allocated_bytes'] - row['baseline_allocated_bytes']
                if suite == 'native' and phase != 'plugin':
                    for field in ('instructions', 'allocated_bytes', 'reclaimed_bytes'):
                        assert row[f'baseline_{field}'] == row[f'final_{field}'], (suite, name, phase, field)
            rows.append(row)
    assert failures == [report['failed_measurements'] for report in reports]
fields = list(dict.fromkeys(field for row in rows for field in row))
with (root / 'summary.csv').open('w', newline='') as output:
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
print(f'Validated {len(rows)} phases × 3 trials × 2 versions, including declared native failures.')
