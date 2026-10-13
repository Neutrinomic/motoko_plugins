#!/usr/bin/env python3
"""Preserve prior BLS operations/oracles; add only untimed memory observation."""
import hashlib
import json
from pathlib import Path
HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
MEMORY = '''  public query func memory() : async {
    heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat
  } {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
     totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
'''
a = json.loads((BENCH/'all-cases.json').read_text())['cases']
b = json.loads((BENCH/'round2/bls-cohort.json').read_text())['cases']
selected = [c for c in b if 'aggregate_' in c['name']]
selected += [c for c in a if c['family'] == 'bls12-381' and c['implementation'] == 'fast'
             and ('verify_' in c['name'] or 'pairing_' in c['name'])]
cases = []
for case in selected:
    original = BENCH/case['source']
    source = original.read_text()
    assert 'public query func memory(' not in source
    end = source.rfind('}')
    assert end >= 0 and not source[end+1:].strip()
    output = HERE/'cases'/case['name']/'main.mo'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(source[:end]+MEMORY+source[end:])
    cases.append({**case, 'source':str(output.relative_to(BENCH)), 'memory_metrics':True,
                  'control_source':case['source'],
                  'control_source_sha256':hashlib.sha256(original.read_bytes()).hexdigest()})
(HERE/'cohort.json').write_text(json.dumps({'methodology':'Existing independent fixtures and oracles; only an untimed memory query added.','cases':cases},indent=2)+'\n')
print(len(cases))
