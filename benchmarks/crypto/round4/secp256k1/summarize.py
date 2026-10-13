#!/usr/bin/env python3
"""Summarize pinned matched three-trial stages without hiding regressions."""
import argparse, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('baseline',type=Path); p.add_argument('candidate',type=Path); p.add_argument('output',type=Path); a=p.parse_args()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(path):
 r=json.loads((path/'results.json').read_text()); b=json.loads((path/'build.json').read_text())
 assert r['complete'] and not r['failed_measurements'] and r['trials']==3
 assert r['build_sha256']==sha(path/'build.json')
 rows={}
 for case in r['cases']:
  ms=case['measurements']; assert len(ms)==3 and all(m['correct'] for m in ms)
  assert len({(m['instructions'],m['allocated_bytes'],m['reclaimed_bytes']) for m in ms})==1
  rows[case['name']]={k:ms[0][k] for k in ['instructions','allocated_bytes','reclaimed_bytes']}
  rows[case['name']].update(wasm_bytes=case['wasm_bytes'],source_sha256=case['source_sha256'],expected_hex=case['expected_hex'])
 runtime=path/'inputs/dist/secp256k1/runtime.wasm'
 return {'stage':r['stage'],'observations':len(rows)*3,'results_sha256':sha(path/'results.json'),'build_sha256':sha(path/'build.json'),
  'runtime_sha256':sha(runtime),'runtime_bytes':runtime.stat().st_size,'compiler_sha256':b['compiler_sha256']}, rows
old, left=read(a.baseline); new,right=read(a.candidate)
assert left.keys()==right.keys(); assert old['compiler_sha256']==new['compiler_sha256']
rows=[]
for name,before in left.items():
 after=right[name]
 assert before['source_sha256']==after['source_sha256'] and before['expected_hex']==after['expected_hex']
 rows.append({'name':name,'baseline':before,'candidate':after,'instructions_saved':before['instructions']-after['instructions'],
  'reduction_percent':100*(before['instructions']-after['instructions'])/before['instructions']})
a.output.write_text(json.dumps({'baseline':old,'candidate':new,'all_correct':True,'all_triples_identical':True,'cases':rows},indent=2)+'\n')
for row in rows: print(row['name'],row['baseline']['instructions'],row['candidate']['instructions'],f"{row['reduction_percent']:.2f}%")
