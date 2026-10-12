#!/usr/bin/env python3
"""Verify final table pins, preserved evidence, and the portable source archive."""
import argparse, hashlib, json, tarfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent
ROOT = BENCH.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--restored', type=Path, help='Optional restored round2-api-final directory')
args = parser.parse_args()
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
read = lambda path: json.loads(path.read_text())
preserved = read(HERE / 'round1-preservation.json')['sha256']
for name, digest in preserved.items():
    assert sha(BENCH / name) == digest, 'Round-one evidence changed: ' + name
fingerprint = read(HERE / 'api-final-fingerprint.json')
for name, digest in fingerprint['source_and_artifact_sha256'].items():
    assert sha(ROOT / name) == digest, 'Final production input changed: ' + name
measurements = read(HERE / 'api-measurements.json')
assert measurements['callable_count'] == 155 and measurements['workload_row_count'] == 181
assert measurements['selection_sha256'] == sha(HERE / 'api-selection.json')
assert measurements['inventory_sha256'] == sha(HERE / 'api-inventory.json')
for stage, pins in measurements['stages'].items():
    for filename in ['build', 'results']:
        assert sha(BENCH / 'results' / stage / (filename + '.json')) == pins[filename + '_sha256']
refs = {}
for row in measurements['rows']:
    for kind, value in row['measurements'].items():
        ref = row[kind + '_case']
        assert sha(BENCH / ref['source']) == value['source_sha256'] == ref['source_sha256']
        assert value['trials'] == 3
        refs[(value['name'], value['implementation'], value['source_sha256'])] = kind
    if 'native' in row['measurements']:
        assert row['measurements']['native']['expected_hex'] == row['measurements']['plugin']['expected_hex']
index = read(HERE / 'source-store.json')
assert sha(HERE / 'source-store.tar.gz') == index['sha256']
with tarfile.open(HERE / 'source-store.tar.gz', 'r:gz') as archive:
    blobs = {Path(member.name).name: archive.extractfile(member).read() for member in archive if member.isfile()}
for digest, data in blobs.items():
    assert hashlib.sha256(data).hexdigest() == digest
assert len(blobs) == index['unique_files']
for name, digest in index['stage_maps'].items():
    mapping_path = BENCH / name
    assert sha(mapping_path) == digest
    for relative, pin in read(mapping_path)['files'].items():
        path = Path(relative)
        assert not path.is_absolute() and '..' not in path.parts
        assert '_out' not in path.parts and path.suffix not in {'.wasm', '.cmxs', '.cmo', '.cmi', '.cmx', '.o', '.a', '.so', '.pyc'}
        assert pin['sha256'] in blobs
        if args.restored and mapping_path.parent.name == 'round2-api-final':
            assert sha(args.restored / relative) == pin['sha256']
wrappers = read(HERE / 'wrapper-provenance.json')
for digest, relative in wrappers['versions'].items():
    assert sha(HERE / relative) == digest
for stage, pin in wrappers['stages'].items():
    assert read(BENCH / 'results' / stage / 'round2.json')['wrapper_sha256'] == pin['wrapper_sha256']
    assert sha(HERE / pin['source']) == pin['wrapper_sha256']
displayed = set(measurements['displayed_api_rows'])
summary = {
    'status': 'pass', 'callables': 155, 'workload_rows': 181,
    'paired_displayed_callables': sum(row['id'] in displayed and 'native' in row['measurements'] for row in measurements['rows']),
    'plugin_fixtures': sum(kind == 'plugin' for kind in refs.values()),
    'pure_motoko_fixtures': sum(kind == 'native' for kind in refs.values()),
    'represented_trials': len(refs) * 3,
    'unchanged_round_one_files': len(preserved),
    'final_production_pins': len(fingerprint['source_and_artifact_sha256']),
    'source_archive_stages': len(index['stage_maps']), 'source_archive_contents': len(blobs),
    'source_archive_bytes': (HERE / 'source-store.tar.gz').stat().st_size,
    'launcher_snapshots_checked': len(wrappers['stages']),
    'final_stage_restore_verified': bool(args.restored),
    'evidence_sha256': {name: sha(HERE / name) for name in ['api-measurements.json', 'api-inventory.json', 'api-selection.json', 'api-final-fingerprint.json', 'source-store.json', 'source-store.tar.gz', 'wrapper-provenance.json', 'experiment-review.json', 'RESULTS.md']},
    'table_sha256': sha(ROOT / 'benchmark_crypto.md'),
}
(HERE / 'final-verification.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({key: value for key, value in summary.items() if 'sha256' not in key}, indent=2))
