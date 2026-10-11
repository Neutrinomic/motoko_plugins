#!/usr/bin/env python3
"""Verify the frozen callback experiments and reproduce the final comparison."""
import argparse
import csv
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', required=True, type=Path)
args = parser.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
inventory = json.loads((ROOT / 'artifact-manifest.json').read_text())['files']
present = {path.relative_to(ROOT).as_posix() for path in ROOT.rglob('*')
           if path.is_file() and path.name != 'artifact-manifest.json'
           and path.suffix not in ('.wasm', '.cmxs')
           and not {'__pycache__', '_out', '_out-dbg'}.intersection(path.parts)}
assert present == set(inventory), 'Missing or unlisted archive files'
for name, item in inventory.items():
    data = (ROOT / name).read_bytes()
    assert len(data) == item['size'] and hashlib.sha256(data).hexdigest() == item['sha256'], name
subprocess.run([sys.executable, str(ROOT / 'sdk/verify.py')], check=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(directory, trials, pilot=False):
    report = json.loads((directory / 'results.json').read_text())
    manifest = json.loads((directory / 'cases.json').read_text())
    provenance = json.loads((directory / 'provenance.json').read_text())
    assert not report.get('fatal_error') and report['failed_measurements'] == 0
    assert report['trials'] == trials
    for field, name in [('source_sha256', 'main.mo'), ('cases_sha256', 'cases.json'),
                        ('runner_sha256', 'harness/run.mjs')]:
        assert report[field] == sha(directory / name), (directory, field)
    assert report['provenance'] == manifest['provenance']
    assert manifest['provenance']['full_provenance_sha256'] == sha(directory / 'provenance.json')
    assert report['wasm_sha256'] == provenance['artifacts']['main.wasm']
    assert report['source_sha256'] == provenance['artifacts']['main.mo']
    if (directory / 'main.wasm').exists():
        assert report['wasm_sha256'] == sha(directory / 'main.wasm')
    for name, digest in provenance['plugin']['source_sha256'].items():
        assert not Path(name).is_absolute() and '..' not in Path(name).parts
        assert sha(directory / 'sources' / name) == digest, (directory, name)
    specs = {case['name']: case for case in manifest['cases']}
    assert len(specs) == len(manifest['cases'])
    expected = {name for name in specs if not pilot or re.search(r'get-(hit|miss)-(1000|100000)$', name)}
    actual = {case['name']: case for case in report['cases']}
    assert len(actual) == len(report['cases']) and set(actual) == expected
    rows = {}
    for name, case in actual.items():
        spec = specs[name]
        assert case['phases'] == spec['phases']
        phases = [phase['label'] for phase in spec['phases']]
        assert len(phases) == len(set(phases))
        samples = {(sample['trial'], sample['phase']): sample for sample in case['measurements']}
        assert len(samples) == len(case['measurements'])
        assert set(samples) == {(trial, phase) for trial in range(trials) for phase in phases}
        for phase in phases:
            values = [samples[trial, phase] for trial in range(trials)]
            for sample in values:
                assert 'error' not in sample
                assert sample['output_bytes'] == 2
                assert sample['output_sha256'] == hashlib.sha256(b'ok').hexdigest()
                for metric in ('instructions', 'allocated_bytes', 'reclaimed_bytes'):
                    assert type(sample[metric]) is int and sample[metric] >= 0
            for metric in ('instructions', 'allocated_bytes', 'reclaimed_bytes'):
                assert len({sample[metric] for sample in values}) == 1
            rows[name, phase] = (spec, values[0])
    return report, manifest, provenance, rows


for candidate in ('baseline', 'tag-once', 'branchless'):
    for plugin in ('pure-map', 'mutable-map'):
        load(ROOT / 'pilots' / candidate / plugin, 1, pilot=True)
for cohort in ('phase-order', 'fresh-phase-smoke', 'default-smoke'):
    load(ROOT / cohort, 1)

comparisons = []
for plugin in ('pure-map', 'mutable-map'):
    loaded = []
    for candidate in ('baseline', 'combined'):
        directory = ROOT / 'final' / candidate / plugin
        loaded.append(load(directory, 3))
        script = 'summarize-map.py' if plugin == 'pure-map' else 'summarize-mutable-map.py'
        subprocess.run([sys.executable, str(ROOT / 'harness' / script),
                        str(directory / 'results.json'), '--cases', str(directory / 'cases.json'),
                        '--out', str(args.out / f'{plugin}-{candidate}.csv'), '--expected-trials', '3'],
                       check=True, stdout=subprocess.DEVNULL)
    (before, bm, bp, old), (after, am, ap, new) = loaded
    assert len(bm['cases']) == len(am['cases']) == 18
    assert {case['map_size'] for case in bm['cases']} == {1000, 10000, 100000}
    assert {k: v for k, v in bm.items() if k != 'provenance'} == {k: v for k, v in am.items() if k != 'provenance'}
    for field in ('source_sha256', 'runner_sha256', 'pocket_ic_version', 'measurement_protocol'):
        assert before[field] == after[field], field
    assert before['measurement_protocol']['fresh_canister'] == 'per workload/trial/phase'
    assert bp['dependencies'] == ap['dependencies']
    assert old.keys() == new.keys()
    for identity, (spec, first) in old.items():
        _, last = new[identity]
        name, phase = identity
        for metric in ('allocated_bytes', 'reclaimed_bytes'):
            assert first[metric] == last[metric], (identity, metric)
        if phase in ('core', 'plugin_static'):
            assert first['instructions'] == last['instructions'], identity
        count = spec['operations_per_phase']
        comparisons.append({'plugin': plugin, 'workload': name, 'size': spec['map_size'],
                            'operation': spec['operation'], 'phase': phase,
                            'operations': count, 'before_instructions': first['instructions'],
                            'after_instructions': last['instructions'],
                            'before_per_op': first['instructions'] / count,
                            'after_per_op': last['instructions'] / count,
                            'saved_percent': (1 - last['instructions'] / first['instructions']) * 100,
                            'allocated_bytes_per_op': first['allocated_bytes'] / count,
                            'reclaimed_bytes_per_op': first['reclaimed_bytes'] / count})
with (args.out / 'comparison.csv').open('w', newline='') as handle:
    writer = csv.DictWriter(handle, fieldnames=list(comparisons[0]))
    writer.writeheader()
    writer.writerows(comparisons)
for table in (ROOT / 'tables').glob('*.csv'):
    assert table.read_bytes() == (args.out / table.name).read_bytes(), table.name
print(f'Verified 36 final workloads, {len(comparisons) * 6} final measurements, pilots and phase-order diagnostics.')
