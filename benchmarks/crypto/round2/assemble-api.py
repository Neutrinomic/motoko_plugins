#!/usr/bin/env python3
"""Assemble exact public-API fixture inventory without regenerating family-owned sources."""
import argparse, hashlib, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--allow-pending-bls',action='store_true')
a=p.parse_args()
inventories=[HERE/'api-hash-codec/api-inventory.json',HERE/'api-bitcoin/inventory.json']
combined_curves=HERE/'api-curves/api-rows.json'
if combined_curves.exists():inventories.append(combined_curves)
else:inventories.append(HERE/'api-curves/curve-api-rows.json')
bls=HERE/'api-curves/bls/api-rows.json'
if not bls.exists():bls=HERE/'api-curves/bls/inventory.json'
if not combined_curves.exists():
    if bls.exists():inventories.append(bls)
    else:assert a.allow_pending_bls, 'BLS API inventory not ready'
case_index={}
for path in [BENCH/'all-cases.json',*sorted(HERE.rglob('*cases.json'))]:
    if 'stage-manifests' in path.parts or path.name in ['api-cases.json','api-plugin-cases.json','api-pure-cases.json']:continue
    try:data=json.loads(path.read_text())
    except (json.JSONDecodeError,UnicodeDecodeError):continue
    cases=data.get('cases',[]) if isinstance(data,dict) else data
    if not isinstance(cases,list):continue
    for case in cases:
        if not isinstance(case,dict) or not all(k in case for k in ['name','implementation','source','expected_hex']):continue
        source=BENCH/case['source']
        assert source.exists(), 'Missing fixture '+str(source)
        key=(case['name'],case['implementation'])
        digest=hashlib.sha256(source.read_bytes()).hexdigest()
        case_index.setdefault(key,{})[digest]=case
rows=[];selected={}
overrides={}
override_paths=[HERE/'api-closest-overrides.json',*sorted(HERE.glob('api-*/closest*/override*.json')),HERE/'api-display-metadata.json']
for override_path in override_paths:
    if override_path.exists():
        value=json.loads(override_path.read_text())
        for key,update in value.get('overrides',value).items():
            overrides.setdefault(key,{}).update(update)
for path in inventories:
    data=json.loads(path.read_text());family_rows=data['api_rows'] if isinstance(data,dict) else data
    for row in family_rows:
        if row['id'] in overrides:
            override=overrides[row['id']]
            row.update(override)
            if override.get('counterpart_caveat'):row['notes']=override['counterpart_caveat']
            if override.get('contract')=='closest-different-wire':row['visible_footnote']='G2-uncompressed'
            if override.get('footnote_id'):row['visible_footnote']=override['footnote_id']
        for field in ['plugin_case','native_case']:
            ref=row.get(field)
            if not ref:continue
            choices=case_index[(ref['name'],ref['implementation'])]
            if ref.get('source'):
                digest=hashlib.sha256((BENCH/ref['source']).read_bytes()).hexdigest()
                assert not ref.get('source_sha256') or ref['source_sha256']==digest
                case=choices[digest]
            else:
                assert len(choices)==1, 'Ambiguous fixture; add source pin: '+str(ref)
                digest,case=next(iter(choices.items()))
            ref['source']=case['source'];ref['source_sha256']=digest
            selected[(case['name'],case['implementation'],digest)]=case
            assert bool(case.get('plugins'))==(field=='plugin_case'), 'Plugin/pure Motoko label mismatch'
        plugin=case_index[(row['plugin_case']['name'],row['plugin_case']['implementation'])][row['plugin_case']['source_sha256']]
        if row.get('native_case'):
            native=case_index[(row['native_case']['name'],row['native_case']['implementation'])][row['native_case']['source_sha256']]
            assert plugin['expected_hex']==native['expected_hex'], 'Unequal public outputs: '+row['id']
        rows.append(row)
assert len({row['id'] for row in rows})==len(rows), 'Duplicate API workload id'
callables=sorted({row['module']+'.'+row['function'] for row in rows})
(HERE/'api-inventory.json').write_text(json.dumps({'callable_count':len(callables),'workload_rows':len(rows),'callables':callables,'inventory_sources':{str(path.relative_to(BENCH)):hashlib.sha256(path.read_bytes()).hexdigest() for path in inventories},'counterpart_overrides':overrides,'api_rows':rows},indent=2)+'\n')
for name,predicate in [('api-cases.json',lambda c:True),('api-plugin-cases.json',lambda c:bool(c.get('plugins'))),('api-pure-cases.json',lambda c:not c.get('plugins'))]:
    cases=[case for case in selected.values() if predicate(case)]
    (HERE/name).write_text(json.dumps({'cases':cases},indent=2)+'\n')
    print(name,len(cases))
print(len(callables),'callables;',len(rows),'workload rows')
