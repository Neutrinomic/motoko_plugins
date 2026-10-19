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
p.add_argument('--allow-partial', action='store_true', help='summarize an explicitly filtered candidate screen')
p.add_argument('--require-native-win', action='store_true',
               help='require three trials and lower ICWire encode/decode medians on every workload')
p.add_argument('--require-candidx-win', action='store_true',
               help='also gate against CandidX encoding and native decoding of CandidX bytes')
a = p.parse_args()
report = json.loads(a.results.read_text())
if report.get('failed_measurements') or report.get('fatal_error'):
    raise SystemExit('refusing failed benchmark report')
manifest_path = a.cases or a.results.parent / 'sources/cases.json'
manifest_bytes = manifest_path.read_bytes()
if hashlib.sha256(manifest_bytes).hexdigest() != report['cases_sha256']:
    raise SystemExit('case manifest does not match report')
specs = {case['name']: case for case in json.loads(manifest_bytes)['cases']}
names = [case['name'] for case in report['cases']]
if not names or len(names) != len(set(names)):
    raise SystemExit('empty report or duplicate workload names')
if not set(names) <= set(specs) or (not a.allow_partial and set(names) != set(specs)):
    raise SystemExit('report workloads do not match the complete manifest; use --allow-partial for screens')
build = json.loads((a.results.parent / 'build.json').read_text())
archive = build['archive_sha256']
for field, filename in [('source_sha256', 'sources/main.mo'), ('wasm_sha256', 'main.wasm'),
                        ('runner_sha256', 'sources/run.mjs')]:
    if report[field] != archive[filename]:
        raise SystemExit(f'{field} differs from archived build inputs')
    path = a.results.parent / filename
    # Wasm binaries are intentionally not committed, but their build hashes are.
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() != archive[filename]:
        raise SystemExit(f'archived input changed: {filename}')
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
if ('control', 'overhead') in by_key:
    print(f'Control interval: {by_key[("control", "overhead")]["instructions"]:,} instructions; no subtraction.\n')
print('| Workload | Candid enc | ICWire enc | Candid dec | ICWire dec | CandidX enc | Bytes Candid / ICWire |')
print('| --- | ---: | ---: | ---: | ---: | ---: | ---: |')
for name in [case['name'] for case in report['cases']]:
    if name == 'control':
        continue
    def val(phase, key='instructions'):
        value = by_key.get((name, phase), {}).get(key)
        return '—' if value is None else f'{value:,}'
    print(f'| {name} | {val("candid_encode")} | {val("icwire_encode")} | {val("candid_decode")} | {val("icwire_decode")} | {val("candidx_encode")} | {val("candid_encode", "wire_bytes")} / {val("icwire_encode", "wire_bytes")} |')
print(out)
if a.require_native_win or a.require_candidx_win:
    if a.allow_partial or report['trials'] < 3:
        raise SystemExit('instruction gates require a complete suite and at least three trials')
    for baseline, enabled, label in [('candid', a.require_native_win, 'Native'),
                                     ('candidx', a.require_candidx_win, 'CandidX')]:
        if not enabled:
            continue
        losses = []
        for name in names:
            if name == 'control':
                continue
            for operation in ['encode', 'decode']:
                other = by_key[(name, baseline + '_' + operation)]['instructions']
                wire = by_key[(name, 'icwire_' + operation)]['instructions']
                if wire >= other:
                    losses.append(f'{name}/{operation}: ICWire {wire:,} >= {label} {other:,}')
        if losses:
            raise SystemExit(f'{label}-win gate failed:\n' + '\n'.join(losses))
        print(f'{label}-win gate passed: {len(names) - ("control" in names)} workloads, encode and decode, {report["trials"]} trials.')
