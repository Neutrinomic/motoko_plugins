#!/usr/bin/env python3
"""Validate complete mutable-map trials and print raw and per-operation cost summaries."""
import argparse
import csv
import hashlib
import json
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('reports', nargs='*', type=Path)
parser.add_argument('--cases', type=Path)
parser.add_argument('--out', type=Path)
parser.add_argument('--archive', type=Path, help='Verify archive hashes and reproduce all archived cohort tables offline')
parser.add_argument('--expected-trials', type=int, default=3)
args = parser.parse_args()
if args.archive:
    archive = args.archive.resolve()
    inventory = json.loads((archive / 'artifact-manifest.json').read_text())
    present = {path.relative_to(archive).as_posix() for path in archive.rglob('*')
               if path.is_file() and path.name != 'artifact-manifest.json'
               and path.suffix not in ('.wasm', '.cmxs') and '__pycache__' not in path.parts}
    assert present == set(inventory['files']), 'Unlisted or missing archive files'
    for name, item in inventory['files'].items():
        assert not Path(name).is_absolute() and '..' not in Path(name).parts, name
        payload = (archive / name).read_bytes()
        assert len(payload) == item['size'] and hashlib.sha256(payload).hexdigest() == item['sha256'], name
    with tempfile.TemporaryDirectory(prefix='mutable-map-archive-') as temporary:
        for name, trials in inventory['cohorts'].items():
            assert not Path(name).is_absolute() and '..' not in Path(name).parts, name
            cohort = archive / name
            output = Path(temporary) / 'summary.csv'
            table = subprocess.check_output([
                sys.executable, str(Path(__file__).resolve()), str(cohort / 'results.json'),
                '--cases', str(cohort / 'cases.json'), '--out', str(output),
                '--expected-trials', str(trials)])
            assert output.read_bytes() == (cohort / 'summary.csv').read_bytes(), name + '/summary.csv'
            assert table == (cohort / 'costs.md').read_bytes(), name + '/costs.md'
    print(f"Verified {len(inventory['files'])} archive files and {len(inventory['cohorts'])} complete cohorts")
    raise SystemExit(0)
if not args.reports or not args.cases or not args.out or args.expected_trials < 1:
    parser.error('reports, --cases, --out and a positive --expected-trials are required unless using --archive')
manifest = json.loads(args.cases.read_text())
provenance_path = args.cases.parent / 'provenance.json'
provenance = json.loads(provenance_path.read_text())
assert hashlib.sha256(provenance_path.read_bytes()).hexdigest() == manifest['provenance']['full_provenance_sha256']
assert hashlib.sha256((args.cases.parent / 'main.mo').read_bytes()).hexdigest() == provenance['artifacts']['main.mo']
wasm = args.cases.parent / 'main.wasm'
if wasm.exists():
    assert hashlib.sha256(wasm.read_bytes()).hexdigest() == provenance['artifacts']['main.wasm']
for name, digest in provenance['plugin']['source_sha256'].items():
    assert not Path(name).is_absolute() and '..' not in Path(name).parts
    assert hashlib.sha256((args.cases.parent / 'sources' / name).read_bytes()).hexdigest() == digest
runner_digest = hashlib.sha256((args.cases.parent / 'harness/run.mjs').read_bytes()).hexdigest()
specs = {case['name']: case for case in manifest['cases']}
assert len(specs) == len(manifest['cases']), 'Duplicate manifest case names'
detail_fields = tuple(field for field in ('public_function', 'static_public_function',
                                         'core_function', 'adapter_note', 'workload_kind', 'unit')
                      if any(field in case for case in specs.values()))
identities, seen, rows = set(), set(), []
labels = ('core', 'plugin_custom', 'plugin_static')
expected_digest = hashlib.sha256(b'ok').hexdigest()


def natural(value):
    assert type(value) is int or (isinstance(value, str) and value.isascii() and value.isdecimal())
    result = int(value)
    assert result >= 0
    return result


for path in args.reports:
    report = json.loads(path.read_text())
    assert not report.get('fatal_error'), report.get('fatal_error')
    assert report['implementations']['core']['module'] == 'Map', 'Expected mutable Core Map baseline'
    assert report['implementations']['core']['version'] == '2.5.0'
    assert report.get('provenance') == manifest.get('provenance'), 'Report provenance differs from manifest'
    assert report['runner_sha256'] == runner_digest
    assert report['source_sha256'] == provenance['artifacts']['main.mo']
    assert report['wasm_sha256'] == provenance['artifacts']['main.wasm']
    assert report['failed_measurements'] == 0, f'{path}: failed measurements'
    assert report['trials'] == args.expected_trials, f'{path}: wrong trial count'
    assert report['cases_sha256'] == hashlib.sha256(args.cases.read_bytes()).hexdigest(), \
        f'{path}: report was measured with a different manifest'
    identities.add((report['wasm_sha256'], report['source_sha256'], report['cases_sha256'],
                    report['runner_sha256'], report['pocket_ic_version']))
    for case in report['cases']:
        name = case['name']
        assert name in specs and name not in seen, f'{name}: unexpected or duplicate case'
        seen.add(name)
        spec = specs[name]
        assert case['phases'] == spec['phases'], f'{name}: different phase protocol'
        phases = [phase['label'] for phase in spec['phases']]
        assert {'core', 'plugin_custom'} <= set(phases) <= set(labels), f'{name}: unsupported comparison phases'
        count = natural(spec['operations_per_phase'])
        assert count > 0
        samples = {(sample['trial'], sample['phase']): sample for sample in case['measurements']}
        assert len(samples) == len(case['measurements']), f'{name}: duplicate measurements'
        assert set(samples) == {(trial, phase) for trial in range(args.expected_trials) for phase in phases}, \
            f'{name}: missing trials/phases'
        row = {'workload': name, 'map_size': spec['map_size'], 'operation': spec['operation'],
               'operations_per_phase': count, 'trials': args.expected_trials}
        for field in detail_fields:
            row[field] = spec.get(field, '')
            assert isinstance(row[field], str), f'{name}: {field} must be text'
        for label in labels:
            fields = ('instructions', 'allocated_bytes', 'reclaimed_bytes')
            if label not in phases:
                for field in fields:
                    row[f'{label}_{field}'] = ''
                    row[f'{label}_{field}_per_op'] = ''
                row[f'{label}_instructions_min'] = ''
                row[f'{label}_instructions_max'] = ''
                continue
            group = [samples[trial, label] for trial in range(args.expected_trials)]
            for sample in group:
                assert 'error' not in sample, f'{name}/{label}: {sample.get("error")}'
                assert sample['output_sha256'] == expected_digest and natural(sample['output_bytes']) == 2
                for field in fields:
                    sample[field] = natural(sample[field])
                assert sample['instructions'] > 0
            for field in fields:
                value = statistics.median(sample[field] for sample in group)
                row[f'{label}_{field}'] = value
                row[f'{label}_{field}_per_op'] = value / count
            row[f'{label}_instructions_min'] = min(sample['instructions'] for sample in group)
            row[f'{label}_instructions_max'] = max(sample['instructions'] for sample in group)
        row['core_over_custom'] = row['core_instructions'] / row['plugin_custom_instructions']
        row['core_over_static'] = (row['core_instructions'] / row['plugin_static_instructions']
                                   if row['plugin_static_instructions'] != '' else '')
        rows.append(row)

assert seen == set(specs), f'Missing cases: {set(specs) - seen}'
assert len(identities) == 1, 'Cannot combine different compiler/runner/manifest snapshots'
rows.sort(key=lambda row: (row['map_size'], row['operation']))
args.out.parent.mkdir(parents=True, exist_ok=True)
with args.out.open('w', newline='') as output:
    writer = csv.DictWriter(output, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
has_functions = 'public_function' in detail_fields
if has_functions:
    assert all(row.get('workload_kind') in ('construction', 'populated-map') for row in rows), \
        'Unknown function workload kind'
    print('# Mutable map function costs\n')
    print(f'{args.expected_trials}-trial medians, normalized by the number of complete operations in each batch. '
          'Both implementations use the same compiler and inputs. Allocated bytes include '
          'temporary objects and retained results; they are not peak or live heap size. '
          'Core/plugin above 1 means fewer plugin instructions.\n')
    print('Point-function rows are per call. `get` is key lookup; `find` is ordered predicate search. Iterator `create` rows '
          'measure cursor creation only; `consume` rows include creation and the entire '
          'map traversal; `seek16` rows include creation and 16 entries. Fold, transform, '
          'clone, clear, and construction rows measure the complete function call. Core adapters '
          'are listed below; see [methodology](README.md) for exact semantics and validation.\n')
    for kind, title in (('construction', 'Construction'), ('populated-map', 'Operations on populated maps')):
        group = [row for row in rows if row.get('workload_kind') == kind]
        if not group:
            continue
        print(f'## {title}\n')
        print('| Public function | Workload | Size | Core instructions/op | Plugin callback/op | Core allocated B/op | Plugin allocated B/op | Core/plugin |')
        print('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |')
        for row in sorted(group, key=lambda row: (row['operation'], row['map_size'])):
            values = [f'{row[field]:,.2f}' for field in
                      ('core_instructions_per_op', 'plugin_custom_instructions_per_op',
                       'core_allocated_bytes_per_op', 'plugin_custom_allocated_bytes_per_op')]
            print(f'| `Map.{row["public_function"]}` | {row["operation"]} | {row["map_size"]:,} | ' +
                  ' | '.join(values) + f' | {row["core_over_custom"]:.2f}× |')
        print()
    scalar_rows = [row for row in rows if row['plugin_static_instructions'] != '']
    if scalar_rows:
        print('## Scalar ordering on the same workloads\n')
        print('The callback path uses the same Motoko comparator as Core. The scalar path '
              'orders Nat64 keys directly; values remain generic Motoko references.\n')
        print('| Scalar function | Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core allocated B/op | Callback allocated B/op | Scalar allocated B/op |')
        print('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |')
        for row in sorted(scalar_rows, key=lambda row: (row['operation'], row['map_size'])):
            values = [f'{row[field]:,.2f}' for field in
                      ('core_instructions_per_op', 'plugin_custom_instructions_per_op',
                       'plugin_static_instructions_per_op', 'core_allocated_bytes_per_op',
                       'plugin_custom_allocated_bytes_per_op', 'plugin_static_allocated_bytes_per_op')]
            print(f'| `Map.{row.get("static_public_function", "")}` | {row["operation"]} | {row["map_size"]:,} | ' +
                  ' | '.join(values) + ' |')
    details = sorted({(row['operation'], row.get('core_function', ''), row.get('adapter_note', ''))
                      for row in rows if row.get('adapter_note', '')})
    if details:
        print('\n## Core baseline details\n')
        print('Explicit adapters are used where Core has no matching public API. '
              'All direct baselines use mo:core/Map 2.5.0; find/getEntry use the listed small public API adapters.\n')
        print('| Workload | Core baseline | Note |')
        print('| --- | --- | --- |')
        for operation, core_function, note in details:
            print(f'| {operation} | `{core_function}` | {note} |')
else:
    print('| Workload | Size | Core instructions/op | Plugin callback/op | Plugin scalar/op | Core/callback | Core/scalar |')
    print('| --- | ---: | ---: | ---: | ---: | ---: | ---: |')
    for row in rows:
        counts = [f'{row[label + "_instructions_per_op"]:,.2f}'
                  if row[label + '_instructions_per_op'] != '' else '—' for label in labels]
        ratio = f'{row["core_over_static"]:.2f}×' if row['core_over_static'] != '' else '—'
        print(f'| {row["operation"]} | {row["map_size"]:,} | ' + ' | '.join(counts) +
              f' | {row["core_over_custom"]:.2f}× | {ratio} |')
if has_functions:
    print('\nRaw batch totals, allocation/op, reclamation/op, and trial ranges are in [summary.csv](summary.csv).')
else:
    print('\nRaw batch totals, allocation/op, reclamation/op, and trial ranges are in ' + str(args.out))
