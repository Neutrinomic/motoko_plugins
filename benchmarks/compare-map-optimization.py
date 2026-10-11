#!/usr/bin/env python3
"""Validate matched map benchmark suites and compare instructions and allocation."""
import argparse
import csv
import hashlib
import json
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--before', required=True, type=Path)
parser.add_argument('--after', required=True, type=Path)
parser.add_argument('--out', required=True, type=Path)
args = parser.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def map_source_sha(provenance):
    sources = provenance['plugin']['source_sha256']
    path = 'packages/fast/src/pure/Map.mo'
    # Archived benchmark evidence retains the source path used at measurement.
    if path not in sources:
        path = 'plugins/pure-map/motoko/Map.mo'
    return sources[path]


def load(directory, label):
    report = json.loads((directory / 'results.json').read_text())
    manifest = json.loads((directory / 'cases.json').read_text())
    provenance = json.loads((directory / 'provenance.json').read_text())
    assert report['source_sha256'] == sha(directory / 'main.mo')
    assert report['wasm_sha256'] == provenance['artifacts']['main.wasm']
    assert report['source_sha256'] == provenance['artifacts']['main.mo']
    assert manifest['provenance']['full_provenance_sha256'] == sha(directory / 'provenance.json')
    assert report['provenance'] == manifest['provenance']
    if (directory / 'main.wasm').exists():
        assert report['wasm_sha256'] == sha(directory / 'main.wasm')
    summary = args.out / f'{label}.csv'
    # The existing validator checks every declared phase/trial, oracle digest,
    # count, manifest identity, missing/duplicate sample and failed measurement.
    subprocess.run([sys.executable, str(root / 'summarize-map.py'),
                    str(directory / 'results.json'), '--cases', str(directory / 'cases.json'),
                    '--expected-trials', '3', '--out', str(summary)],
                   check=True, stdout=subprocess.DEVNULL)
    with summary.open() as handle:
        rows = {row['workload']: row for row in csv.DictReader(handle)}
    return report, manifest, provenance, rows


before, before_manifest, before_provenance, before_rows = load(args.before, 'before')
after, after_manifest, after_provenance, after_rows = load(args.after, 'after')
for field in ('source_sha256', 'runner_sha256', 'pocket_ic_version', 'trials', 'measurement_protocol'):
    assert before[field] == after[field], f'Changed benchmark protocol: {field}'
assert {k: v for k, v in before_manifest.items() if k != 'provenance'} == {
    k: v for k, v in after_manifest.items() if k != 'provenance'}, 'Changed actor inputs or workload definitions'
assert before_provenance['compiler'] == after_provenance['compiler'], 'Changed compiler'
assert before_provenance['dependencies'] == after_provenance['dependencies'], 'Changed dependencies'
assert before_rows.keys() == after_rows.keys()
rows = []
for name, old in before_rows.items():
    new = after_rows[name]
    for phase in ('core', 'plugin_custom', 'plugin_static'):
        if not old[f'{phase}_instructions']:
            continue
        row = {key: old[key] for key in ('workload', 'map_size', 'operation', 'operations_per_phase')}
        row['phase'] = phase
        for metric in ('instructions', 'allocated_bytes', 'reclaimed_bytes'):
            key = f'{phase}_{metric}'
            initial, final = float(old[key]), float(new[key])
            row[f'before_{metric}'] = int(initial)
            row[f'after_{metric}'] = int(final)
            row[f'{metric}_change_percent'] = (final / initial - 1) * 100 if initial else ''
            count = int(row['operations_per_phase'])
            row[f'before_{metric}_per_op'] = initial / count
            row[f'after_{metric}_per_op'] = final / count
            if phase == 'core':
                assert initial == final, f'Core changed: {name}/{metric}'
        rows.append(row)
with (args.out / 'comparison.csv').open('w', newline='') as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)

stable = all(len({sample[metric] for sample in case['measurements'] if sample['phase'] == phase['label']}) == 1
             for report in (before, after) for case in report['cases'] for phase in case['phases']
             for metric in ('instructions', 'allocated_bytes', 'reclaimed_bytes'))
validation = {
    'workloads': len(before_rows), 'trials_per_workload_per_build': 3,
    'measurements_per_build': sum(len(case['measurements']) for case in after['cases']),
    'all_trial_costs_identical': stable,
    'core_costs_identical_before_after': True,
    'same_actor_source_inputs_compiler_dependencies_runner_protocol': True,
    'before': {name: sha(args.before / name) for name in ('main.mo', 'cases.json', 'provenance.json', 'results.json')},
    'after': {name: sha(args.after / name) for name in ('main.mo', 'cases.json', 'provenance.json', 'results.json')},
    'before_map_sha256': map_source_sha(before_provenance),
    'after_map_sha256': map_source_sha(after_provenance),
}
(args.out / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n')
with (args.out / 'costs.md').open('w') as handle:
    handle.write('Three-trial medians per complete operation. Cursor consume includes creation and traversal; '
                 'creation retains the cursor for later validation. Allocated bytes include temporary garbage '
                 'and retained results, not peak or live heap. All Core counts are unchanged between builds.\n\n')
    handle.write('| Workload | Size | Core instructions | Before instructions | After instructions | Core allocated B | Before allocated B | After allocated B |\n')
    handle.write('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for row in rows:
        if row['phase'] != 'plugin_custom':
            continue
        old = before_rows[row['workload']]
        values = [float(old['core_instructions_per_op']), row['before_instructions_per_op'], row['after_instructions_per_op'],
                  float(old['core_allocated_bytes_per_op']), row['before_allocated_bytes_per_op'], row['after_allocated_bytes_per_op']]
        handle.write(f'| {row["operation"]} | {int(row["map_size"]):,} | ' +
                     ' | '.join(f'{value:,.2f}' for value in values) + ' |\n')
    handle.write('\n[CSV](comparison.csv) includes scalar paths, raw batch totals, allocation and reclamation changes.\n')
print(args.out / 'validation.json')
