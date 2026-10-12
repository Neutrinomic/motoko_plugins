#!/usr/bin/env python3
"""Independently validate completed round-two experiments against matching frozen baselines."""
import importlib.util, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent
spec=importlib.util.spec_from_file_location('paired_compare',HERE/'compare.py')
paired=importlib.util.module_from_spec(spec);spec.loader.exec_module(paired)
stages=[];pending=[];excluded=[]
documented={
    'round2-bls-combined-candidate1':'Rejected before compilation by the provenance guard: reduced candidate Cargo workspace did not match artifact source pins. Rebuilt from the complete frozen workspace for candidate2.',
    'round2-sha512-kernel-simd-smoke':'Rejected during compilation: plugin importer does not accept Wasm SIMD opcode 0xfd. No performance ratio reported.',
    'round2-bech32-fused-screen':'Preliminary screen retained for historical context only; final Bech32 decisions use the complete 48-case frozen-baseline cohorts.',
    'round2-bech32-poly-screen':'Preliminary screen retained for historical context only; final Bech32 decisions use the complete 48-case frozen-baseline cohorts.',
    'round2-bls-cachecap-repeated':'Abandoned, not measured: directory contains only an empty inputs directory and no selected fixtures, build or results. Final cache-cap evidence is the complete round2-bls-cachecap-aggregates cohort.',
    'round2-api-final':'Final public API cohort is compared with pure Motoko in api-measurements.json; it is not a single-family before/after experiment.'
}
for directory in sorted((BENCH/'results').glob('round2-*')):
    if directory.name in documented:
        excluded.append({'stage':directory.name,'reason':documented[directory.name]});continue
    if not (directory/'round2.json').exists() or not (directory/'results.json').exists():
        pending.append({'stage':directory.name,'reason':'No complete measurement records yet'});continue
    try:result=json.loads((directory/'results.json').read_text())
    except json.JSONDecodeError:
        pending.append({'stage':directory.name,'reason':'Measurement record is being written; retry after completion'});continue
    if not result['complete']:
        pending.append({'stage':directory.name,'reason':'Measurements incomplete'});continue
    metadata=json.loads((directory/'round2.json').read_text())
    stages.append((directory,result,metadata))
baselines=[(d,r,m) for d,r,m in stages if m['candidate_root']==m['baseline_root']]
records=[];unpaired=[]
for directory,result,metadata in stages:
    if metadata['candidate_root']==metadata['baseline_root']:continue
    keys={(c['name'],c['implementation'],c['source_sha256'],c['expected_hex']) for c in result['cases']}
    candidates=[]
    for bd,br,bm in baselines:
        baseline_keys={(c['name'],c['implementation'],c['source_sha256'],c['expected_hex']) for c in br['cases']}
        if keys<=baseline_keys:candidates.append((len(baseline_keys),bd.name))
    if not candidates:
        remaining=set(keys);selected=[]
        for bd,br,bm in baselines:
            available={(c['name'],c['implementation'],c['source_sha256'],c['expected_hex']) for c in br['cases']}
            if remaining&available:
                selected.append(bd.name);remaining-=available
        if remaining:
            unpaired.append({'stage':directory.name,'reason':'No baseline contains all identical workload fixtures and oracles'});continue
        baseline=selected
    else:baseline=min(candidates)[1]
    comparison=paired.compare(baseline,directory.name)
    path=HERE/'comparisons'/(directory.name.removeprefix('round2-')+'.json')
    paired.write_comparison(path,comparison)
    reductions=[r['instruction_reduction_percent'] for r in comparison['rows']]
    records.append({'stage':directory.name,'baseline':baseline,'cases':len(reductions),'trials':comparison['trial_count'],'improved_cases':sum(v>0 for v in reductions),'unchanged_cases':sum(v==0 for v in reductions),'regressed_cases':sum(v<0 for v in reductions),'instruction_reduction_percent_range':[min(reductions),max(reductions)],'comparison':str(path.relative_to(HERE))})
report={'reviewed':records,'unpaired':unpaired,'pending':pending,'documented_exclusions':excluded}
(HERE/'experiment-review.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'{len(records)} strict comparisons; {sum(r["cases"]*r["trials"] for r in records)} verified candidate trials; {len(unpaired)} unpaired; {len(pending)} pending')
for row in unpaired:print(row)
