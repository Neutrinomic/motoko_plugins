#!/usr/bin/env python3
"""Retain P256 controls and independent RFC6979 digest-boundary workloads."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
ROOT = BENCH.parents[1]
MEMORY = '''  // Observed outside the timed operation.
  public query func memory() : async {
    heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat
  } {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
     totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
'''
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def blob(value): return '"' + ''.join('\\%02x' % b for b in bytes.fromhex(value)) + '"'
def write(case, source):
    out = HERE/'cases'/case['name']/'main.mo'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(source)
    return {**case, 'source': out.relative_to(BENCH).as_posix(), 'memory_metrics': True}

cases=[]
original=BENCH/'round2/stage-manifests/round2-p256-hotspots-baseline.json'
controls=json.loads(original.read_text())['cases']
controls += [c for c in json.loads((BENCH/'round2/api-plugin-cases.json').read_text())['cases'] if c['name']=='api-p256-derivePublicKey-fast']
for case in controls:
    old=BENCH/case['source']
    source=old.read_text()
    closing=source.rfind('}')
    assert closing>=0 and not source[closing+1:].strip()
    cases.append(write({**case, 'control_source':case['source'], 'control_source_sha256':sha(old)},source[:closing]+MEMORY+source[closing:]))

vectors=ROOT/'plugins/p256/tests/vectors/rfc6979-digest-boundaries.json'
golden=json.loads(vectors.read_text())
for vector in golden['vectors']:
    name='r3-p256-sign-digest-'+vector['name'].replace('_','-')
    source=f'''import Prim "mo:⛔";
import P256 "mo:fast/P256";
persistent actor {{
  transient let secret : Blob = {blob(golden['secret_key'])};
  transient let digest : Blob = {blob(vector['digest'])};
  transient var result : P256.Result<Blob> = #ok("");
  public func configure() : async () {{}};
  public func run() : async {{instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat}} {{
    let beforeAllocated = Prim.rts_total_allocation();
    let beforeReclaimed = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := P256.signPrehash(secret, digest);
    let instructions = Prim.performanceCounter(0) - start;
    {{instructions; allocated = Prim.rts_total_allocation() - beforeAllocated;
      reclaimed = Prim.rts_reclaimed() - beforeReclaimed; outputSize = 64}}
  }};
{MEMORY}  public query func bytesResult() : async Blob {{
    let #ok(output) = result else Prim.trap("signature error");
    assert output == {blob(vector['signature'])};
    output
  }};
}}
'''
    cases.append(write({'name':name,'family':'p256','implementation':'fast','comparison':name,'plugins':['p256'],'expected_hex':vector['signature'],'operations_per_sample':1,'fixture_provenance':golden['source'],'oracle_source':str(vectors.relative_to(ROOT)),'oracle_sha256':sha(vectors)},source))
(HERE/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(f'Generated {len(cases)} P256 cases')
