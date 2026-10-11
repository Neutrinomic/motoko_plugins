#!/usr/bin/env python3
"""Validate all paired trials and regenerate CBOR optimization CSV tables."""
import csv
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
provenance = json.loads((root / 'provenance.json').read_text())
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(root / 'run.mjs') == provenance['runner_sha256']
for version, source in (('baseline', 'before'), ('final', 'after')):
    build = json.loads((root / f'{version}-build.json').read_text())
    assert not build['motoko_dirty']
    assert build['motoko_revision'] == provenance['compiler_revision']
    assert build['moc_sha256'] == provenance['compiler_executable_sha256']
    assert build['sha256'] == provenance['artifacts'][version]['package_sha256']
    expected_source = build['source_sha256']['plugins/cbor/runtime/src/lib.rs']
    assert sha(root / 'validation' / f'runtime-{source}.rs') == expected_source
    assert expected_source == provenance['artifacts'][version]['runtime_source_sha256']
for name, expected in provenance.get('archive_files', {}).items():
    assert sha(root / name) == expected, name
for name, expected in json.loads((root / 'validation/audit-provenance.json').read_text())['archive_files'].items():
    assert sha(root / name) == expected, name
rows = []
for suffix in ('', '-edges', '-errors', '-integers'):
    before = json.loads((root / f'baseline{suffix}.json').read_text())
    after = json.loads((root / f'final{suffix}.json').read_text())
    suite = suffix.removeprefix('-') or 'core'
    for version, report in (('baseline', before), ('final', after)):
        assert report['source_sha256'] == provenance['inputs'][suite]['source_sha256']
        assert report['cases_sha256'] == provenance['inputs'][suite]['cases_sha256']
        assert report['runner_sha256'] == provenance['runner_sha256']
        assert report['wasm_sha256'] == provenance['artifacts'][version]['actors_sha256'][suite]
    for key in ('source_sha256', 'cases_sha256', 'runner_sha256'):
        assert before[key] == after[key], (suffix, key)
    for report in (before, after):
        assert not report.get('fatal_error')
        assert report['failed_measurements'] == 0
    assert before['measurement_protocol'] == after['measurement_protocol']
    assert before['pocket_ic_version'] == after['pocket_ic_version']
    assert before['trials'] == after['trials'] == 3
    assert [c['name'] for c in before['cases']] == [c['name'] for c in after['cases']]
    for bcase, acase in zip(before['cases'], after['cases']):
        assert bcase['phases'] == acase['phases']
        assert len(bcase['measurements']) == len(acase['measurements']) == 3 * len(bcase['phases'])
        for phase in bcase['phases']:
            label = phase['label']
            bs = [m for m in bcase['measurements'] if m['phase'] == label]
            ats = [m for m in acase['measurements'] if m['phase'] == label]
            assert [m['trial'] for m in bs] == [m['trial'] for m in ats] == [0, 1, 2]
            for key in ('instructions', 'allocated_bytes', 'reclaimed_bytes', 'output_sha256'):
                assert len({m[key] for m in bs}) == len({m[key] for m in ats}) == 1
            assert bs[0]['output_sha256'] == ats[0]['output_sha256']
            for sample in bs + ats:
                assert 'error' not in sample
            if label != 'plugin':
                for key in ('instructions', 'allocated_bytes', 'reclaimed_bytes'):
                    assert bs[0][key] == ats[0][key], (suffix, bcase['name'], label, key)
            if label == 'plugin':
                assert bs[0]['reclaimed_bytes'] == ats[0]['reclaimed_bytes'] == 0
            bi, ai = bs[0]['instructions'], ats[0]['instructions']
            ba, aa = bs[0]['allocated_bytes'], ats[0]['allocated_bytes']
            rows.append([bcase['name'], label, bi, ai, f'{100*(ai/bi-1):.2f}',
                         ba, aa, f'{100*(aa/ba-1):.2f}'])

with (root / 'summary.csv').open('w') as output:
    writer = csv.writer(output, lineterminator='\n')
    writer.writerow(['workload', 'implementation', 'baseline_instructions', 'final_instructions',
                     'instructions_change_percent', 'baseline_allocated_bytes',
                     'final_allocated_bytes', 'allocation_change_percent'])
    writer.writerows(rows)
print(f'Validated {len(rows)} paired measurements, each with three identical trials.')
for row in rows:
    if row[1] == 'plugin':
        name, _, bi, ai, change, ba, aa, _ = row
        print(f'| {name.removeprefix("cbor-")} | {bi:,} → {ai:,} | {change}% | {ba:,} → {aa:,} |')
