#!/usr/bin/env python3
"""Audit source + actual linked Wasm against frozen build, retaining exact evidence."""
import argparse,hashlib,json,subprocess,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
p=argparse.ArgumentParser();p.add_argument('--motoko',type=Path,required=True);p.add_argument('--phase',choices=['all','native','interpreter','wasm'],default='all');p.add_argument('--only',choices=['cache-cap','first-class']);a=p.parse_args()
M=a.motoko.resolve();D=ROOT/'dist/bls12-381';E=HERE/'evidence';E.mkdir(exist_ok=True);W=ROOT/'_build/round3-bls-independent';W.mkdir(parents=True,exist_ok=True)
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
def inputs():
    paths=list((ROOT/'plugins/bls12-381').rglob('*.rs'))+list((ROOT/'plugins/bls12-381/compiler').glob('*'))
    paths += [ROOT/'packages/fast/src/BLS12381.mo',D/'plugin.cmxs',D/'runtime.wasm',D/'build.json',M/'src/moc']
    return {str(x.relative_to(ROOT)) if x.is_relative_to(ROOT) else str(x):sha(x) for x in paths if x.is_file()}
manifest=json.loads((D/'build.json').read_text())
selected={name:digest for name,digest in manifest['source_sha256'].items() if name.startswith('plugins/bls12-381/')}
for name,digest in selected.items():
    if sha(ROOT/name)!=digest: raise RuntimeError('stale build source: '+name)
before=inputs();results=[]
def save():
    after=inputs();stable=before==after
    (E/(a.phase+('-'+a.only if a.only else '')+'-report.json')).write_text(json.dumps(dict(phase=a.phase,build_manifest_sources_verified=len(selected),inputs=before,inputs_unchanged=stable,all_passed=stable and all(r['exit_code']==0 for r in results),commands=results),indent=2)+'\n')
    if not stable: raise RuntimeError('audited source/artifact changed during execution')
def run(name,cmd):
    log=E/(name+'.log');start=time.monotonic()
    with log.open('w') as stream:r=subprocess.run([str(x) for x in cmd],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
    row=dict(name=name,command=[str(x) for x in cmd],exit_code=r.returncode,seconds=round(time.monotonic()-start,3),log=log.name,log_sha256=sha(log));results.append(row);print(json.dumps(row),flush=True);save()
    if r.returncode:raise SystemExit(r.returncode)
if a.phase in ['all','native'] and not a.only:
    run('native',['cargo','test','--manifest-path',HERE/'Cargo.toml','--locked','--offline','--release','--target-dir',W/'target','audit_','--','--nocapture'])
flags=['--package','fast',ROOT/'packages/fast/src','--plugin',D,'--sanity-checks']
tests=[('independent-public',HERE/'public.mo'),('aggregate-boundaries',ROOT/'plugins/bls12-381/tests/run/aggregate-boundaries.mo'),('retained-round2',ROOT/'packages/fast/tests/run/crypto-bls-round2.mo'),('cache-cap',ROOT/'tests/crypto-audit/round2/bls/cache-cap.mo'),('first-class',ROOT/'plugins/bls12-381/tests/run/aggregate-functions.mo')]
if a.only: tests=[(name,source) for name,source in tests if name==a.only]
for name,source in tests:
    if a.phase in ['all','interpreter']:run(name+'-interpreter',[M/'bin/moc',*flags,'-r',source])
    if a.phase in ['all','wasm']:
        wasm=W/(name+'.wasm');run(name+'-compile',[M/'bin/moc',*flags,'-wasi-system-api','-c',source,'-o',wasm]);run(name+'-validate',['wasm-validate','--enable-memory64','--enable-multi-memory',wasm]);run(name+'-wasm',['wasmtime','run','-C','cache=n','-W','nan-canonicalization=y','-W','memory64','-W','multi-memory','-W','bulk-memory',wasm])
save()
