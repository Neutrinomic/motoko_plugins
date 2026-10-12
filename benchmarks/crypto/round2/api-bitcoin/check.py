#!/usr/bin/env python3
"""Local compilation guard; shared runner owns immutable measured stages."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
BENCH=HERE.parents[1]
ROOT=BENCH.parents[1]
BASE=ROOT/'_build/crypto-optimization-round2/baseline'
TOOL=Path('/home/devbox/.local/lib/motoko-compute')
LOCK=json.loads((BENCH/'dependencies/mops.lock').read_text())
ARGS=[]
for alias,version in LOCK['deps'].items():
    ARGS.extend(['--package',alias,str(BENCH/'dependencies/.mops'/(alias.split('@')[0]+'@'+version)/'src')])
ARGS.extend(['--package','fast',str(BASE/'packages/fast/src')])
CASES=json.loads((HERE/'cases.json').read_text())['cases']

def check(case):
    out=HERE/'check'/case['name']/case['implementation']
    out.mkdir(parents=True,exist_ok=True)
    command=[str(TOOL/'moc'),*ARGS]
    for plugin in case['plugins']:
        command.extend(['--plugin',str(BASE/'dist'/plugin)])
    command.extend([str(BENCH/case['source']),'-o',str(out/'main.wasm')])
    env=dict(os.environ,MOC_RELEASE_RTS=str(TOOL/'mo-rts.wasm'),MOC_DEBUG_RTS=str(TOOL/'mo-rts-debug.wasm'))
    p=subprocess.run(command,capture_output=True,text=True,env=env)
    (out/'compile.log').write_text(p.stdout+p.stderr)
    return dict(name=case['name'],implementation=case['implementation'],returncode=p.returncode,log=str((out/'compile.log').relative_to(HERE)))

with ThreadPoolExecutor(max_workers=2) as pool:
    results=list(pool.map(check,CASES))
(HERE/'check.json').write_text(json.dumps(results,indent=2)+'\n')
for row in results:
    if row['returncode']:
        print(row['name'],row['implementation'],(HERE/row['log']).read_text()[-3000:])
print(f'{sum(row["returncode"]==0 for row in results)}/{len(results)} compiled')
raise SystemExit(any(row['returncode'] for row in results))
