from pathlib import Path
import hashlib, json, subprocess
root=Path(__file__).resolve().parent
repo=root.parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
commit=subprocess.check_output(['git','-C',repo,'rev-parse','HEAD'],text=True).strip()
assert subprocess.check_output(['git','-C',repo,'status','--porcelain'],text=True)==''
accepted={'baseline_commit':'c320bf90d0b63a058b5de2c41a42c96e8b82243f','candidate_commit':commit,'abi':1,'moc_sha256':sha(repo/'src/moc'),'source_sha256':{str(p.relative_to(repo)):sha(p) for p in [repo/'src/codegen/compile.ml',repo/'test/compute-plugins/run/scalar-tagged-order.mo']},'paired_phases':54,'raw_measurements':324,'trials_per_phase_per_compiler':3,'sdk_fixtures':46,'production_implementation_line_delta':-1}
(root/'accepted.json').write_text(json.dumps(accepted,indent=2)+'\n')
files=['README.md','audit.md','accepted.json','main.mo','cases.json','run.mjs','fixture_callbacks.ml','scalar-tagged-order.mo','generate.py','generate-test.py','generate-map.py','build-evidence.py','build-map.py','summarize.py','make-manifest.py','baseline.json','candidate.json','provenance.json','summary.csv','summary.log','canonical-freeze.json','validation.log','baseline-bench.log','committed-build.log','committed-actors-build.log','committed-bench.log','committed-fixtures.log','map/main.mo','map/cases.json','map/Map.mo','map/baseline.json','map/candidate.json','map/provenance.json']
for directory in ['audit','rejected-oracle','precommit']:
    files += [str(p.relative_to(root)) for p in sorted((root/directory).rglob('*')) if p.is_file() and '_out' not in p.parts]
files=sorted(set(files))
binaries=['baseline/main.wasm','candidate/main.wasm','baseline/plugin.cmxs','candidate/plugin.cmxs','map/baseline/main.wasm','map/candidate/main.wasm','map/baseline/plugin.cmxs','map/candidate/plugin.cmxs']
meta=lambda names:{name:{'sha256':sha(root/name),'bytes':(root/name).stat().st_size} for name in names}
manifest={'root':str(root),'accepted_commit':commit,'files':meta(files),'generated_artifacts':meta(binaries),'archive_files':files+['artifact-manifest.json']}
(root/'artifact-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'{len(files)} archived files, {sum(d["bytes"] for d in manifest["files"].values()):,} bytes; {len(binaries)} generated binaries recorded separately.')
