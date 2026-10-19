#!/usr/bin/env python3
"""Compare two complete runs of the same actor source and unchanged wire outputs."""
import argparse
import json
from pathlib import Path
from statistics import median
import subprocess
import sys
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('before', type=Path)
p.add_argument('after', type=Path)
a = p.parse_args()
reports = []
builds = []
for path in [a.before, a.after]:
    with tempfile.TemporaryDirectory(prefix='icwire-compare-') as temporary:
        subprocess.run([sys.executable, str(Path(__file__).with_name('summarize.py')), str(path),
                        '--out', str(Path(temporary) / 'summary.csv')],
                       check=True, stdout=subprocess.DEVNULL)
    reports.append(json.loads(path.read_text()))
    builds.append(json.loads((path.parent / 'build.json').read_text()))
before, after = reports
for field in ['source_sha256', 'cases_sha256', 'runner_sha256', 'pocket_ic_version', 'trials']:
    if before[field] != after[field]:
        raise SystemExit(f'unmatched benchmark input: {field}')
if builds[0]['toolchain_sha256'] != builds[1]['toolchain_sha256']:
    raise SystemExit('compiler/RTS changed between candidates')
def indexed(report):
    return {(c['name'], p['label']): [m for m in c['measurements'] if m['phase'] == p['label']]
            for c in report['cases'] for p in c['phases']}
left, right = indexed(before), indexed(after)
if left.keys() != right.keys():
    raise SystemExit('workloads/phases changed')
print('| Workload / phase | Before instr | After instr | Change | Before alloc B | After alloc B |')
print('| --- | ---: | ---: | ---: | ---: | ---: |')
control_changes = []
for key, old in left.items():
    new = right[key]
    if {(s['output_sha256'], s['output_bytes']) for s in old} != {(s['output_sha256'], s['output_bytes']) for s in new}:
        raise SystemExit(f'wire output changed: {key}')
    old_i = median(int(s['instructions']) for s in old)
    new_i = median(int(s['instructions']) for s in new)
    old_a = median(int(s['allocated_bytes']) for s in old)
    new_a = median(int(s['allocated_bytes']) for s in new)
    if key[1].startswith('icwire_'):
        print(f'| {key[0]} / {key[1]} | {old_i:,} | {new_i:,} | {(new_i / old_i - 1) * 100:+.2f}% | {old_a:,} | {new_a:,} |')
    elif new_i != old_i or new_a != old_a:
        control_changes.append(f'{key[0]}/{key[1]}: {old_i:,} → {new_i:,} instructions, {old_a:,} → {new_a:,} allocated B')
print(f'Whole actor Wasm: {before["wasm_bytes"]:,} → {after["wasm_bytes"]:,} B.')
if control_changes:
    print('Repeated control changes (retained heap/allocation placement can affect raw costs):')
    print('\n'.join(control_changes))
