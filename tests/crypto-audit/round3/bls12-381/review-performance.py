#!/usr/bin/env python3
"""Independently check round3 BLS raw trials, medians, source and artifact parity."""
import argparse,hashlib,json,statistics
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
p=argparse.ArgumentParser();p.add_argument('--integration',type=Path,required=True);a=p.parse_args();I=a.integration.resolve();B=I/'benchmarks/crypto';C=B/'round3/bls12-381/comparison.json';cmp=json.loads(C.read_text());audit=json.loads((HERE/'report.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
records={};verified={};rows=[]
for side,stage in [('before',cmp['baseline']),('after',cmp['candidate'])]:
 d=B/'results'/stage;build=json.loads((d/'build.json').read_text());raw=json.loads((d/'results.json').read_text());meta=json.loads((d/'round3.json').read_text())
 assert build['complete'] and raw['complete'] and raw['trials']==3 and not raw['failed_measurements']
 assert len(build['cases'])==len(raw['cases'])==17
 assert raw['build_sha256']==sha(d/'build.json')
 assert raw['runner_sha256']==build['runner_sha256']==cmp['toolchain']['runner']
 assert raw['pocket_ic_sha256']==cmp['toolchain']['pocket_ic']
 assert build['compiler_sha256']==cmp['toolchain']['moc']==audit['compiler_binary_sha256']
 for key,path in build['rts_environment'].items():assert sha(Path(path))==cmp['toolchain'][key]
 assert meta['selected_manifest_sha256']==sha(B/'round3/stage-manifests'/f'{stage}.json')
 frozen=build['frozen_inputs_sha256']
 for name,digest in frozen.items():assert sha(d/'inputs'/name)==digest,(stage,name)
 builds={c['name']:c for c in build['cases']};samples={c['name']:c for c in raw['cases']}
 for name,case in samples.items():
  for key in ['source_sha256','wasm_sha256','expected_hex','wasm_bytes']:
   assert case[key]==builds[name][key],(name,key)
  assert sha(d/case['wasm'])==case['wasm_sha256']
  assert (d/case['wasm']).stat().st_size==case['wasm_bytes']
  assert len(case['measurements'])==3 and {m['trial'] for m in case['measurements']}=={0,1,2}
  expected=bytes.fromhex(case['expected_hex']);expected_digest=hashlib.sha256(expected).hexdigest()
  for m in case['measurements']:
   assert m['correct'] and m['output_sha256']==expected_digest and m['output_bytes']==len(expected)
   assert m['reclaimed_bytes']==0
 records[side]=(build,raw,meta,builds,samples)
 verified[side]=dict(stage=stage,build_sha256=sha(d/'build.json'),results_sha256=sha(d/'results.json'),round3_sha256=sha(d/'round3.json'),frozen_files_verified=len(frozen),wasm_artifacts_verified=17,trials_verified=51)
assert records['before'][2]['protocol_sha256']==records['after'][2]['protocol_sha256']
assert records['before'][0]['dependency_aliases']==records['after'][0]['dependency_aliases']
dependencies=[]
for side in ['before','after']:
 dependencies.append({name:digest for name,digest in records[side][0]['frozen_inputs_sha256'].items() if name.startswith('benchmarks/crypto/dependencies/')})
assert dependencies[0] and dependencies[0]==dependencies[1]
for row in cmp['rows']:
 name=row['name'];counts={}
 commands=[]
 for side in ['before','after']:
  stage_root=str(B/'results'/verified[side]['stage'])
  commands.append([arg.replace(stage_root,'<stage>') for arg in records[side][3][name]['command']])
  case=records[side][4][name];assert case['source_sha256']==row['source_sha256'];assert case['expected_hex']==row['expected_hex']
  for metric in ['instructions','allocated_bytes','reclaimed_bytes']:
   values=[m[metric] for m in case['measurements']]
   assert row[side][metric]==statistics.median(values),(name,side,metric)
   assert row[side][metric+'_range']==[min(values),max(values)]
  for snapshot in ['before_run','after_run','after_gc']:
   for metric in ['occupied_heap_bytes','wasm_capacity_bytes','total_allocation_bytes','reclaimed_bytes']:
    values=[m['memory'][snapshot][metric] for m in case['measurements']]
    assert row[side]['memory'][snapshot][metric]==statistics.median(values)
    assert row[side]['memory'][snapshot][metric+'_range']==[min(values),max(values)]
  counts[side]=row[side]['instructions']
 assert commands[0]==commands[1],(name,'compiler command changed')
 reduction=(1-counts['after']/counts['before'])*100
 assert abs(reduction-row['instruction_reduction_percent'])<1e-9
 assert abs(counts['before']/counts['after']-row['speedup'])<1e-12
 assert row['allocation_delta_bytes']==row['after']['allocated_bytes']-row['before']['allocated_bytes']
 assert row['wasm_delta_bytes']==row['after']['wasm_bytes']-row['before']['wasm_bytes']
 rows.append(dict(name=name,before_instructions=counts['before'],after_instructions=counts['after'],instruction_reduction_percent=reduction,allocation_delta_bytes=row['allocation_delta_bytes'],wasm_delta_bytes=row['wasm_delta_bytes']))
# Actual measured inputs must match the independently audited module and native/compiler code.
inputs=records['after'][0]['inputs_sha256'];source_matches={}
for name,digest in audit['source_sha256'].items():
 path=str(ROOT/name)
 if path in inputs:
  assert inputs[path]==digest==sha(ROOT/name),(name,'source changed')
  source_matches[name]=digest
for name,digest in audit['artifacts'].items():
 path=str(ROOT/'dist/bls12-381'/name);assert inputs[path]==digest==sha(Path(path))
assert 'packages/fast/src/BLS12381.mo' in source_matches
assert 'plugins/bls12-381/runtime/src/lib.rs' in source_matches
for k in ['baseline_build_sha256','baseline_results_sha256']:
 side_key='build_sha256' if 'build' in k else 'results_sha256';assert cmp[k][cmp['baseline']]==verified['before'][side_key]
assert cmp['candidate_build_sha256']==verified['after']['build_sha256'];assert cmp['candidate_results_sha256']==verified['after']['results_sha256']
report=dict(status='pass',comparison_sha256=sha(C),audited_production_commit=audit['audited_production_commit'],verified=verified,matching_audited_source_sha256=source_matches,rows=rows,assessment='Approve aggregate fusion: all valid aggregate cohorts improve instructions and allocation; single verifiers are unchanged. Preserve explicit small-invalid-input and Wasm-size regressions in published results.',limitations=['Fresh-canister isolated operations with fixed inputs, not a saturation or statistical wall-time study.','All three trials are deterministic in these measured counters.','Occupied-heap snapshots are not peak or live memory; four forced GC increments do not prove full reclamation.','Single-signature verification does not improve; measured benefits are aggregate profiles.'])
(HERE/'performance-review.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(dict(status=report['status'],verified=verified),indent=2))
for row in rows:print(row['name'],row['before_instructions'],row['after_instructions'],round(row['instruction_reduction_percent'],4),row['allocation_delta_bytes'],row['wasm_delta_bytes'])
