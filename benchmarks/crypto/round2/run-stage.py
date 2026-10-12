#!/usr/bin/env python3
"""Build and measure one immutable round-two cohort with the round-one protocol."""
import argparse, hashlib, importlib.util, json, re, shutil, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent
ROOT = BENCH.parents[1]
BASELINE = ROOT / '_build/crypto-optimization-round2/baseline'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--stage', required=True, help='Unique name; round2- is added automatically')
p.add_argument('--root', type=Path, default=BASELINE, help='Frozen candidate root, or delivered baseline')
p.add_argument('--plugin', action='append', default=[], help='Only these artifacts come from --root; repeatable')
p.add_argument('--manifest', type=Path, default=BENCH/'all-cases.json')
p.add_argument('--family', default='.', help='Regex on family, not name')
p.add_argument('--filter', default='.')
p.add_argument('--implementation', default='.')
p.add_argument('--include-mops', action='store_true', help='Include pure Motoko rows for full API comparison')
p.add_argument('--compile-only', action='store_true')
a = p.parse_args()
assert re.fullmatch(r'[a-zA-Z0-9_-]+', a.stage), 'Unsafe stage name'
stage = a.stage if a.stage.startswith('round2-') else 'round2-'+a.stage
assert not (BENCH/'results'/stage).exists(), 'Stage already exists; use a new name'
root = a.root.resolve()
frozen = json.loads((BASELINE/'baseline.json').read_text())
for name, digest in frozen['sha256'].items():
    assert sha(BASELINE/name) == digest, 'Delivered baseline changed: '+name
manifest = json.loads(a.manifest.read_text())
cases = manifest['cases'] if isinstance(manifest, dict) else manifest
cases = [c for c in cases if (a.include_mops or c.get('plugins')) and re.search(a.family,c['family']) and re.search(a.filter,c['name']) and re.search(a.implementation,c['implementation'])]
assert cases, 'No native cases selected'
plugins = sorted({plugin for case in cases for plugin in case['plugins']})
assert set(a.plugin) <= set(plugins), 'Requested plugin not used by cohort'
assert root == BASELINE or a.plugin or a.family == '^bitcoin$', 'Candidate root requires explicit --plugin overrides (or Bitcoin-only source changes)'
roots = {plugin:str(root if plugin in a.plugin else BASELINE) for plugin in plugins}
config = HERE/'stage-manifests'
config.mkdir(exist_ok=True)
manifest_path = config/(stage+'.json')
roots_path = config/(stage+'-roots.json')
manifest_path.write_text(json.dumps({'cases':cases},indent=2)+'\n')
roots_path.write_text(json.dumps(roots,indent=2)+'\n')
spec=importlib.util.spec_from_file_location('capture_oracles',HERE/'capture-oracles.py')
capture=importlib.util.module_from_spec(spec);spec.loader.exec_module(capture)
oracle_temporary=ROOT/'_build/crypto-optimization-round2'/('oracle-'+stage)
oracle_metadata=capture.capture(oracle_temporary,'before compilation and measurement')
subprocess.run([sys.executable,str(BENCH/'build.py'),'--stage',stage,'--manifest',str(manifest_path),'--plugin-roots',str(roots_path),'--fast-root',str(root/'packages/fast/src')],check=True)
build_path = BENCH/'results'/stage/'build.json'
build = json.loads(build_path.read_text())
assert build['complete'] and all(c['returncode']==0 for c in build['cases']), 'Compilation failed; inspect stage logs'
metadata = {'baseline_manifest_sha256':sha(BASELINE/'baseline.json'),'baseline_root':str(BASELINE),'candidate_root':str(root),'plugin_overrides':a.plugin,'selected_manifest_sha256':sha(manifest_path),'wrapper_sha256':sha(Path(__file__)),'protocol_build_sha256':sha(BENCH/'build.py'),'protocol_run_sha256':sha(BENCH/'run.mjs')}
(build_path.parent/'round2.json').write_text(json.dumps(metadata,indent=2)+'\n')
shutil.move(str(oracle_temporary),str(build_path.parent/'inputs/benchmark-oracles'))
(build_path.parent/'oracle-provenance.json').write_text(json.dumps(oracle_metadata,indent=2)+'\n')
if not a.compile_only:
    subprocess.run(['node',str(BENCH/'run.mjs'),'--build',str(build_path),'--out',str(build_path.parent/'results.json'),'--trials','3'],check=True)
print(build_path.parent)
