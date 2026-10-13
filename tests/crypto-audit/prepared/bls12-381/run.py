#!/usr/bin/env python3
"""Retain independent execution evidence for one frozen prepared-BLS candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
p = argparse.ArgumentParser()
p.add_argument('--motoko', type=Path, required=True)
p.add_argument('--phase', choices=['all','native','public','ash'], default='all')
p.add_argument('--run', required=True, help='New evidence directory; existing runs are never overwritten')
p.add_argument('--ash-source', type=Path, help='Private Ash snapshot with explicit SDK compiler resolver')
p.add_argument('--ash-provenance', type=Path, help='Source-copy manifest for that private Ash snapshot')
a = p.parse_args()
M = a.motoko.resolve()
D = ROOT/'dist/bls12-381'
E = HERE/'evidence'/a.run
E.mkdir(parents=True, exist_ok=False)
W = ROOT/'_build/prepared-bls-independent'
W.mkdir(parents=True, exist_ok=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
def inputs():
    paths = list((ROOT/'plugins/bls12-381/compiler').glob('*'))
    paths += list((ROOT/'plugins/bls12-381/runtime').rglob('*'))
    paths += [ROOT/'packages/fast/src/BLS12381.mo', D/'build.json', D/'plugin.cmxs', D/'runtime.wasm',
              M/'src/moc', M/'bin/moc', M/'rts/mo-rts.wasm', M/'rts/mo-rts-debug.wasm']
    return {str(x.relative_to(ROOT)) if x.is_relative_to(ROOT) else str(x):sha(x)
            for x in paths if x.is_file() and 'target' not in x.parts}
manifest = json.loads((D/'build.json').read_text())
assert manifest['moc_sha256']==sha(M/'src/moc'), 'Compiler does not match plugin build'
for name,digest in manifest['source_sha256'].items():
    if name.startswith('plugins/bls12-381/'):
        assert sha(ROOT/name)==digest, 'Stale plugin build: '+name
before = inputs()
test_paths = [x for x in HERE.iterdir() if x.is_file() and x.suffix in ['.mo','.rs','.py','.tsv','.json','.toml']]
test_paths += list((HERE/'fail').glob('*.mo'))
test_inputs = {str(x.relative_to(ROOT)):sha(x) for x in test_paths}
ash_inputs = {}
if a.phase in ['all','ash']:
    assert a.ash_source and a.ash_provenance, 'Ash needs an explicitly pinned private source snapshot'
    provenance = json.loads(a.ash_provenance.read_text())
    assert Path(provenance['sdk_moc_override']).resolve()==(M/'bin/moc').resolve()
    for name,record in provenance['files'].items():
        path = a.ash_source/name
        assert sha(path)==record['copied_sha256'], 'Changed Ash snapshot: '+name
        ash_inputs[str(path.resolve())] = record['copied_sha256']
    (E/'ash-source-provenance.json').write_text(a.ash_provenance.read_text())
results = []
def save():
    after = inputs()
    ash_stable = all(sha(Path(path))==digest for path,digest in ash_inputs.items())
    test_stable = all(sha(ROOT/path)==digest for path,digest in test_inputs.items())
    report = dict(phase=a.phase,source_artifact_hashes=before,test_inputs_sha256=test_inputs,ash_source_hashes=ash_inputs,inputs_unchanged=before==after and ash_stable and test_stable,
                  all_passed=before==after and ash_stable and test_stable and all(r['passed'] for r in results),commands=results)
    (E/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    assert before==after and ash_stable and test_stable, 'Audited source/artifact changed during execution'
def run(name, command, negative=False, env=None):
    command = list(map(str,command))
    log = E/(name+'.log')
    start = time.monotonic()
    with log.open('w') as stream:
        r = subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,env=env)
    output = log.read_text()
    passed = r.returncode != 0 and 'error [' in output and 'Prepared' in output if negative else r.returncode==0
    row = dict(name=name,command=command,exit_code=r.returncode,expected_failure=negative,passed=passed,
               seconds=round(time.monotonic()-start,3),log=log.name,log_sha256=sha(log))
    results.append(row)
    print(json.dumps(row),flush=True)
    save()
    if not passed: raise SystemExit(r.returncode or 1)
if a.phase in ['all','native']:
    run('native-lock',['cargo','generate-lockfile','--manifest-path',HERE/'Cargo.toml','--offline'])
    run('native',['cargo','test','--manifest-path',HERE/'Cargo.toml','--locked','--offline','--release',
                  '--target-dir',W/'target','audit_','--','--nocapture'])
flags = ['--package','fast',ROOT/'packages/fast/src','--plugin',D,'--sanity-checks']
if a.phase in ['all','public']:
    for name,source in [('independent',HERE/'public.mo'),('ordinary-callbacks',ROOT/'plugins/bls12-381/tests/run/aggregate-functions.mo')]:
        run(name+'-interpreter',[M/'bin/moc',*flags,'-r',source])
        wasm=W/(name+'.wasm')
        run(name+'-compile',[M/'bin/moc',*flags,'-wasi-system-api','-c',source,'-o',wasm])
        run(name+'-validate',['wasm-validate','--enable-memory64','--enable-multi-memory',wasm])
        run(name+'-wasm',['wasmtime','run','-C','cache=n','-W','memory64','-W','multi-memory','-W','bulk-memory',wasm])
    for source in sorted((HERE/'fail').glob('*.mo')):
        run('type-negative-'+source.stem,[M/'bin/moc',*flags,'--check',source],negative=True)
if a.phase in ['all','ash']:
    # The private snapshot pins only moc; no global compiler links change.
    run('ash',['bun',a.ash_source/'src/index.ts','test',HERE/'Prepared.ash.json','--verbose'])
save()
