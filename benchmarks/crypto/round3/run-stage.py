#!/usr/bin/env python3
"""Build and measure one immutable signature round-three cohort."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent
BASELINE = Path('/srv/shared/code/motoko_experiments/plugins/_build/signature-round3/baseline')
INSTALLED_MOC = Path('/home/devbox/.local/lib/motoko-compute/moc')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage', required=True, help='Unique name; round3- is added automatically')
    p.add_argument('--baseline', type=Path, default=BASELINE)
    p.add_argument('--root', type=Path, help='Candidate root; defaults to the frozen baseline')
    p.add_argument('--plugin', action='append', default=[], help='Artifacts taken from --root; repeatable')
    p.add_argument('--manifest', type=Path, default=BENCH/'all-cases.json')
    p.add_argument('--family', default='.', help='Regex on family')
    p.add_argument('--filter', default='.')
    p.add_argument('--implementation', default='.')
    p.add_argument('--include-mops', action='store_true', help='Include pure Motoko comparison fixtures')
    p.add_argument('--compile-only', action='store_true')
    p.add_argument('--moc', type=Path, default=INSTALLED_MOC, help='Executable with the frozen compiler hash')
    p.add_argument('--server', type=Path, default=Path('/home/devbox/.local/bin/pocket-ic'))
    p.add_argument('--sdk-package', type=Path, default=Path('/srv/shared/code/candidx/ts/package.json'))
    a = p.parse_args()
    assert re.fullmatch(r'[a-zA-Z0-9_-]+', a.stage), 'Unsafe stage name'
    stage = a.stage if a.stage.startswith('round3-') else 'round3-'+a.stage
    directory = BENCH/'results'/stage
    assert not directory.exists(), 'Stage already exists; use a new name'
    baseline = a.baseline.resolve()
    root = (a.root or baseline).resolve()
    moc = a.moc.resolve()
    frozen = json.loads((baseline/'baseline.json').read_text())
    assert sha(baseline/'baseline.json') == sha(HERE/'baseline.json'), 'Baseline manifest differs from round-three pins'
    for name, digest in frozen['sha256'].items():
        assert not Path(name).is_absolute() and '..' not in Path(name).parts, 'Unsafe baseline path'
        assert sha(baseline/name) == digest, 'Delivered baseline changed: '+name
    assert sha(moc) == frozen['sha256']['toolchain/moc'], 'Installed compiler differs from frozen baseline'
    manifest = json.loads(a.manifest.read_text())
    cases = manifest['cases'] if isinstance(manifest, dict) else manifest
    cases = [c for c in cases if (a.include_mops or c.get('plugins'))
             and re.search(a.family, c['family']) and re.search(a.filter, c['name'])
             and re.search(a.implementation, c['implementation'])]
    assert cases, 'No cases selected'
    plugins = sorted({plugin for case in cases for plugin in case.get('plugins', [])})
    assert set(a.plugin) <= set(plugins), 'Requested plugin not used by cohort'
    assert root == baseline or a.plugin or not plugins, 'Candidate root requires explicit --plugin overrides'
    roots = {plugin: str(root if plugin in a.plugin else baseline) for plugin in plugins}
    config = HERE/'stage-manifests'
    config.mkdir(exist_ok=True)
    manifest_path = config/(stage+'.json')
    roots_path = config/(stage+'-roots.json')
    for path, value in [(manifest_path, {'cases': cases}), (roots_path, roots)]:
        with path.open('x') as output:
            output.write(json.dumps(value, indent=2)+'\n')
    protocol_hashes = {name: sha(HERE/name) for name in ['run-stage.py', 'build.py', 'run.mjs', 'common.py', 'compare.py']}
    subprocess.run([sys.executable, str(HERE/'build.py'), '--stage', stage,
                    '--manifest', str(manifest_path), '--plugin-roots', str(roots_path),
                    '--fast-root', str(root/'packages/fast/src'), '--bundle', str(baseline/'toolchain'),
                    '--moc', str(moc)], check=True)
    build_path = directory/'build.json'
    build = json.loads(build_path.read_text())
    assert build['complete'] and all(c['returncode'] == 0 for c in build['cases']), 'Compilation failed; inspect stage logs'
    assert protocol_hashes == {name: sha(HERE/name) for name in protocol_hashes}, 'Protocol changed during build'
    metadata = {
        'baseline_manifest_sha256': sha(baseline/'baseline.json'), 'baseline_root': str(baseline),
        'candidate_root': str(root), 'plugin_overrides': a.plugin,
        'selected_manifest_sha256': sha(manifest_path), 'protocol_sha256': protocol_hashes,
        'methodology': 'Three fresh-canister trials; exact output checks; immutable source, compiler, RTS and plugin snapshots.',
    }
    with (directory/'round3.json').open('x') as output:
        output.write(json.dumps(metadata, indent=2)+'\n')
    if not a.compile_only:
        runner = directory/'inputs/benchmarks/crypto/round3/run.mjs'
        subprocess.run(['node', str(runner), '--build', str(build_path), '--out', str(directory/'results.json'),
                        '--trials', '3', '--server', str(a.server), '--sdk-package', str(a.sdk_package)], check=True)
    print(directory)


if __name__ == '__main__':
    main()
