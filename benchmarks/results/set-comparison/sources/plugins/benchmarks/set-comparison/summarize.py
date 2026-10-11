#!/usr/bin/env python3
"""Verify retained set benchmark evidence and print instruction/allocation tables."""
import argparse
import hashlib
import json
import statistics
from pathlib import Path


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('archive', type=Path)
parser.add_argument('--operations', help='Comma-separated subset of operations')
args = parser.parse_args()
archive = args.archive.resolve()
manifest = json.loads((archive / 'manifest.json').read_text())
for relative, digest in manifest.items():
    path = archive / relative
    if not path.resolve().is_relative_to(archive):
        raise ValueError(f'Invalid archive path: {relative}')
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f'Archive checksum mismatch: {relative}')
provenance = json.loads((archive / 'provenance.json').read_text())
if provenance['status'] != 'complete':
    raise ValueError('Incomplete benchmark archive')
results = json.loads((archive / 'results.json').read_text())
if len(results) != provenance['case_count'] or len({row['metrics_key'] for row in results}) != len(results):
    raise ValueError('Summary has an incorrect number of distinct cases')
for row in results:
    if len(row['samples']) != provenance['trials']:
        raise ValueError(f'Incorrect trial count: {row["metrics_key"]}')
    for trial, sample in enumerate(row['samples'], 1):
        name = Path(row['config']).parent.name
        raw = json.loads((archive / 'raw' / f'trial-{trial}' / name / 'test-metrics.json').read_text())
        actual = {key: int(value) for key, value in raw['metrics'][row['metrics_key']].items()}
        if sample != actual:
            raise ValueError(f'Summary differs from raw sample: {row["metrics_key"]}')
    instructions = statistics.median(sample['instructions'] for sample in row['samples'])
    allocated = statistics.median(sample['totalAllocatedBytes'] for sample in row['samples'])
    stable = len({(sample['instructions'], sample['totalAllocatedBytes']) for sample in row['samples']}) == 1
    if (instructions, allocated, stable) != (row['instructions'], row['allocated_bytes'], row['stable']):
        raise ValueError(f'Cached medians/stability differ from raw samples: {row["metrics_key"]}')
if all(row['stable'] for row in results) != provenance['stable_instructions_and_allocations']:
    raise ValueError('Overall stability differs from individual sample results')
selected = set(args.operations.split(',')) if args.operations else None
print('Each cell is median IC instructions / cumulative allocated bytes per operation. '
      'Point operations average 32 probes; construction, iteration, union, and intersection '
      'measure one complete operation. Inputs are freshly rebuilt outside the measured '
      'block, except construction itself. Validation follows measurement. '
      'All keys are Nat; generic uses a comparator callback, native uses the Nat helper.\n')
print(f'{provenance["case_count"]} cases × {provenance["trials"]} independent trials. '
      f'Instruction and allocation counts identical across trials: '
      f'{provenance["stable_instructions_and_allocations"]}.\n')
for family in sorted({row['family'] for row in results}):
    print(f'### {family.capitalize()} Set\n')
    print('| Size | Operation | Core 2.5.0 | Plugin generic | Plugin native Nat |')
    print('|---:|---|---:|---:|---:|')
    lookup = {(row['size'], row['operation'], row['variant']): row for row in results if row['family'] == family}
    for size, operation in sorted({(key[0], key[1]) for key in lookup}):
        if selected and operation not in selected:
            continue
        cells = []
        for variant in ('core', 'generic', 'native'):
            row = lookup.get((size, operation, variant))
            if row is None:
                cells.append('—')
                continue
            count = row['operations_per_sample']
            instruction = row['instructions'] / count
            allocated = row['allocated_bytes'] / count
            cells.append(f'{instruction:,.2f} / {allocated:,.2f}')
        print(f'| {size:,} | {operation} | ' + ' | '.join(cells) + ' |')
    print()
