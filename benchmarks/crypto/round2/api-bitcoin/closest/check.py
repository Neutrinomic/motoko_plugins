#!/usr/bin/env python3
"""Compile only the two additional closest-code peer actors."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
BENCH=HERE.parents[2]
TOOL=Path('/home/devbox/.local/lib/motoko-compute')
args=[]
for alias,version in json.loads((BENCH/'dependencies/mops.lock').read_text())['deps'].items():
    args+=['--package',alias,str(BENCH/'dependencies/.mops'/(alias.split('@')[0]+'@'+version)/'src')]
results=[]
for case in json.loads((HERE/'cases.json').read_text())['cases']:
    source=BENCH/case['source']
    target=HERE/'check'/case['name']
    target.mkdir(parents=True,exist_ok=True)
    p=subprocess.run([str(TOOL/'moc'),*args,str(source),'-o',str(target/'main.wasm')],text=True,capture_output=True,
       env=dict(os.environ,MOC_RELEASE_RTS=str(TOOL/'mo-rts.wasm'),MOC_DEBUG_RTS=str(TOOL/'mo-rts-debug.wasm')))
    (target/'compile.log').write_text(p.stdout+p.stderr)
    results.append(dict(name=case['name'],returncode=p.returncode,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
    print(case['name'],p.returncode)
    if p.returncode:print(p.stdout+p.stderr)
(HERE/'check.json').write_text(json.dumps(results,indent=2)+'\n')
raise SystemExit(any(r['returncode'] for r in results))
