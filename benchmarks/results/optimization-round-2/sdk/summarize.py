#!/usr/bin/env python3
"""Validate every SDK trial and emit the paired instruction/allocation table."""
from pathlib import Path
import csv, hashlib, json, statistics
ROOT = Path(__file__).resolve().parent
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
OK = hashlib.sha256(b'ok').hexdigest()
METRICS = ('instructions', 'allocated_bytes', 'reclaimed_bytes')
AFFECTED = {'Nat8', 'Int8', 'Nat16', 'Int16', 'Nat32', 'Int32', 'Char'}
rows = []
for suite in ('scalar', 'map'):
    folder = ROOT if suite == 'scalar' else ROOT / 'map'
    manifest = json.loads((folder / 'cases.json').read_text())
    specs = {c['name']: c for c in manifest['cases']}
    assert len(specs) == len(manifest['cases'])
    provenance = json.loads((folder / 'provenance.json').read_text())
    versions = {}
    for version in ('baseline', 'candidate'):
        report = json.loads((folder / f'{version}.json').read_text())
        assert not report.get('fatal_error') and report['failed_measurements'] == 0
        assert report['trials'] == 3
        assert report['source_sha256'] == sha(folder / 'main.mo')
        assert report['cases_sha256'] == sha(folder / 'cases.json')
        assert report['runner_sha256'] == sha(ROOT / 'run.mjs')
        assert report['wasm_sha256'] == provenance['compilers'][version]['wasm']
        assert len(report['cases']) == len(specs)
        seen = set()
        samples = {}
        for case in report['cases']:
            name = case['name']
            assert name in specs and name not in seen
            seen.add(name)
            assert case['phases'] == specs[name]['phases']
            phases = [p['label'] for p in case['phases']]
            assert len(phases) == len(set(phases))
            group = {(m['trial'], m['phase']): m for m in case['measurements']}
            assert len(group) == len(case['measurements'])
            assert set(group) == {(trial, phase) for trial in range(3) for phase in phases}
            for (trial, phase), sample in group.items():
                assert 'error' not in sample
                assert sample['output_sha256'] == OK and sample['output_bytes'] == 2
                for field in METRICS:
                    assert type(sample[field]) is int and sample[field] >= 0
                assert sample['instructions'] > 0 and sample['reclaimed_bytes'] == 0
                samples[name, phase, trial] = sample
        assert seen == set(specs)
        versions[version] = samples
    assert versions['baseline'].keys() == versions['candidate'].keys()
    for name, spec in specs.items():
        for phase in (p['label'] for p in spec['phases']):
            values = {}
            for version in versions:
                group = [versions[version][name, phase, trial] for trial in range(3)]
                values[version] = {field: statistics.median(g[field] for g in group) for field in METRICS}
                for field in METRICS:
                    assert len({g[field] for g in group}) == 1, (suite, name, phase, field)
            before, after = values['baseline'], values['candidate']
            assert before['allocated_bytes'] == after['allocated_bytes']
            assert after['instructions'] <= before['instructions']
            if suite == 'scalar':
                repetitions = [0, 1, 4096][spec['index']]
                expected = 4 * 42 * repetitions if phase in AFFECTED else 0
                assert before['instructions'] - after['instructions'] == expected
            rows.append({'suite': suite, 'workload': name, 'phase': phase,
                'baseline_instructions': before['instructions'], 'candidate_instructions': after['instructions'],
                'instruction_change_pct': round(100 * (after['instructions'] / before['instructions'] - 1), 6),
                'baseline_allocated_bytes': before['allocated_bytes'], 'candidate_allocated_bytes': after['allocated_bytes'],
                'reclaimed_bytes': 0, 'trials': 3})
with (ROOT / 'summary.csv').open('w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
print(f'Validated {len(rows)} paired phases, {len(rows) * 6} measurements; no failures, complete trials, outputs match.')
for row in rows:
    if row['suite'] == 'map': print(row)
