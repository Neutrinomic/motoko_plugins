#!/usr/bin/env python3
"""Targeted wrapper-only re-audit after bounding repeated-message comparisons."""
from pathlib import Path
import argparse, hashlib, json, subprocess, time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
p=argparse.ArgumentParser()
p.add_argument('--snapshot',type=Path,required=True)
p.add_argument('--motoko',type=Path,required=True)
a=p.parse_args();snapshot=a.snapshot.resolve();motoko=a.motoko.resolve()
plugin=snapshot/'dist/bls12-381'
work=ROOT/'_build/crypto-audit-round2/bls';work.mkdir(parents=True,exist_ok=True)
evidence=HERE/'evidence'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
paths=[snapshot/'plugins/bls12-381/runtime/src/lib.rs',snapshot/'packages/fast/src/BLS12381.mo',
       *[plugin/x for x in ['runtime.wasm','plugin.cmxs','build.json']],
       *[motoko/x for x in ['bin/moc','src/moc','rts/mo-rts.wasm','rts/mo-rts-debug.wasm']],
       *[HERE/x for x in ['run-cache-cap.py','generate-cache-cap.py','cache-cap.mo','cache-cap-provenance.json','profiles.mo']]]
before={str(p):sha(p) for p in paths}
prior=json.loads((HERE/'evidence/prior-report.json').read_text())
assert sha(paths[0])==prior['sources']['plugins/bls12-381/runtime/src/lib.rs']
for name in ['runtime.wasm','plugin.cmxs','build.json']:
    assert sha(plugin/name)==prior['artifacts']['dist/bls12-381/'+name]
results=[]
def save():
    stable=before=={str(p):sha(p) for p in paths}
    report=dict(status='pass' if len(results)==8 and stable and all(r['exit_code']==0 for r in results) else 'incomplete-or-failed',
        snapshot=str(snapshot),runtime_and_plugin_artifacts_unchanged=True,inputs_unchanged=stable,
        public_checks_per_backend=52,results=results,sha256=before)
    (HERE/'cache-cap-report.json').write_text(json.dumps(report,indent=2)+'\n')
    if not stable:raise RuntimeError('Audited source or artifact changed during execution')
def run(name,command):
    log=evidence/(name+'.log');start=time.monotonic()
    with log.open('w') as stream:
        proc=subprocess.run([str(x) for x in command],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
    result=dict(name=name,command=[str(x) for x in command],exit_code=proc.returncode,seconds=round(time.monotonic()-start,3),log=str(log),log_sha256=sha(log))
    results.append(result);print(json.dumps(result),flush=True);save()
    if proc.returncode:raise SystemExit(proc.returncode)
flags=['--package','fast',snapshot/'packages/fast/src','--plugin',plugin,'--sanity-checks']
for name in ['cache-cap','profiles']:
    prefix='cap-'+name;src=HERE/(name+'.mo');wasm=work/(prefix+'.wasm')
    run(prefix+'-interpreter',[motoko/'bin/moc',*flags,'-r',src])
    run(prefix+'-compile',[motoko/'bin/moc',*flags,'-wasi-system-api','-c',src,'-o',wasm])
    run(prefix+'-validate',['wasm-validate','--enable-memory64','--enable-multi-memory',wasm])
    run(prefix+'-wasm',['wasmtime','run','-C','cache=n','-W','nan-canonicalization=y','-W','memory64','-W','multi-memory','-W','bulk-memory',wasm])
save()
