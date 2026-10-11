#!/usr/bin/env python3
"""Verify the portable mutable-map audit evidence without rerunning Motoko."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'audit-manifest.json').read_text())
for name, digest in manifest['files'].items():
    path = Path(name)
    assert not path.is_absolute() and '..' not in path.parts, name
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == digest, name
provenance = json.loads((root / 'candidate-provenance.json').read_text())
assert provenance['compiler_revision'] == 'abfba892fe4bd8fa2bc88e25dca0b895d35c1962'
assert provenance['compiler_sha256'] == 'a5a68803ecc8d48509c77052889f05eb8b5e3e983ee55b2027e9689939d79498'
for name, digest in provenance['source_sha256'].items():
    assert hashlib.sha256((root / 'sources' / name).read_bytes()).hexdigest() == digest, name

expected = {
    'callback-state': 'audit: callback-visible tree and size remained valid across split/borrow/merge/root collapse\n',
    'helper-instantiations': 'audit: generic helper sharing, nested options, key/payload aliases, closures and scalar extremes passed\n',
    'randomized-core': 'audit: 7200 seeded operations and inclusive seeks matched core mutable Map\n',
}
for name, output in expected.items():
    for stage in ('tc', 'comp', 'valid', 'diff-ir', 'diff-low'):
        assert (root / 'outputs/run' / f'{name}.{stage}').read_bytes() == b'', (name, stage)
    for stage in ('run', 'run-ir', 'run-low', 'wasm-run'):
        actual = root / 'outputs/run' / f'{name}.{stage}'
        assert actual.read_text() == output, (name, stage)
        assert actual.read_bytes() == (root / 'run/ok' / f'{name}.{stage}.ok').read_bytes()

expected_drun = {
    'mutable-map-gc': [
        'mutable-map aliases, shared payloads and callbacks survived incremental GC',
        'mutable-map point allocation is independent of payload size',
    ],
    'mutable-map-upgrade': ['mutable-map upgrade preserved aliases, cloned nodes and shared payloads'] * 2,
    'mutable-map-traversal-allocation': ['mutable-map find traverses without per-entry tuple garbage'],
}
for name, messages in expected_drun.items():
    for stage in ('tc', 'comp', 'valid'):
        assert (root / 'outputs/run-drun' / f'{name}.{stage}').read_bytes() == b'', (name, stage)
    output = (root / 'outputs/run-drun' / f'{name}.drun-run').read_text()
    assert output.encode() == (root / 'run-drun/ok' / f'{name}.drun-run.ok').read_bytes()
    assert [line.removeprefix('debug.print: ') for line in output.splitlines()
            if line.startswith('debug.print: ')] == messages, name
    assert all(line.startswith(('ingress Completed: Reply: ', 'debug.print: '))
               for line in output.splitlines()), name
assert not list((root / 'outputs').rglob('*.ret'))
for name, count in [('final-callback-tests.log', 1), ('final-generic-tests.log', 2), ('gc-upgrade-tests.log', 3)]:
    assert f'{count} tests ran successfully.' in (root / name).read_text(), name
print('Verified 3 audit programs in 4 engines, 3 IC fixtures, frozen sources and archived output hashes')
