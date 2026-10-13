#!/usr/bin/env python3
"""Strict paired round-three comparison. Reject incomplete or semantically unequal runs."""
import argparse, hashlib, json, re, statistics
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def write_comparison(path,result):
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x') as output:
        output.write(json.dumps(result,indent=2)+'\n')


def natural(value):
    assert isinstance(value,int) and not isinstance(value,bool) and value>=0, 'Invalid measurement counter'
    return value


def read_stage(name):
    assert re.fullmatch(r'round3-[a-zA-Z0-9_-]+',name), 'Unsafe stage name'
    directory=BENCH/'results'/name
    result=json.loads((directory/'results.json').read_text())
    build=json.loads((directory/'build.json').read_text())
    assert result['stage']==build['stage']==name, 'Stage identity mismatch'
    assert result['protocol']==build['protocol']=='crypto-round3-v1', 'Different measurement protocol'
    assert result['runner_sha256']==build['runner_sha256']==sha(directory/'inputs/benchmarks/crypto/round3/run.mjs'), 'Frozen runner changed'
    for relative,digest in build['frozen_inputs_sha256'].items():
        path=Path(relative)
        assert not path.is_absolute() and '..' not in path.parts, 'Unsafe frozen input path'
        assert sha(directory/'inputs'/path)==digest, 'Frozen input changed: '+relative
    assert result['build_sha256']==sha(directory/'build.json'), 'Build metadata changed'
    assert result['complete'] and build['complete'], 'Incomplete stage'
    assert result['expected_case_count']==len(result['cases'])==len(build['cases'])==build['expected_case_count'], 'Incomplete cohort'
    assert isinstance(result['trials'],int) and result['trials']>=3
    assert result['failed_measurements']==0, 'Failed measurements'
    identity={'protocol':result['protocol'],'moc':build['compiler_sha256'],'pocket_ic':result['pocket_ic_sha256'],'runner':result['runner_sha256']}
    dependency_pins={path:digest for path,digest in build['frozen_inputs_sha256'].items() if path.startswith('benchmarks/crypto/dependencies/')}
    assert 'benchmarks/crypto/dependencies/mops.lock' in dependency_pins, 'Missing dependency lock'
    identity['motoko_dependencies_sha256']=hashlib.sha256(json.dumps(dependency_pins,sort_keys=True,separators=(',',':')).encode()).hexdigest()
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
        for field in ['family','source','expected_hex','source_sha256','wasm_sha256','wasm_bytes']:
            assert case[field]==compiled[field], 'Build/result mismatch: '+field
        assert case.get('plugins',[])==compiled.get('plugins',[]), 'Build/result plugin mismatch'
        assert sha(directory/compiled['wasm'])==compiled['wasm_sha256'], 'Wasm changed'
        frozen_source=directory/'inputs/benchmarks/crypto'/case['source']
        assert sha(frozen_source)==case['source_sha256'], 'Frozen fixture changed'
        assert case.get('memory_metrics',False)==compiled.get('memory_metrics',False), 'Memory instrumentation mismatch'
        measurements=case['measurements']
        assert len(measurements)==result['trials']
        assert sorted(m['trial'] for m in measurements)==list(range(result['trials'])), 'Invalid trial indices'
        oracle=hashlib.sha256(bytes.fromhex(case['expected_hex'])).hexdigest()
        assert all(m['correct'] and m['output_sha256']==oracle for m in measurements), 'Oracle mismatch'
        for measurement in measurements:
            for metric in ['instructions','allocated_bytes','reclaimed_bytes']:
                natural(measurement[metric])
            assert measurement['output_bytes']==len(bytes.fromhex(case['expected_hex'])), 'Output length mismatch'
            if case.get('memory_metrics',False):
                assert set(measurement['memory'])=={'before_run','after_run','after_gc'}, 'Missing memory snapshot'
                for snapshot in measurement['memory'].values():
                    assert set(snapshot)=={'occupied_heap_bytes','wasm_capacity_bytes','total_allocation_bytes','reclaimed_bytes'}, 'Incomplete memory counters'
                    for value in snapshot.values():natural(value)
            else:
                assert 'memory' not in measurement, 'Unexpected memory instrumentation'
        cases[key]=case
    return directory,result,build,identity,cases

def compare(baseline_name,candidate_name,family='.'):
    baseline_names=[baseline_name] if isinstance(baseline_name,str) else baseline_name
    assert baseline_names
    before={};before_identity=None;before_trials=None;baseline_builds={};baseline_results={}
    for name in baseline_names:
        directory,result,build,identity,cases=read_stage(name)
        if before_identity is None:before_identity=identity;before_trials=result['trials']
        assert before_trials==result['trials'], 'Baseline trial counts differ'
        assert before_identity==identity, 'Baseline toolchains differ'
        for key,value in cases.items():
            assert key not in before, 'Overlapping baseline cohorts: '+str(key)
            before[key]=value
        baseline_builds[name]=sha(directory/'build.json')
        baseline_results[name]=sha(directory/'results.json')
    after_dir,after_result,after_build,after_identity,after=read_stage(candidate_name)
    assert before_trials==after_result['trials'], 'Paired trial counts differ'
    assert before_identity==after_identity, 'Compiler, RTS, runner, PocketIC or dependencies changed'
    rows=[]
    for key,new in after.items():
        if not re.search(family,new['family']):continue
        assert key in before, 'Candidate case absent from baseline: '+str(key)
        old=before[key]
        assert old['source_sha256']==new['source_sha256'], 'Different workload source: '+str(key)
        assert old['expected_hex']==new['expected_hex'], 'Different oracle: '+str(key)
        assert old.get('memory_metrics',False)==new.get('memory_metrics',False), 'Different memory instrumentation: '+str(key)
        row={'name':key[0],'implementation':key[1],'family':new['family'],'source_sha256':new['source_sha256'],'expected_hex':new['expected_hex'],'before':{},'after':{}}
        for side,case in [('before',old),('after',new)]:
            for metric in ['instructions','allocated_bytes','reclaimed_bytes']:
                values=[m[metric] for m in case['measurements']]
                row[side][metric]=statistics.median(values)
                row[side][metric+'_range']=[min(values),max(values)]
            row[side]['wasm_bytes']=case['wasm_bytes']
            if case.get('memory_metrics',False):
                row[side]['memory']={}
                for snapshot in ['before_run','after_run','after_gc']:
                    counters={}
                    for metric in ['occupied_heap_bytes','wasm_capacity_bytes','total_allocation_bytes','reclaimed_bytes']:
                        values=[m['memory'][snapshot][metric] for m in case['measurements']]
                        counters[metric]=statistics.median(values)
                        counters[metric+'_range']=[min(values),max(values)]
                    row[side]['memory'][snapshot]=counters
        assert row['before']['instructions']>0 and row['after']['instructions']>0, 'Zero instruction count'
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
