#!/usr/bin/env python3
"""Assemble the exhaustive callable inventory and only its referenced cases."""
import hashlib
import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
ROOT = BENCH.parents[1]
rows = []
for name in ['inventory.json', 'sha-ripemd/inventory.json']:
    rows += json.loads((HERE/name).read_text())['api_rows']
assert len({r['id'] for r in rows}) == len(rows)
expected = {
    'SHA256': ['digest'],
    'SHA512': ['digest', 'digest384', 'Digest', 'Digest.write', 'Digest.sum', 'Digest.reset',
              'Digest384', 'Digest384.write', 'Digest384.sum', 'Digest384.reset'],
    'RIPEMD160': ['digest', 'init', 'update', 'finalize', 'Digest', 'Digest.write', 'Digest.sum', 'Digest.reset'],
    'BLAKE3': ['digest', 'keyedHash', 'deriveKey', 'xof', 'new', 'newKeyed', 'newDeriveKey', 'update', 'finalizeXof', 'finalize'],
    'HMAC': ['sha256', 'sha512'] + [f'{prefix}{suffix}{method}' for suffix in ['256', '512']
        for prefix, methods in [('SHA', ['', '.write', '.sum', '.reset']),
                                ('prepareSha', ['', '.digest', '.stream', '.stream.write', '.stream.sum', '.stream.reset'])]
        for method in methods],
    'Base58': ['encode', 'decode'], 'Base58Check': ['encode', 'decode'],
    'Bech32': ['encode', 'decode', 'convertBits'], 'Segwit': ['encode', 'decode'],
}
found = defaultdict(set)
for row in rows:
    found[row['module']].add(row['function'])
assert dict(found) == {k: set(v) for k, v in expected.items()}
available = {}
for path in [BENCH/'all-cases.json', BENCH/'round2/bech32-workloads/cases.json',
             HERE/'cases.json', HERE/'sha-ripemd/cases.json']:
    manifest = json.loads(path.read_text())
    for case in manifest['cases'] if isinstance(manifest, dict) else manifest:
        key = case['name'], case['implementation']
        if key in available:
            assert available[key] == case, ('Conflicting fixture', key)
        available[key] = case
selected = {}
for row in rows:
    row['public_function'] = row['module']+'.'+row['function']
    row['source_module'] = 'packages/fast/src/'+row['module']+'.mo'
    pair = []
    for field in ['plugin_case', 'native_case']:
        reference = row.get(field)
        if reference is None:
            continue
        key = reference['name'], reference['implementation']
        case = available[key]
        assert bool(case['plugins']) == (field == 'plugin_case'), (row['id'], field)
        source = BENCH/case['source']
        assert source.is_file()
        reference['source'] = case['source']
        reference['source_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
        pair.append(case['expected_hex'])
        selected[key] = case
    assert len(set(pair)) == 1, ('Mismatched exact outputs', row['id'])
result = {
    'api_rows': sorted(rows, key=lambda r: r['id']),
    'callable_count': sum(len(v) for v in expected.values()),
    'workload_rows': len(rows), 'case_count': len(selected),
    'module_source_sha256': {module: hashlib.sha256((ROOT/'_build/crypto-optimization-round2/baseline/packages/fast/src'/(module+'.mo')).read_bytes()).hexdigest() for module in expected},
    'missing_native_counterpart_rows': sum(r.get('native_case') is None for r in rows),
    'notes': 'Native means pure Motoko; internal implementation label native means plugin-backed. Preserve this distinction when rendering table headings. Missing counterpart cells remain empty, with explanatory row notes.',
}
(HERE/'api-inventory.json').write_text(json.dumps(result, indent=2)+'\n')
(HERE/'suite-cases.json').write_text(json.dumps({'cases': [selected[k] for k in sorted(selected)]}, indent=2)+'\n')
print(f'{result["callable_count"]} callables, {len(rows)} workload rows, {len(selected)} implementation/workload cases, {result["missing_native_counterpart_rows"]} absent native cells')
