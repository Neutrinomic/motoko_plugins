#!/usr/bin/env python3
"""Validate archived CBOR trials and regenerate the three-stage comparison CSV."""
import csv
import json
from pathlib import Path

out = Path(__file__).resolve().parent
old = out.parent.parent / 'cbor'


def read(path):
    return json.loads(path.read_text())


rows = []
for suite, suffix in [('core', ''), ('edges', '-edges'), ('errors', '-errors')]:
    baseline = read(old / f'baseline{suffix}.json')
    audited = read(old / f'final{suffix}.json')
    integrated = read(out / f'{suite}.json')
    for key in ('source_sha256', 'cases_sha256', 'runner_sha256'):
        assert baseline[key] == audited[key] == integrated[key], (suite, key)
    for report in (baseline, audited, integrated):
        assert report['trials'] == 3 and report['failed_measurements'] == 0
    assert [c['name'] for c in baseline['cases']] == [c['name'] for c in audited['cases']] == [c['name'] for c in integrated['cases']]
    for bc, ac, ic in zip(baseline['cases'], audited['cases'], integrated['cases']):
        assert bc['phases'] == ac['phases'] == ic['phases']
        for phase in ic['phases']:
            label = phase['label']
            samples = []
            for case in (bc, ac, ic):
                values = [m for m in case['measurements'] if m['phase'] == label]
                assert [m['trial'] for m in values] == [0, 1, 2]
                for key in ('instructions', 'allocated_bytes', 'reclaimed_bytes', 'output_sha256'):
                    assert len({m[key] for m in values}) == 1, (case['name'], key)
                if label == 'plugin':
                    assert values[0]['reclaimed_bytes'] == 0
                samples.append(values[0])
            b, a, i = samples
            assert b['output_sha256'] == a['output_sha256'] == i['output_sha256']
            rows.append({
                'workload': ic['name'], 'implementation': label,
                'baseline_instructions': b['instructions'],
                'audited_f1_instructions': a['instructions'],
                'integrated_instructions': i['instructions'],
                'instructions_change_vs_baseline_percent': round(100*(i['instructions']/b['instructions']-1), 4),
                'instructions_change_vs_audited_f1_percent': round(100*(i['instructions']/a['instructions']-1), 4),
                'baseline_allocated_bytes': b['allocated_bytes'],
                'audited_f1_allocated_bytes': a['allocated_bytes'],
                'integrated_allocated_bytes': i['allocated_bytes'],
                'allocation_change_vs_baseline_percent': round(100*(i['allocated_bytes']/b['allocated_bytes']-1), 4),
                'allocation_change_vs_audited_f1_percent': round(100*(i['allocated_bytes']/a['allocated_bytes']-1), 4),
            })

with (out / 'comparison.csv').open('w') as file:
    writer = csv.DictWriter(file, fieldnames=rows[0].keys(), lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)

print(f'Validated {len(rows)} phase rows with three stable trials at each stage.')
