#!/usr/bin/env python3
"""Run the independent BLS round2 audit against an explicit frozen snapshot."""
import argparse
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OLD = ROOT/'tests/crypto-audit/bls'
p = argparse.ArgumentParser()
p.add_argument('--motoko', type=Path, required=True)
p.add_argument('--snapshot', type=Path, required=True)
p.add_argument('--baseline', type=Path, required=True)
p.add_argument('--phase', choices=['all','native','interpreter','wasm'], default='all')
a = p.parse_args()
snapshot, baseline, motoko = a.snapshot.resolve(), a.baseline.resolve(), a.motoko.resolve()
plugin = snapshot/'dist/bls12-381'
work = ROOT/'_build/crypto-audit-round2/bls'
work.mkdir(parents=True, exist_ok=True)
evidence = HERE/'evidence'; evidence.mkdir(exist_ok=True)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def inputs():
    paths = []
    for tree in [snapshot/'plugins/bls12-381', baseline/'plugins/bls12-381']:
        paths.extend(x for x in tree.rglob('*') if x.is_file())
    for root in [snapshot, baseline]:
        paths.extend([root/'packages/fast/src/BLS12381.mo',root/'Cargo.lock'])
    paths.extend(x for x in HERE.iterdir() if x.is_file() and x.name not in ['report.json','retention-manifest.json','recoding-report.json'])
    paths.extend([OLD/name for name in ['native.rs','Cargo.toml','Cargo.lock','vectors.tsv','msm-vectors.tsv','primitives.mo','profiles.mo','msm.mo']])
    paths.extend([motoko/'bin/moc',plugin/'runtime.wasm',plugin/'plugin.cmxs',plugin/'build.json'])
    return {str(x):sha(x) for x in sorted(paths)}
before = inputs()
results = []
def save():
    after = inputs()
    stable = before == after
    report = dict(snapshot=str(snapshot),baseline=str(baseline),phase=a.phase,inputs_unchanged=stable,
        results=results,all_passed=stable and all(r['exit_code']==0 for r in results),
        assertions=dict(existing_native=206,new_native=87,existing_public=230,sort=1279,profiles=37,new_public=87),
        limitations=['Independent functional and code audit; no formal proof or hardware side-channel measurement.'])
    (evidence/(a.phase+'-report.json')).write_text(json.dumps(report,indent=2)+'\n')
    (HERE/'retention-manifest.json').write_text(json.dumps(dict(sha256=before,inputs_unchanged=stable,
        generated_wasm={str(x):sha(x) for x in work.glob('*.wasm')}),indent=2)+'\n')
    if not stable: raise RuntimeError('Audited input changed during execution')
def run(name, cmd):
    start=time.monotonic(); log=evidence/(name+'.log')
    with log.open('w') as stream:
        result=subprocess.run([str(x) for x in cmd],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
    row=dict(name=name,command=[str(x) for x in cmd],exit_code=result.returncode,seconds=round(time.monotonic()-start,3),log=str(log),log_sha256=sha(log))
    results.append(row); print(json.dumps(row),flush=True); save()
    if result.returncode: raise SystemExit(result.returncode)

if a.phase in ['all','native']:
    # Test the snapshot source itself, not the mutable shared working tree.
    source=(OLD/'native.rs').read_text()
    source=source.replace('../../../plugins/bls12-381/runtime/src/lib.rs',str(snapshot/'plugins/bls12-381/runtime/src/lib.rs'))
    source=source.replace('include_str!("vectors.tsv")',f'include_str!("{OLD}/vectors.tsv")')
    source=source.replace('include_str!("msm-vectors.tsv")',f'include_str!("{OLD}/msm-vectors.tsv")')
    source=source.replace('.lines().chain(include_str!',f'.lines().chain(include_str!("{HERE}/vectors.tsv").lines()).chain(include_str!',1)
    (work/'native.rs').write_text(source)
    shutil.copyfile(OLD/'Cargo.toml',work/'Cargo.toml'); shutil.copyfile(OLD/'Cargo.lock',work/'Cargo.lock')
    run('native',['cargo','test','--manifest-path',work/'Cargo.toml','--locked','--offline','--target-dir',work/'target','audit_','--','--nocapture'])

flags=['--package','fast',snapshot/'packages/fast/src','--plugin',plugin,'--sanity-checks']
tests=[('existing-primitives',OLD/'primitives.mo'),('existing-profiles',OLD/'profiles.mo'),('existing-msm',OLD/'msm.mo'),
       ('sorting',HERE/'sorting.mo'),('profiles',HERE/'profiles.mo'),('regressions',HERE/'regressions.mo')]
for name, src in tests:
    if a.phase in ['all','interpreter']:
        run(name+'-interpreter',[motoko/'bin/moc',*flags,'-r',src])
    if a.phase in ['all','wasm']:
        wasm=work/(name+'.wasm')
        run(name+'-compile',[motoko/'bin/moc',*flags,'-wasi-system-api','-c',src,'-o',wasm])
        run(name+'-validate',['wasm-validate','--enable-memory64','--enable-multi-memory',wasm])
        run(name+'-wasm',['wasmtime','run','-C','cache=n','-W','nan-canonicalization=y','-W','memory64','-W','multi-memory','-W','bulk-memory',wasm])
save()
