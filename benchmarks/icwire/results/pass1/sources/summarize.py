#!/usr/bin/env python3
"""Validate all expected observations and summarize raw instruction medians."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
from statistics import median

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('results', type=Path)
p.add_argument('--cases', type=Path)
p.add_argument('--out', type=Path)
a = p.parse_args()
report = json.loads(a.results.read_text())
if report.get('failed_measurements') or report.get('fatal_error'):
    raise SystemExit('refusing failed benchmark report')
manifest_path = a.cases or a.results.parent / 'sources/cases.json'
manifest_bytes = manifest_path.read_bytes()
if hashlib.sha256(manifest_bytes).hexdigest() != report['cases_sha256']:
    raise SystemExit('case manifest does not match report')
specs = {case['name']: case for case in json.loads(manifest_bytes)['cases']}
rows = []
for case in report['cases']:
    spec = specs[case['name']]
    phases = [phase['label'] for phase in spec['phases']]
    for phase in phases:
        samples = [m for m in case['measurements'] if m['phase'] == phase]
        if len(samples) != report['trials'] or sorted(m['trial'] for m in samples) != list(range(report['trials'])):
            raise SystemExit(f'missing/duplicate trials: {case["name"]}/{phase}')
        if any('error' in m for m in samples):
            raise SystemExit(f'failed phase: {case["name"]}/{phase}')
        if len({m['output_sha256'] for m in samples}) != 1:
            raise SystemExit(f'output changed across trials: {case["name"]}/{phase}')
        rows.append({'workload': case['name'], 'phase': phase, 'trials': len(samples),
                     'instructions': median(int(m['instructions']) for m in samples),
                     'allocated_bytes': median(int(m['allocated_bytes']) for m in samples),
                     'reclaimed_bytes': median(int(m['reclaimed_bytes']) for m in samples),
                     'wire_bytes': median(int(m['output_bytes']) for m in samples) if phase.endswith('_encode') else '',
                     'wasm_bytes': report['wasm_bytes']})
    if len(case['measurements']) != report['trials'] * len(phases):
        raise SystemExit(f'unexpected observations: {case["name"]}')
out = a.out or a.results.with_name('summary.csv')
out.parent.mkdir(parents=True, exist_ok=True)
with out.open('w') as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
by_key = {(r['workload'], r['phase']): r for r in rows}
print('| Workload | Candid enc | ICWire enc | Candid dec | ICWire dec | CandidX enc | Bytes Candid / ICWire |')
print('| --- | ---: | ---: | ---: | ---: | ---: | ---: |')
for name in [case['name'] for case in report['cases']]:
    if name == 'control':
        print(f'Control interval: {by_key[(name, "overhead")]["instructions"]:,} instructions; no subtraction.')
        continue
    def val(phase, key='instructions'):
        value = by_key.get((name, phase), {}).get(key)
        return '—' if value is None else f'{value:,}'
    print(f'| {name} | {val("candid_encode")} | {val("icwire_encode")} | {val("candid_decode")} | {val("icwire_decode")} | {val("candidx_encode")} | {val("candid_encode", "wire_bytes")} / {val("icwire_encode", "wire_bytes")} |')
print(out)
