#!/usr/bin/env python3
"""Validate an explicit result selection and produce complete numeric tables."""
import argparse,csv,hashlib,json,statistics
from pathlib import Path
HERE=Path(__file__).resolve().parent
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--selection',type=Path,default=HERE/'selected-results.json')
p.add_argument('--manifest',type=Path,default=HERE/'all-cases.json')
p.add_argument('--out',type=Path,default=HERE/'summary')
p.add_argument('--allow-incomplete',action='store_true')
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
selection=json.loads(a.selection.read_text());manifest=json.loads(a.manifest.read_text());specs=manifest['cases'] if isinstance(manifest,dict) else manifest
selected={};provenance=[];toolchain_identity=None
for stage in selection['stages']:
    path=HERE/'results'/stage/'results.json'
    if not path.exists():
        if a.allow_incomplete:continue
        raise AssertionError('Missing result '+str(path))
    result=json.loads(path.read_text())
    assert result.get('complete',True),f'Incomplete run: {stage}'
    assert 'fatal_error' not in result, (stage,result.get('fatal_error'))
    assert result['trials']>=3 and isinstance(result['trials'],int)
    build_path=path.with_name('build.json');build=json.loads(build_path.read_text())
    assert hashlib.sha256(build_path.read_bytes()).hexdigest()==result['build_sha256'],f'Build changed: {stage}'
    assert not ('complete' in build and not build['complete']),f'Incomplete build: {stage}'
    inputs=build['inputs_sha256']
    identity={kind:next(value for name,value in inputs.items() if Path(name).name==filename) for kind,filename in [('release_rts','mo-rts.wasm'),('debug_rts','mo-rts-debug.wasm')]}
    identity['moc']=build.get('compiler_sha256') or inputs[build['cases'][0]['command'][0]]
    identity['pocket_ic']=result['pocket_ic_sha256']
    if toolchain_identity is None:toolchain_identity=identity
    assert identity==toolchain_identity,f'Toolchain mismatch across selected stages: {stage}'
    provenance.append({'stage':stage,'results_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'build_sha256':result['build_sha256'],'pocket_ic_sha256':result['pocket_ic_sha256']})
    for case in result['cases']:
        selected[(case['name'],case['implementation'])]=(stage,case,result['trials'])
rows=[];problems=[]
expected_failures={(x['name'],x['implementation']):x['reason'] for x in selection.get('expected_failures',[])}
for spec in specs:
    key=(spec['name'],spec['implementation']);entry=selected.get(key)
    row={k:spec.get(k,'') for k in ['name','family','implementation','comparison','notes']}
    row['expected_hex']=spec['expected_hex']
    row['native']=bool(spec.get('plugins'))
    row['comparison_key']=spec.get('comparison',spec['name']) if spec['implementation'] in ['fast','ecdsa','bitcoin','bls12-381'] else spec['name']
    if not entry:
        row.update(status='missing',stage='');problems.append(f'Missing {key}')
    else:
        stage,case,trials=entry;measurements=case['measurements'];row.update(stage=stage,wasm_bytes=case.get('wasm_bytes',''),wasm_sha256=case.get('wasm_sha256',''))
        assert case['expected_hex']==spec['expected_hex'],f'Superseded fixture selected: {key}'
        if not a.allow_incomplete:
            assert case['source_sha256']==hashlib.sha256((HERE/spec['source']).read_bytes()).hexdigest(),f'Stale benchmark source selected: {key}'
        full_trials=len(measurements)==trials and {m['trial'] for m in measurements}==set(range(trials))
        valid=full_trials and all(m.get('correct') is True for m in measurements)
        if valid:
            row['status']='passed';row['trials']=trials
            for metric in ['instructions','allocated_bytes','reclaimed_bytes']:
                values=[int(m[metric]) for m in measurements]
                row[metric+'_median']=statistics.median(values)
                row[metric+'_min']=min(values);row[metric+'_max']=max(values)
            assert len({m['output_sha256'] for m in measurements})==1
            row['output_sha256']=measurements[0]['output_sha256']
        else:
            expected_failure=key in expected_failures and full_trials and case['returncode']==0 and all('independent oracle mismatch' in m.get('error','') for m in measurements)
            row['status']='expected-baseline-failure' if expected_failure else 'failed'
            row['failure_reason']=expected_failures.get(key,'; '.join(str(m.get('error','incomplete')) for m in measurements))
            if not expected_failure:problems.append(f'Failed {key} in {stage}')
    rows.append(row)
# Comparisons never synthesize data from failures or unrelated workload names.
comparisons=[]
for native in rows:
    if not native['native'] or native['status']!='passed':continue
    for baseline in rows:
        if baseline['comparison_key']!=native['comparison_key'] or baseline['native'] or baseline['status']!='passed':continue
        assert native['expected_hex']==baseline['expected_hex']
        comparisons.append(dict(name=native['name'],native=native['implementation'],baseline=baseline['implementation'],native_stage=native['stage'],baseline_stage=baseline['stage'],native_instructions=native['instructions_median'],baseline_instructions=baseline['instructions_median'],instruction_ratio=baseline['instructions_median']/native['instructions_median'],native_allocated_bytes=native['allocated_bytes_median'],baseline_allocated_bytes=baseline['allocated_bytes_median'],native_wasm_bytes=native['wasm_bytes'],baseline_wasm_bytes=baseline['wasm_bytes'],notes=native['notes']))
def write_csv(path,records):
    fields=list(dict.fromkeys(k for row in records for k in row))
    with path.open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=fields);writer.writeheader();writer.writerows(records)
write_csv(a.out/'measurements.csv',rows);write_csv(a.out/'comparisons.csv',comparisons)
report={'toolchain_sha256':toolchain_identity,'selected_results':provenance,'cases':len(rows),'passed':sum(r['status']=='passed' for r in rows),'expected_baseline_failures':sum(r['status']=='expected-baseline-failure' for r in rows),'problems':problems,'comparisons':comparisons,'measurements':rows}
(a.out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
print(f"{report['passed']}/{report['cases']} passed; {report['expected_baseline_failures']} expected baseline failures; {len(problems)} unresolved")
if problems and not a.allow_incomplete:raise SystemExit('\n'.join(problems))
