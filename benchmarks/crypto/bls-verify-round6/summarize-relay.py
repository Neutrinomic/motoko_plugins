#!/usr/bin/env python3
"""Compare the unchanged certificate investigation against the selected BLS runtime."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def read(name):
    path = HERE / name
    raw = path.read_bytes()
    report = json.loads(raw)
    assert report['complete'] is True and 'error' not in report
    assert report['trials'] == 3 and len(report['cases']) == 15
    assert len(report['negative_checks']) == 12
    assert all(row['rejected'] is True for row in report['negative_checks'])
    cases = {}
    for case in report['cases']:
        samples = case['measurements']
        assert len(samples) == 3 and {row['trial'] for row in samples} == {0, 1, 2}
        assert all(row['correct'] is True for row in samples)
        values = {(row['instructions'], row['allocated_bytes'], row['reclaimed_bytes']) for row in samples}
        assert len(values) == 1, 'Observed non-identical trials; do not silently discard variation'
        key = (case['scenario'], case['mode'], case['leaf_count'])
        assert key not in cases
        cases[key] = dict(zip(('instructions', 'allocated_bytes', 'reclaimed_bytes'), values.pop()))
    return report, cases, hashlib.sha256(raw).hexdigest()


baseline, before, baseline_hash = read('relay-baseline.json')
candidate, after, candidate_hash = read('relay-results.json')
for field in ('methodology', 'compiler_sha256', 'compiler_version', 'pocket_ic_version',
              'source_sha256', 'fixtures', 'negative_checks'):
    assert baseline[field] == candidate[field], 'Different relay ' + field
assert baseline['plugins']['sha256'] == candidate['plugins']['sha256']
assert before.keys() == after.keys()
rows = []
for key, first in before.items():
    second = after[key]
    assert first['allocated_bytes'] == second['allocated_bytes']
    assert first['reclaimed_bytes'] == second['reclaimed_bytes'] == 0
    if key[0] in ('cached-certified-root', 'parse-and-hash-only'):
        assert first == second, 'Non-BLS control changed'
    rows.append(dict(scenario=key[0], mode=key[1], leaf_count=key[2], baseline=first,
                     candidate=second, instruction_saving_percent=100 *
                     (first['instructions'] - second['instructions']) / first['instructions']))
summary = dict(protocol='ic-certified-relay-bls-comparison-v1',
               baseline_sha256=baseline_hash, candidate_sha256=candidate_hash,
               compiler_sha256=baseline['compiler_sha256'],
               baseline_bls_runtime_sha256=baseline['plugins']['bls12-381']['runtime.wasm'],
               candidate_bls_runtime_sha256=candidate['plugins']['bls12-381']['runtime.wasm'],
               trials_per_case_per_revision=3, case_count=len(rows), cases=rows)
with (HERE / 'relay-comparison.json').open('x') as output:
    json.dump(summary, output, indent=2)
    output.write('\n')
print('15 relay cases and 12 rejection controls validated on each revision.')
