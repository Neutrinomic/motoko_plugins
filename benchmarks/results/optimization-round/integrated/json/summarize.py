#!/usr/bin/env python3
"""Validate frozen JSON baseline, audited, and integrated trials; emit comparison.csv."""
import csv
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
historical = root.parent.parent / 'json'
rows = []
labels = ('baseline', 'audited', 'integrated')
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
package = json.loads((root / 'package.json').read_text())
provenance = json.loads((root / 'provenance.json').read_text())
assert package['motoko_revision'] == provenance['compiler_revision']
assert package['moc_sha256'] == provenance['compiler_sha256']
previous_package = json.loads((historical / 'package-final.json').read_text())
assert package['sha256']['runtime.wasm'] == previous_package['sha256']['runtime.wasm']
for path, digest in previous_package['source_sha256'].items():
    if path.startswith('plugins/json/'):
        assert package['source_sha256'][path] == digest, path

for suite, expected_count in [('plugin', 15), ('native', 6)]:
    reports = [json.loads(path.read_text()) for path in (
        historical / f'{suite}-baseline.json', historical / f'{suite}-final.json',
        root / suite / 'final.json')]
    for field, artifact in [('source_sha256', root / suite / 'main.mo'),
                            ('cases_sha256', root / suite / 'cases.json'),
                            ('runner_sha256', root / 'run.mjs')]:
        assert all(report[field] == sha(artifact) for report in reports), (suite, field)
    assert len({report['pocket_ic_version'] for report in reports}) == 1
    assert all(report['trials'] == 3 and not report.get('fatal_error') for report in reports)
    assert reports[-1]['wasm_sha256'] == provenance['actors'][suite]['wasm_sha256']
    manifest = json.loads((root / suite / 'cases.json').read_text())
    expected = {case['name']: case for case in manifest['cases']}
    cases = [{case['name']: case for case in report['cases']} for report in reports]
    assert len(expected) == expected_count
    assert all(len(report['cases']) == len(case_map) == expected_count for report, case_map in zip(reports, cases))
    assert all(case_map.keys() == expected.keys() for case_map in cases)
    failures = [0, 0, 0]
    for name, case_spec in expected.items():
        phases = [phase['label'] for phase in case_spec['phases']]
        samples = []
        for case_map in cases:
            case = case_map[name]
            assert case['phases'] == case_spec['phases'], (suite, name)
            group = {(sample['trial'], sample['phase']): sample for sample in case['measurements']}
            assert len(group) == len(case['measurements']) == 3 * len(phases)
            assert group.keys() == {(trial, phase) for trial in range(3) for phase in phases}
            samples.append(group)
        for phase in phases:
            groups = [[samples[version][trial, phase] for trial in range(3)] for version in range(3)]
            expected_failure = suite == 'native' and name == 'json-text-64k-decode' and phase in ('serde', 'serde_core')
            row = {'suite': suite, 'workload': name, 'phase': phase,
                   'status': 'stack overflow' if expected_failure else 'ok'}
            if expected_failure:
                for version in range(3):
                    assert all('stack overflow' in sample.get('error', '') for sample in groups[version])
                    failures[version] += 3
            else:
                assert all('error' not in sample for group in groups for sample in group), (suite, name, phase)
                for field in ('output_sha256', 'output_bytes'):
                    assert len({sample[field] for group in groups for sample in group}) == 1, (suite, name, phase, field)
                for label, group in zip(labels, groups):
                    for field in ('instructions', 'allocated_bytes', 'reclaimed_bytes'):
                        values = {int(sample[field]) for sample in group}
                        assert len(values) == 1, (suite, name, phase, field, values)
                        row[f'{label}_{field}'] = values.pop()
                    assert row[f'{label}_reclaimed_bytes'] == 0
                for label in labels[:2]:
                    row[f'instructions_reduction_vs_{label}_percent'] = 100 * (1 - row['integrated_instructions'] / row[f'{label}_instructions'])
                    row[f'allocated_delta_vs_{label}_bytes'] = row['integrated_allocated_bytes'] - row[f'{label}_allocated_bytes']
            rows.append(row)
    assert failures == [report['failed_measurements'] for report in reports]
fields = list(dict.fromkeys(field for row in rows for field in row))
with (root / 'comparison.csv').open('w', newline='') as output:
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
print(f'Validated {len(rows)} JSON phases × 3 trials × 3 versions, including declared native failures.')
