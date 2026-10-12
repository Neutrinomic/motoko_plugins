#!/usr/bin/env python3
"""Run independent BLS audit in the compiler Nix shell against an isolated build."""
import argparse,hashlib,json,subprocess,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
p=argparse.ArgumentParser()
p.add_argument('--motoko',type=Path,required=True)
p.add_argument('--plugin',type=Path,required=True)
p.add_argument('--tests',nargs='+',default=['primitives','profiles','msm'])
p.add_argument('--phase',choices=['all','native','interpreter','wasm'],default='all')
a=p.parse_args();moc=a.motoko.resolve()/'bin/moc';plugin=a.plugin.resolve()
logs=HERE/'logs';logs.mkdir(exist_ok=True)
results=[]
def run(name,cmd):
    start=time.monotonic()
    with (logs/(name+'.log')).open('w') as f:
        completed=subprocess.run([str(x) for x in cmd],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    item=dict(name=name,command=[str(x) for x in cmd],exit_code=completed.returncode,seconds=round(time.monotonic()-start,3),log=str(logs/(name+'.log')))
    results.append(item)
    print(json.dumps(item),flush=True)
    save()
    if completed.returncode:raise SystemExit(completed.returncode)
def save():
    sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for tree in [ROOT/'plugins/bls12-381',HERE] for p in tree.rglob('*') if p.is_file() and not any(part in ['logs','target'] for part in p.parts) and p.name != 'findings.json' and p.suffix in ['.rs','.ml','.mli','.mo','.json','.toml','.tsv','.py']}
    sources['packages/fast/src/BLS12381.mo']=hashlib.sha256((ROOT/'packages/fast/src/BLS12381.mo').read_bytes()).hexdigest()
    artifacts={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [plugin/'plugin.cmxs',plugin/'runtime.wasm',plugin/'build.json',*logs.glob('*.wasm')] if p.is_file()}
    (logs/(a.phase+'-evidence.json')).write_text(json.dumps(dict(results=results,artifacts=artifacts,source_sha256=sources),indent=2)+'\n')
if a.phase in ['all','native']:
    run('native',['cargo','test','--manifest-path',HERE/'Cargo.toml','--locked','--offline','--target-dir',ROOT/'_build/audit-bls-native','audit_','--','--nocapture'])
flags=['--package','fast',ROOT/'packages/fast/src','--plugin',plugin,'--sanity-checks']
for test in a.tests:
    src=HERE/(test+'.mo')
    if a.phase in ['all','interpreter']:
        run(test+'-interpreter',[moc,*flags,'-r',src])
    if a.phase in ['all','wasm']:
        wasm=logs/(test+'.wasm')
        run(test+'-compile',[moc,*flags,'-wasi-system-api','-c',src,'-o',wasm])
        run(test+'-validate',['wasm-validate','--enable-memory64','--enable-multi-memory',wasm])
        run(test+'-wasm',['wasmtime','run','-C','cache=n','-W','nan-canonicalization=y','-W','memory64','-W','multi-memory','-W','bulk-memory',wasm])
