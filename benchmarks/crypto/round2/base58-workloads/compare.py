#!/usr/bin/env python3
"""Verify frozen result cohorts and summarize Base58's private round-two candidate."""
import hashlib,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
RESULTS=ROOT/'benchmarks/crypto/results'
CANDIDATE=ROOT/'_build/crypto-optimization-round2/base58-limbs-v3'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(stage):
    path=RESULTS/f'round2-{stage}'/'results.json';data=json.loads(path.read_text())
    assert data['complete'] and data['trials']==3
    assert len(data['cases'])==data['expected_case_count']
    for c in data['cases']:
        assert c['returncode']==0 and len(c['measurements'])==3
        expected=hashlib.sha256(bytes.fromhex(c['expected_hex'])).hexdigest()
        assert all(m['correct'] and m['output_sha256']==expected for m in c['measurements'])
        for key in ['instructions','allocated_bytes','reclaimed_bytes','output_bytes']:
            assert len({m[key] for m in c['measurements']})==1,(c['name'],key)
    return {c['name']:c for c in data['cases']},dict(path=str(path.relative_to(ROOT)),sha256=digest(path),build_sha256=data['build_sha256'])
baseline,b0=read('base58-baseline');small,b1=read('base58-baseline-small');baseline.update(small)
candidate,c0=read('base58-limbs-v3')
assert baseline.keys()==candidate.keys()
rows=[]
for name,b in baseline.items():
    c=candidate[name]
    for key in ['source_sha256','expected_hex','plugins']:assert b[key]==c[key],(name,key)
    bm,cm=b['measurements'][0],c['measurements'][0]
    rows.append(dict(name=name,baseline_instructions=bm['instructions'],candidate_instructions=cm['instructions'],speedup=bm['instructions']/cm['instructions'],instruction_reduction_percent=100*(1-cm['instructions']/bm['instructions']),baseline_allocated=bm['allocated_bytes'],candidate_allocated=cm['allocated_bytes'],baseline_wasm_bytes=b['wasm_bytes'],candidate_wasm_bytes=c['wasm_bytes'],wasm_delta=c['wasm_bytes']-b['wasm_bytes']))
assert all(r['baseline_allocated']==r['candidate_allocated'] for r in rows)
files=['plugins/base58/runtime/src/lib.rs','plugins/base58/README.md','dist/base58/runtime.wasm','dist/base58/plugin.cmxs','dist/base58/build.json']
report=dict(candidate=str(CANDIDATE.relative_to(ROOT)),case_count=len(rows),trials_per_case=3,all_exact_outputs=True,allocations_unchanged=True,result_inputs=[b0,b1,c0],artifacts={f:dict(sha256=digest(CANDIDATE/f),bytes=(CANDIDATE/f).stat().st_size) for f in files},regressions=[r['name'] for r in rows if r['speedup']<1],comparisons=rows)
(HERE/'comparison.json').write_text(json.dumps(report,indent=2)+'\n')
lines=['# Base58 optimization round two','','Candidate: `'+str(CANDIDATE.relative_to(ROOT))+'`. Root implementation is unchanged pending independent audit and promotion.','','Each of the '+str(len(rows))+' paired cases ran on three fresh canisters. Python integer conversion and hashlib supply independent exact outputs. Every trial matched, instruction/allocation counts were repeatable, and managed allocation was unchanged. Inputs are prepared and result serialization performed outside the measured interval. Wasm sizes are whole canister artifacts.','','| Case | Baseline instructions | Candidate instructions | Speedup | Allocated bytes | Wasm delta |','|---|---:|---:|---:|---:|---:|']
for r in rows:lines.append(f"| {r['name']} | {r['baseline_instructions']:,} | {r['candidate_instructions']:,} | {r['speedup']:.3f}x | {r['candidate_allocated']:,} | {r['wasm_delta']:+,} |")
lines+=['','Two transition cases regress: decoding the nine-byte payload adds 12 instructions (0.54%), and the twelve-byte payload adds 110 instructions (4.38%). The other 66 cases improve. The candidate is recommended for the much larger address, extended-key and bounded bulk gains; these small regressions and the code-size increase are explicit tradeoffs.','','Runtime Wasm grows from 3,099 to '+str(report['artifacts']['dist/base58/runtime.wasm']['bytes'])+' bytes. Bounded stack scratch replaces repeated byte/digit carry loops with wider limbs, without additional managed allocation. Empty/zero-only and small arbitrary inputs avoid limb scratch.','','Earlier candidates are retained in `round2-base58-limbs-v1` and `round2-base58-limbs-v2`. V1 had small-input regressions; v2 added scalar conversion; v3 avoids redundant zero-only scalar conversion. No input-specific precomputed outputs are used.','','Validation: all five original native tests plus seven baseline/differential tests pass; the independent differential suite exercises 1,665 byte strings, capacities, output sentinels, padding, input preservation, alphabet errors and quota precedence. All eight public source/IR/lowered/Wasm run/fail/trap fixtures passed with unchanged goldens, and all six Base58 Ash methods passed. The independent round-two auditor passed 1,657 Python bigint oracle vectors, all 16 pointer alignment residues, read-only input/guarded output pages, error precedence and ASan/debug execution; evidence is under `_build/crypto-optimization-round2/central-audit/base58`.','','Reproduction: `python3 benchmarks/crypto/round2/base58-workloads/generate.py`; run the frozen baseline with `cases.json` and `small-cases.json` through `round2/run-stage.py`, and the selected candidate with `broad-cases.json`, `--root '+str(CANDIDATE.relative_to(ROOT))+' --plugin base58`. Use fresh stage names; results are immutable. Run this comparator after collecting the named stages.','','Machine-readable hashes, per-case allocation and Wasm sizes are in `comparison.json`.']
(HERE/'REPORT.md').write_text('\n'.join(lines)+'\n')
print(json.dumps({k:report[k] for k in ['case_count','all_exact_outputs','allocations_unchanged','regressions']},indent=2))
