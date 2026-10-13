#!/usr/bin/env python3
"""Recreate the complete operation table from immutable PocketIC reports."""
import csv, json
from pathlib import Path
here=Path(__file__).resolve().parent
final=json.loads((here/'results/final/results.json').read_text())
original=json.loads((here/'results/final-baseline/results.json').read_text())
assert len(final['cases'])==42 and len(original['cases'])==42
before={(row['capacity'],row['operation']):row for row in original['cases']}
with (here/'results/operations.csv').open('w') as f:
 writer=csv.writer(f);writer.writerow(['capacity','operation','operation_count','core_instructions','plugin_original_instructions','plugin_final_instructions','core_allocated_bytes','plugin_allocated_bytes','core_to_plugin_speedup','core_heap_after','plugin_heap_after'])
 for row in final['cases']:
  a=before[row['capacity'],row['operation']];p=row['plugin'];c=row['core']
  assert len(row['samples'])==3
  for sample in row['samples']:
   for key in ['checksum','size','first','next','operations']:assert sample['plugin'][key]==sample['core'][key]
  assert c['checksum']==a['core']['checksum']
  writer.writerow([row['capacity'],row['operation'],p['operations'],c['instructions'],a['plugin']['instructions'],p['instructions'],c['allocated'],p['allocated'],row['speedup'],c['memory_after']['heap'],p['memory_after']['heap']])
print('| Capacity | Operation | Count | Core instructions | Plugin instructions | Core / plugin | Core / plugin allocation |')
print('|---:|---|---:|---:|---:|---:|---:|')
for row in final['cases']:
 if row['capacity'] in [1000,10000,100000] and row['operation'] in ['append','overwrite','get_middle','page_tail_32','drop_half']:
  p=row['plugin'];c=row['core']
  print(f"| {row['capacity']:,} | {row['operation']} | {p['operations']:,} | {c['instructions']:,} | {p['instructions']:,} | {row['speedup']:.2f}× | {c['allocated']:,} / {p['allocated']:,} B |")

core,plugin=final['churn']
for a,b in zip(core['checkpoints'][1:],plugin['checkpoints'][1:]):
 assert a['checksum']==b['checksum'] and a['memory']['size']==b['memory']['size']==1024
 assert b['storage']=={'directory':16,'slots':1024,'bytes':1048576,'chunks':16}
assert plugin['cleared_storage']=={'directory':0,'slots':0,'bytes':0,'chunks':0}
for row in final['churn']:
 assert row['checkpoints'][-1]['memory']['reclaimed']>500*1024*1024
