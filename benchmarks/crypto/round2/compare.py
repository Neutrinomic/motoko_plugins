#!/usr/bin/env python3
"""Strict paired round-two comparison. Reject incomplete or semantically unequal runs."""
import argparse, hashlib, json, re, statistics
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def write_comparison(path,result):
    data=(json.dumps(result,indent=2)+'\n').encode()
    if path.exists() and path.read_bytes()!=data:
        retained=HERE/'source-versions'/(path.stem+'-'+sha(path)+'.json')
        retained.parent.mkdir(exist_ok=True);retained.write_bytes(path.read_bytes())
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)

def read_stage(name):
    directory=BENCH/'results'/name
    result=json.loads((directory/'results.json').read_text())
    build=json.loads((directory/'build.json').read_text())
    assert result['build_sha256']==sha(directory/'build.json'), 'Build metadata changed'
    assert result['complete'] and build['complete'], 'Incomplete stage'
    assert result['expected_case_count']==len(result['cases'])==len(build['cases'])==build['expected_case_count'], 'Incomplete cohort'
    assert isinstance(result['trials'],int) and result['trials']>=3
    assert result['failed_measurements']==0, 'Failed measurements'
    identity={'moc':build['compiler_sha256'],'pocket_ic':result['pocket_ic_sha256'],'runner':result['runner_sha256']}
    for key,value in build['rts_environment'].items():
        identity[key]=sha(directory/'inputs/toolchain'/Path(value).name)
    cases={}
    builds={(c['name'],c['implementation']):c for c in build['cases']}
    assert len(builds)==len(build['cases']), 'Duplicate build case'
    for case in result['cases']:
        key=(case['name'],case['implementation'])
        assert key not in cases, 'Duplicate result case'
        compiled=builds[key]
        assert case['returncode']==compiled['returncode']==0
        for field in ['expected_hex','source_sha256','wasm_sha256','wasm_bytes']:
            assert case[field]==compiled[field], 'Build/result mismatch: '+field
        assert sha(directory/compiled['wasm'])==compiled['wasm_sha256'], 'Wasm changed'
        frozen_source=directory/'inputs/benchmarks/crypto'/case['source']
        assert sha(frozen_source)==case['source_sha256'], 'Frozen fixture changed'
        measurements=case['measurements']
        assert len(measurements)==result['trials']
        assert sorted(m['trial'] for m in measurements)==list(range(result['trials'])), 'Invalid trial indices'
        oracle=hashlib.sha256(bytes.fromhex(case['expected_hex'])).hexdigest()
        assert all(m['correct'] and m['output_sha256']==oracle for m in measurements), 'Oracle mismatch'
        cases[key]=case
    return directory,result,build,identity,cases

def compare(baseline_name,candidate_name,family='.'):
    baseline_names=[baseline_name] if isinstance(baseline_name,str) else baseline_name
    assert baseline_names
    before={};before_identity=None;baseline_builds={};baseline_results={}
    for name in baseline_names:
        directory,result,build,identity,cases=read_stage(name)
        if before_identity is None:before_identity=identity
        assert before_identity==identity, 'Baseline toolchains differ'
        for key,value in cases.items():
            if key in before:
                assert before[key]['source_sha256']==value['source_sha256'] and before[key]['expected_hex']==value['expected_hex'], 'Conflicting baseline fixture'
            before[key]=value
        baseline_builds[name]=sha(directory/'build.json')
        baseline_results[name]=sha(directory/'results.json')
    after_dir,after_result,after_build,after_identity,after=read_stage(candidate_name)
    assert before_identity==after_identity, 'Compiler, RTS, runner or PocketIC changed'
    rows=[]
    for key,new in after.items():
        if not re.search(family,new['family']):continue
        assert key in before, 'Candidate case absent from baseline: '+str(key)
        old=before[key]
        assert old['source_sha256']==new['source_sha256'], 'Different workload source: '+str(key)
        assert old['expected_hex']==new['expected_hex'], 'Different oracle: '+str(key)
        row={'name':key[0],'implementation':key[1],'family':new['family'],'source_sha256':new['source_sha256'],'expected_hex':new['expected_hex'],'before':{},'after':{}}
        for side,case in [('before',old),('after',new)]:
            for metric in ['instructions','allocated_bytes','reclaimed_bytes']:
                values=[m[metric] for m in case['measurements']]
                row[side][metric]=statistics.median(values)
                row[side][metric+'_range']=[min(values),max(values)]
            row[side]['wasm_bytes']=case['wasm_bytes']
        row['instruction_reduction_percent']=100*(1-row['after']['instructions']/row['before']['instructions'])
        row['speedup']=row['before']['instructions']/row['after']['instructions']
        row['allocation_delta_bytes']=row['after']['allocated_bytes']-row['before']['allocated_bytes']
        row['wasm_delta_bytes']=row['after']['wasm_bytes']-row['before']['wasm_bytes']
        rows.append(row)
    assert rows, 'No matching candidate family'
    return {'baseline':baseline_names[0] if len(baseline_names)==1 else baseline_names,'candidate':candidate_name,'baseline_build_sha256':baseline_builds,'candidate_build_sha256':sha(after_dir/'build.json'),'baseline_results_sha256':baseline_results,'candidate_results_sha256':sha(after_dir/'results.json'),'toolchain':before_identity,'trial_count':after_result['trials'],'baseline_case_count':len(before),'candidate_case_count':len(after),'selected_family_regex':family,'selected_case_count':len(rows),'rows':rows}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline',required=True,action='append',help='Repeat to combine disjoint frozen baseline cohorts')
    p.add_argument('--candidate',required=True)
    p.add_argument('--out',type=Path)
    p.add_argument('--family',default='.',help='Explicit family subset of a combined final cohort; full stage still validated')
    a=p.parse_args()
    result=compare(a.baseline,a.candidate,a.family)
    if a.out:
        write_comparison(a.out,result)
    print('| Workload | Before | After | Instruction reduction | Allocation delta | Wasm delta |')
    print('|---|---:|---:|---:|---:|---:|')
    for row in result['rows']:
        print(f"| {row['name']} | {row['before']['instructions']:,.0f} | {row['after']['instructions']:,.0f} | {row['instruction_reduction_percent']:+.2f}% | {row['allocation_delta_bytes']:+,.0f} | {row['wasm_delta_bytes']:+,} |")
