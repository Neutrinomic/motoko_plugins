#!/usr/bin/env python3
"""Independently recompute the reported round4 comparisons from raw trials."""
import argparse
import hashlib
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--results-root',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
parser.add_argument('--extra',action='store_true',help='Review the final paired direct/cold ten-call cohort')
args=parser.parse_args()
summaries=ROOT/'benchmarks/crypto/round4/secp256k1'
stages={}
pins={}
def stage(meta):
    name=meta['stage']
    path=args.results_root/name
    b=json.loads((path/'build.json').read_text())
    r=json.loads((path/'results.json').read_text())
    assert sha(path/'build.json')==meta['build_sha256']==r['build_sha256']
    assert sha(path/'results.json')==meta['results_sha256']
    assert b['complete'] and r['complete'] and not r['failed_measurements']
    assert b['compiler_sha256']==meta['compiler_sha256']=='24d8d0b951c4d2928c505ed6e91503750c83cf754d9518dcda9a265a8842beb2'
    runtime=path/'inputs/dist/secp256k1/runtime.wasm'
    assert sha(runtime)==meta['runtime_sha256']==b['frozen_inputs_sha256']['dist/secp256k1/runtime.wasm']
    assert runtime.stat().st_size==meta['runtime_bytes']
    built={c['name']:c for c in b['cases']}
    cases={}
    count=0
    for c in r['cases']:
        assert c['returncode']==0 and built[c['name']]['returncode']==0
        assert len(c['measurements'])==3 and {m['trial'] for m in c['measurements']}=={0,1,2}
        assert all(m['correct'] for m in c['measurements'])
        assert all({m[k] for m in c['measurements']}=={c['measurements'][0][k]} for k in ['instructions','allocated_bytes','reclaimed_bytes','output_sha256'])
        wasm=path/c['wasm']
        assert sha(wasm)==c['wasm_sha256']==built[c['name']]['wasm_sha256']
        assert wasm.stat().st_size==c['wasm_bytes']
        source=path/'inputs/benchmarks/crypto'/c['source']
        assert sha(source)==c['source_sha256']==built[c['name']]['source_sha256']
        cases[c['name']]={k:c['measurements'][0][k] for k in ['instructions','allocated_bytes','reclaimed_bytes']}
        cases[c['name']].update({k:c[k] for k in ['wasm_bytes','source_sha256','expected_hex']})
        count+=len(c['measurements'])
    assert count==meta['observations']==(18 if args.extra else 33)
    assert len(cases)==(6 if args.extra else 11)
    stages[name]={**meta,'oracle_correct':True,'triples_identical':True}
    return cases
names=['extra-comparison'] if args.extra else ['c1-fixed-generator','c2-inversionless-verify','c3-specialized-square','final-comparison']
for name in names:
    path=summaries/(name+'.json')
    report=json.loads(path.read_text())
    left,right=stage(report['baseline']),stage(report['candidate'])
    assert report['all_correct'] and report['all_triples_identical']
    assert {c['name'] for c in report['cases']}==set(left)==set(right)
    for case in report['cases']:
        before,after=left[case['name']],right[case['name']]
        assert case['baseline']==before and case['candidate']==after
        assert before['source_sha256']==after['source_sha256']
        saved=before['instructions']-after['instructions']
        assert saved==case['instructions_saved']
        assert abs(case['reduction_percent']-saved/before['instructions']*100)<1e-10
    pins[name+'.json']=sha(path)
selected=stages['prepared-round4-secp256k1-extra-final' if args.extra else 'prepared-round4-secp256k1-c3-candidate']
assert selected['runtime_sha256']==sha(ROOT/'dist/secp256k1/runtime.wasm')
total=36 if args.extra else 132
assert len(stages)==(2 if args.extra else 4) and sum(s['observations'] for s in stages.values())==total
report={'passed':True,'distinct_observations':total,'stages':stages,'summary_sha256':pins,
        'method':'Recomputed every comparison from raw three-trial stages; checked oracle flags, identical counters/allocations, artifact and compiled-Wasm/source hashes, compiler identity, every summary field and percentage. No host timing, isolated live-heap or new collection inference.',
        'script_sha256':sha(Path(__file__))}
if args.extra:
    prior=json.loads((HERE/'numeric-review.json').read_text())
    assert prior['passed'] and prior['distinct_observations']==132
    assert set(prior['stages']).isdisjoint(stages)
    report['prior_numeric_review_sha256']=sha(HERE/'numeric-review.json')
    report['total_distinct_observations_with_prior_review']=132+total
    report['benchmark_readme_sha256']=sha(summaries/'README.md')
    readme=(summaries/'README.md').read_text()
    assert '168 PocketIC observations' in readme
    report['actual_ten_call_comparisons']={}
    for label,family in [('ECDSA verify','ecdsa-verify'),('Schnorr verify','schnorr-verify'),('Schnorr sign','schnorr-sign')]:
        direct=right[f'secp256k1-{family}-direct-n10']
        cold=right[f'secp256k1-{family}-cold-n10']
        saving=(direct['instructions']-cold['instructions'])/direct['instructions']*100
        expected=f"| {label} | {direct['instructions']:,} | {cold['instructions']:,} | {saving:.2f}% | {direct['allocated_bytes']:,} / {cold['allocated_bytes']:,} B |"
        assert expected in readme,expected
        assert cold['allocated_bytes']-direct['allocated_bytes']==(120 if family=='schnorr-sign' else 568)
        source=args.results_root/selected['stage']/f'inputs/benchmarks/crypto/round4/secp256k1/cases/secp256k1-{family}-cold-n10/main.mo'
        measured=source.read_text().split('let start = Prim.performanceCounter(0);',1)[1].split('let stop = Prim.performanceCounter(0);',1)[0]
        assert measured.index('key := ?unwrap(Curve.prepare')<measured.index('var remaining = 10;')<measured.index('while (remaining > 0)')
        report['actual_ten_call_comparisons'][family]={'direct':direct,'preparation_plus_ten':cold,'saving_percent':saving,'preparation_inside_interval_source_sha256':sha(source)}
args.out.write_text(json.dumps(report,indent=2)+'\n')
print(f'{total} observations and all {len(names)} comparison summaries independently verified')
