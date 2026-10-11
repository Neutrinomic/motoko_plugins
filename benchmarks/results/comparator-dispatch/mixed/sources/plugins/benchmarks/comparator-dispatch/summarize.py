#!/usr/bin/env python3
"""Verify comparator-dispatch evidence and print before/after tables."""
import argparse
import hashlib
import json
import statistics
from pathlib import Path


def read_archive(archive):
    archive = archive.resolve()
    manifest = json.loads((archive / 'manifest.json').read_text())
    actual_files = {path.relative_to(archive).as_posix() for path in archive.rglob('*')
                    if path.is_file() and path != archive / 'manifest.json'}
    if set(manifest) != actual_files:
        raise ValueError('archive file set differs from manifest')
    for relative, digest in manifest.items():
        path = archive / relative
        if not path.resolve().is_relative_to(archive):
            raise ValueError(f'invalid archive path: {relative}')
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f'archive checksum mismatch: {relative}')
    provenance = json.loads((archive / 'provenance.json').read_text())
    if provenance['status'] != 'complete':
        raise ValueError('incomplete benchmark archive')
    results = json.loads((archive / 'results.json').read_text())
    if len(results) != provenance['case_count'] or len({row['metrics_key'] for row in results}) != len(results):
        raise ValueError('summary has incorrect count of distinct cases')
    for row in results:
        if len(row['samples']) != provenance['trials'] or len(row['wasm_samples']) != provenance['trials']:
            raise ValueError(f'incorrect trial count: {row["metrics_key"]}')
        for trial, (sample, artifact) in enumerate(zip(row['samples'], row['wasm_samples']), 1):
            directory = archive / 'raw' / f'trial-{trial}' / Path(row['config']).parent.name
            payload = json.loads((directory / 'test-metrics.json').read_text())
            if set(payload['metrics']) != {row['metrics_key']}:
                raise ValueError(f'extra/missing raw measurement: {row["metrics_key"]}')
            raw = {name: int(value) for name, value in payload['metrics'][row['metrics_key']].items()}
            if sample != raw or artifact != json.loads((directory / 'wasm.json').read_text()):
                raise ValueError(f'summary differs from raw evidence: {row["metrics_key"]}')
        cached = (row['instructions'], row['allocated_bytes'], row['wasm_bytes'], row['stable'], row['wasm_stable'])
        computed = (statistics.median(s['instructions'] for s in row['samples']),
                    statistics.median(s['totalAllocatedBytes'] for s in row['samples']),
                    statistics.median(s['bytes'] for s in row['wasm_samples']),
                    len({(s['instructions'], s['totalAllocatedBytes']) for s in row['samples']}) == 1,
                    len({(s['sha256'], s['bytes']) for s in row['wasm_samples']}) == 1)
        if cached != computed:
            raise ValueError(f'cached medians/stability differ from samples: {row["metrics_key"]}')
    if (all(row['stable'] for row in results) != provenance['stable_instructions_and_allocations'] or
            all(row['wasm_stable'] for row in results) != provenance['stable_wasm']):
        raise ValueError('overall stability differs from sample results')
    return results, provenance


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--sizes', help='Comma-separated sizes')
    parser.add_argument('--families', help='Comma-separated families')
    parser.add_argument('--operations', help='Comma-separated operations')
    args = parser.parse_args()
    rows, provenance = read_archive(args.candidate)
    old = []
    if args.baseline:
        old, before = read_archive(args.baseline)
        if before['phase'] != 'baseline' or provenance['phase'] != 'candidate':
            raise ValueError('comparison requires baseline then candidate archive')
        # Same public wrappers and Ash metric module are required to attribute this
        # comparison to native/compiler dispatch changes.
        for directory in ('sources/fast', 'harness'):
            def hashes(archive):
                base = archive / directory
                return {str(p.relative_to(base)): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in base.rglob('*') if p.is_file()}
            if hashes(args.baseline) != hashes(args.candidate):
                raise ValueError(f'before/after {directory} differs; use the same frozen measurement inputs')
        if before['comparison_inputs'] != provenance['comparison_inputs']:
            raise ValueError('before/after execution binaries, RTS, Core or Ash inputs differ')
        common = {row['metrics_key'] for row in old}
        if not common <= {row['metrics_key'] for row in rows}:
            raise ValueError('candidate matrix is missing baseline cases')
        for key in common:
            current = next(row for row in rows if row['metrics_key'] == key)
            previous = next(row for row in old if row['metrics_key'] == key)
            name = Path(current['config']).parent / 'main.mo'
            if (args.candidate / 'sources/generated' / name).read_bytes() != (args.baseline / 'sources/generated' / name).read_bytes():
                raise ValueError(f'before/after measured program differs: {key}')
            if any(current[field] != previous[field] for field in ('family', 'variant', 'size', 'operation', 'operations_per_sample')):
                raise ValueError(f'before/after case metadata differs: {key}')
    selected_sizes = set(map(int, args.sizes.split(','))) if args.sizes else None
    selected_families = set(args.families.split(',')) if args.families else None
    selected_operations = set(args.operations.split(',')) if args.operations else None
    rows = [row for row in rows if (selected_sizes is None or row['size'] in selected_sizes)
            and (selected_families is None or row['family'] in selected_families)
            and (selected_operations is None or row['operation'] in selected_operations)]
    print('Cells show IC instructions / cumulative allocated bytes per operation, followed by complete canister Wasm bytes. '
          'Point rows average 32 probes; empty/singleton rows use one. Build measures the whole shuffled build. '
          'Setup and full-content validation are excluded. Wasm includes the RTS, harness and validation.\n')
    print(f'{provenance["phase"].capitalize()}: {provenance["case_count"]} cases × {provenance["trials"]} independent trials; '
          f'identical instruction/allocation counts: {provenance["stable_instructions_and_allocations"]}; '
          f'identical emitted Wasm: {provenance["stable_wasm"]}.\n')
    if args.baseline:
        print(f'Baseline: {before["case_count"]} cases × {before["trials"]} independent trials.\n')
    def cell(row):
        if row is None:
            return '—'
        count = row['operations_per_sample']
        return f'{row["instructions"] / count:,.2f} / {row["allocated_bytes"] / count:,.2f}; {row["wasm_bytes"]:,}'
    for family in sorted({row['family'] for row in rows}):
        subset = [row for row in rows if row['family'] == family]
        lookup = {(row['size'], row['operation'], row['variant']): row for row in subset}
        old_lookup = {(row['size'], row['operation'], row['variant']): row for row in old if row['family'] == family}
        print(f'### {family}\n')
        print('| Size | Operation / comparator | Core 2.5.0 | Before | Automatic / fallback | Explicit Nat64 |')
        print('|---:|---|---:|---:|---:|---:|')
        for size, operation in sorted({(row['size'], row['operation']) for row in subset}):
            variants = ['direct'] + sorted({row['variant'] for row in subset
                if row['size'] == size and row['operation'] == operation and row['variant'] not in {'core', 'direct', 'static'}})
            for variant in variants:
                cells = [cell(lookup.get((size, operation, 'core'))) if variant == 'direct' else '—',
                         cell(old_lookup.get((size, operation, variant))), cell(lookup.get((size, operation, variant))),
                         cell(lookup.get((size, operation, 'static'))) if variant == 'direct' else '—']
                if all(value == '—' for value in cells):
                    continue
                print(f'| {size:,} | {operation} / {variant} | ' + ' | '.join(cells) + ' |')
        print()


if __name__ == '__main__':
    main()
