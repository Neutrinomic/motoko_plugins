#!/usr/bin/env python3
"""Compare complete Wasm sections and unmodified WAT; fail on executable changes."""
from pathlib import Path
import difflib
import hashlib
import json
import shutil
import subprocess

ROOT = Path('/srv/shared/code/motoko_experiments/plugins')
REPORT = ROOT / 'benchmarks/results/optimization-round-2/integrated'
SCRATCH = ROOT / '_build/opt2-integrated'
OLD_VERSION = b'2.0.0-10-gc320bf90d'
NEW_VERSION = b'2.0.0-11-g128a41c06'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def leb(data, pos):
    result = shift = 0
    while True:
        byte = data[pos]
        pos += 1
        result |= (byte & 127) << shift
        if byte < 128:
            return result, pos
        shift += 7
        assert shift < 35


def sections(data):
    assert data[:8] == b'\0asm\1\0\0\0'
    result = []
    pos = 8
    while pos < len(data):
        start = pos
        kind = data[pos]
        length, pos = leb(data, pos + 1)
        end = pos + length
        assert end <= len(data)
        name = None
        if kind == 0:
            n, q = leb(data, pos)
            name = data[q:q + n].decode()
        result.append((kind, name, data[start:end], data[pos:end]))
        pos = end
    return result


def bodies(payload):
    count, pos = leb(payload, 0)
    result = []
    for _ in range(count):
        length, pos = leb(payload, pos)
        result.append(payload[pos:pos + length])
        pos += length
    assert pos == len(payload)
    return result


disassembler = shutil.which('wasm2wat')
assert disassembler
build = json.loads((REPORT / 'build.json').read_text())
actors = json.loads((REPORT / 'actors.json').read_text())
proof = {
    'no_new_performance_trials': True,
    'historical_compiler_revision': 'c320bf90d0b63a058b5de2c41a42c96e8b82243f',
    'integrated_compiler_revision': build['compiler_revision'],
    'historical_version': OLD_VERSION.decode(), 'integrated_version': NEW_VERSION.decode(),
    'disassembler': {'path': disassembler,
                     'version': subprocess.check_output([disassembler, '--version'], text=True).strip(),
                     'sha256': sha(Path(disassembler).read_bytes()), 'flags': ['--enable-all']},
    'actors': {},
}
assert len(OLD_VERSION) == len(NEW_VERSION)
for name, actor in actors.items():
    scratch = SCRATCH / name
    report = REPORT / name
    report.mkdir(exist_ok=True)
    old_path = Path(actor['wasm'])
    new_path = scratch / 'main.wasm'
    old, new = old_path.read_bytes(), new_path.read_bytes()
    inputs = build['actors'][name]
    assert sha(old) == inputs['historical_wasm_sha256']
    assert sha(new) == inputs['integrated_wasm_sha256']
    texts = []
    for label, path in [('c320', old_path), ('128a', new_path)]:
        wat = scratch / (label + '.wat')
        subprocess.run([disassembler, '--enable-all', str(path), '-o', str(wat)], check=True)
        texts.append(wat.read_text().splitlines(keepends=True))
    before, after = texts
    diff = ''.join(difflib.unified_diff(before, after, fromfile='c320.wat', tofile='128a.wat', n=2))
    (report / 'raw-wat.diff').write_text(diff)
    old_sections, new_sections = sections(old), sections(new)
    assert [(s[0], s[1]) for s in old_sections] == [(s[0], s[1]) for s in new_sections]
    rows = []
    for a, b in zip(old_sections, new_sections):
        row = {'id': a[0], 'name': a[1], 'equal': a[2] == b[2],
               'before_sha256': sha(a[2]), 'after_sha256': sha(b[2]),
               'before_bytes': len(a[2]), 'after_bytes': len(b[2])}
        rows.append(row)
        if a[0] == 10:
            old_bodies, new_bodies = bodies(a[3]), bodies(b[3])
    changed_bodies = [i for i, (a, b) in enumerate(zip(old_bodies, new_bodies)) if a != b]
    record = {
        **inputs, 'before_bytes': len(old), 'after_bytes': len(new),
        'before_wat_sha256': sha(''.join(before).encode()),
        'after_wat_sha256': sha(''.join(after).encode()),
        'raw_wat_diff_sha256': sha(diff.encode()),
        'function_body_count': len(old_bodies), 'changed_function_body_indices': changed_bodies,
        'all_code_bytes_identical': old_bodies == new_bodies,
        'whole_binary_reconstructed_by_version_substitution': old.replace(OLD_VERSION, NEW_VERSION) == new,
        'sections': rows,
    }
    proof['actors'][name] = record
    # Write diagnostics before assertions so unexpected changes remain reviewable.
    (REPORT / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
    assert len(old_bodies) == len(new_bodies) and not changed_bodies, (name, changed_bodies)
    assert old.count(OLD_VERSION) == 2 and old.replace(OLD_VERSION, NEW_VERSION) == new, name
    for a, b in zip(old_sections, new_sections):
        if a[2] != b[2]:
            assert a[0] == 11 or a[1] == 'icp:private motoko:compiler', (name, a[:2])
            assert a[3].count(OLD_VERSION) == 1
            assert a[3].replace(OLD_VERSION, NEW_VERSION) == b[3], (name, a[:2])
    assert ''.join(before).replace(OLD_VERSION.decode(), NEW_VERSION.decode()) == ''.join(after), name
    assert len([r for r in rows if not r['equal']]) == 2
    print(name, len(old_bodies), 'function bodies byte-identical; only version data/custom section changed')

proof['conclusion'] = ('All six actors have byte-identical complete code sections and every function body, '
                       'including static initializers. Every other section is identical except the one '
                       'same-length compiler-version string in the data and compiler custom sections. '
                       'Existing c320 measurements remain historical measurements; no trials were rerun.')
(REPORT / 'proof.json').write_text(json.dumps(proof, indent=2) + '\n')
