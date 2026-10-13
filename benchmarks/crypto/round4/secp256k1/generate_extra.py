#!/usr/bin/env python3
"""Reuse the retained direct10/cold10 workloads without changing screen inputs."""
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent
CRYPTO=HERE.parents[1]
prior=json.loads((CRYPTO/'prepared/secp256k1/cases.json').read_text())['cases']
cases=[]
for case in prior:
    if case['prepared']['reuse'] != 10 or case['prepared']['mode'] not in ['direct','cold']:
        continue
    source=CRYPTO/case['source']
    relative=Path('round4/secp256k1/cases')/case['name']/'main.mo'
    target=CRYPTO/relative; target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(source.read_bytes())
    case['source']=relative.as_posix()
    case['prepared']['fixture_source']='round4/secp256k1/fixtures.json'
    cases.append(case)
assert len(cases)==6
(HERE/'extra-cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print('Generated six existing direct10/cold10 workloads')
