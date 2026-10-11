#!/usr/bin/env python3
"""Validate archived JSON trials and summarize all measured phases."""
import csv
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
rows = []
for suite, expected_cases in [('plugin', 15), ('native', 6)]:
    before = json.loads((root / f'{suite}-baseline.json').read_text())
    after = json.loads((root / f'{suite}-final.json').read_text())
    for field in ('source_sha256', 'cases_sha256', 'runner_sha256', 'pocket_ic_version'):
        assert before[field] == after[field], (suite, field)
    assert before['trials'] == after['trials'] == 3
    assert not before.get('fatal_error') and not after.get('fatal_error')
    for field, artifact in [('source_sha256', root / suite / 'main.mo'),
                            ('cases_sha256', root / suite / 'cases.json'),
                            ('runner_sha256', root / 'run.mjs')]:
        assert before[field] == hashlib.sha256(artifact.read_bytes()).hexdigest()
    manifest = json.loads((root / suite / 'cases.json').read_text())
    expected_names = {case['name'] for case in manifest['cases']}
    assert len(expected_names) == expected_cases
    cases = [{case['name']: case for case in report['cases']} for report in (before, after)]
    assert cases[0].keys() == cases[1].keys() == expected_names
    failures = [0, 0]
    for name, case in cases[0].items():
        phases = [phase['label'] for phase in case['phases']]
        assert case['phases'] == cases[1][name]['phases']
        groups = []
        for version in range(2):
            measurements = cases[version][name]['measurements']
            samples = {(sample['trial'], sample['phase']): sample for sample in measurements}
            assert len(samples) == len(measurements) == 3 * len(phases)
            assert samples.keys() == {(trial, phase) for trial in range(3) for phase in phases}
            groups.append(samples)
        for phase in phases:
            samples = [[group[trial, phase] for trial in range(3)] for group in groups]
            expected_failure = suite == 'native' and name == 'json-text-64k-decode' and phase in ('serde', 'serde_core')
            row = {'suite': suite, 'workload': name, 'phase': phase,
                   'status': 'stack overflow' if expected_failure else 'ok'}
            if expected_failure:
                for version in range(2):
                    assert all('stack overflow' in sample.get('error', '') for sample in samples[version])
                    failures[version] += 3
            else:
                assert all('error' not in sample for group in samples for sample in group), (suite, name, phase)
                for field in ('output_sha256', 'output_bytes'):
                    assert len({sample[field] for group in samples for sample in group}) == 1, (suite, name, phase, field)
                for version, label in enumerate(('before', 'after')):
                    for field in ('instructions', 'allocated_bytes', 'reclaimed_bytes'):
                        values = {int(sample[field]) for sample in samples[version]}
                        assert len(values) == 1, (suite, name, phase, field, values)
                        row[f'{label}_{field}'] = values.pop()
                    assert row[f'{label}_reclaimed_bytes'] == 0
                row['instruction_reduction_percent'] = 100 * (1 - row['after_instructions'] / row['before_instructions'])
                row['allocated_delta_bytes'] = row['after_allocated_bytes'] - row['before_allocated_bytes']
            rows.append(row)
    assert failures == [before['failed_measurements'], after['failed_measurements']]
fields = list(dict.fromkeys(field for row in rows for field in row))
with (root / 'summary.csv').open('w', newline='') as output:
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
print(f'Validated {len(rows)} phases × 3 trials × 2 versions; exact outputs and deterministic counters.')
