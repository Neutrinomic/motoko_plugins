#!/usr/bin/env python3
"""Reproduce bounded emitted-code checks; complements the manual data-flow review."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EXPECTED = 'b4b1f17afd54c3928bf037da4f1ddea0f3bc44d7e5bcde19f61c22e32ad0f378'
sha = lambda value: hashlib.sha256(value).hexdigest()
runtime = ROOT / 'dist/p256/runtime.wasm'
assert sha(runtime.read_bytes()) == EXPECTED
wat = subprocess.check_output(['wasm2wat', '--enable-all', str(runtime)], text=True)
funcs = {m[1]: m[0] for m in re.finditer(r'^  \(func (\S+).*?(?=^  \(|\Z)', wat, re.M | re.S)}

def select(fragment):
    result = [(n, b) for n, b in funcs.items() if fragment in n]
    assert len(result) == 1, (fragment, len(result))
    return result[0]

def branches(body):
    return [{'line': i + 1, 'instruction': line.strip()}
            for i, line in enumerate(body.splitlines())
            if re.match(r'^\s*(?:if|br_if|br_table)(?:\s|$)', line)]

fragments = {'generator-comb': '14generator_comb', 'projective-check': '27projective_x_matches_scalar',
             'sign-prehash': '$p256_sign_prehash', 'scalar-sqn': 'Scalar3sqn',
             'scalar-multiply': 'Scalar8multiply', 'scalar-reduce': '14barrett_reduce',
             'double': 'E6doubleCs', 'add-mixed': 'E9add_mixedCs',
             'word-multiply': '$__multi3'}
report = {'runtimeSha256': EXPECTED, 'runtimeBytes': runtime.stat().st_size,
          'wasm2watVersion': subprocess.check_output(['wasm2wat', '--version'], text=True).strip(),
          'limitation': 'Structural checks plus manual changed-code data-flow review; not a formal proof of whole-program constant time.',
          'functions': {}}
for label, fragment in fragments.items():
    name, body = select(fragment)
    encoded = body.encode()
    artifact = HERE / (label + '.wat.gz')
    artifact.write_bytes(gzip.compress(encoded, mtime=0))
    report['functions'][label] = {'name': name, 'lines': len(body.splitlines()),
        'watSha256': sha(encoded), 'snapshot': artifact.name,
        'snapshotSha256': sha(artifact.read_bytes()), 'branches': branches(body),
        'calls': sorted(set(re.findall(r'^\s*call (\S+)', body, re.M)))}

comb = select(fragments['generator-comb'])[1]
assert len(branches(comb)) == 3
# Each condition was manually traced to these fixed induction updates.
for pattern in [r'local.get 12\s+i64.const 72\s+i64.add\s+local.tee 12\s+i64.eqz\s+i32.eqz\s+br_if 0',
                r'local.get 17\s+i64.const 1152\s+i64.add\s+local.tee 17\s+i64.const 4608\s+i64.ne\s+br_if 0',
                r'local.get 13\s+i64.const 0\s+i64.ne\s+br_if 0']:
    assert re.search(pattern, comb), pattern
report['combReview'] = {'scanEntries': 15, 'tables': 4, 'rows': 16,
    'completeMixedAdds': 64, 'doublings': 16,
    'manualDataFlow': 'Secret digit local19 selects only via equality masks over all15 entries. Load addresses depend on public row/chunk/scan counters; no secret index or skipped zero digit. All32 scalar-byte stack slots are wiped.'}
sqn_name, sqn = select(fragments['scalar-sqn'])
assert len(branches(sqn)) == 1
assert re.search(r'local.get 2\s+i64.const -1\s+i64.add\s+local.tee 2\s+i64.eqz\s+i32.eqz\s+br_if 0', sqn)
calls = []
for name, body in funcs.items():
    lines = body.splitlines()
    for i, line in enumerate(lines):
        if line.strip() == 'call ' + sqn_name:
            count = re.fullmatch(r'\s*i64.const (\d+)', lines[i-1])
            assert count is not None and int(count[1]) > 0
            calls.append({'caller': name, 'line': i+1, 'constantCount': int(count[1])})
assert len(calls) == 31
report['scalarSquareLoopCalls'] = calls
for label in ['scalar-multiply', 'scalar-reduce', 'double', 'add-mixed', 'word-multiply']:
    assert not report['functions'][label]['branches'], label
point = select(fragments['projective-check'])[1]
assert not re.search(r'^\s*call .*?(?:invert|affine)', point, re.M)
report['projectiveReview'] = 'Public verification only. Homogeneous X/Z convention; reject Z=0, check X=rZ then checked r+n with canonical field conversion. No affine conversion/inversion remains in helper.'
report['secretScope'] = 'Changed generator selection and inversion schedule preserve fixed scalar-data control. Existing RFC6979 retry, input validity and impossible/rare signature-result rejection paths remain; no blanket branch-free claim for signing.'
report['checkerSha256'] = sha(Path(__file__).read_bytes())
(HERE / 'wasm-review.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'functionsReviewed': len(fragments), 'fixedSquareLoopCalls': len(calls), 'runtimeSha256': EXPECTED}))
