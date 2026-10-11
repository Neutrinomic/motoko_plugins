"""Independent, deliberately local checks for the SDK round-two evidence."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read_suite(directory, scalar):
    cases = json.loads((directory / 'cases.json').read_text())['cases']
    expected = {(c['name'], p['label'], trial)
                for c in cases for p in c['phases'] for trial in range(3)}
    provenance = json.loads((directory / 'provenance.json').read_text())
    source_key = 'source' if scalar else 'actor'
    assert sha(directory / 'main.mo') == provenance[source_key]
    versions = []
    for label in ('baseline', 'candidate'):
        result = json.loads((directory / (label + '.json')).read_text())
        assert result['trials'] == 3 and result['failed_measurements'] == 0
        assert result['source_sha256'] == sha(directory / 'main.mo')
        assert result['cases_sha256'] == sha(directory / 'cases.json')
        assert result['runner_sha256'] == sha(root / 'run.mjs')
        assert result['wasm_sha256'] == provenance['compilers'][label]['wasm']
        binary = directory / label / 'main.wasm'
        if binary.exists():
            assert sha(binary) == result['wasm_sha256']
        rows = {}
        assert len(result['cases']) == len(cases)
        for case in result['cases']:
            spec = next(c for c in cases if c['name'] == case['name'])
            assert case['phases'] == spec['phases']
            for measurement in case['measurements']:
                key = (case['name'], measurement['phase'], measurement['trial'])
                assert key not in rows and key in expected
                assert 'error' not in measurement
                assert measurement['reclaimed_bytes'] == 0
                assert measurement['output_bytes'] == 2
                assert measurement['output_sha256'] == hashlib.sha256(b'ok').hexdigest()
                rows[key] = measurement
        assert set(rows) == expected
        versions.append(rows)
    gains = []
    for key, before in versions[0].items():
        after = versions[1][key]
        assert before['allocated_bytes'] == after['allocated_bytes']
        delta = before['instructions'] - after['instructions']
        if scalar:
            repetitions = int(key[0].split('-')[-1])
            affected = key[1] in ('Nat8', 'Int8', 'Nat16', 'Int16', 'Nat32', 'Int32', 'Char')
            assert delta == (42 * repetitions * 4 if affected else 0), (key, delta)
        else:
            assert delta > 0, (key, delta)
        if key[2] == 0:
            gains.append((key[:2], before['instructions'], after['instructions'], before['allocated_bytes']))
    print(('scalar' if scalar else 'map'), 'verified', len(expected) * 2,
          'paired raw measurements; allocation unchanged, no GC, every output ok')
    for row in gains:
        print(*row)

read_suite(root, True)
read_suite(root / 'map', False)
