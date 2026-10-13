#!/usr/bin/env python3
"""Compile at fixed paths and archive immutable round-two source/binary evidence."""
import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--bundle', type=Path, default=Path('/home/devbox/.local/lib/motoko-compute'))
p.add_argument('--core', type=Path, default=Path('/srv/shared/code/takt/.mops/core@2.6.2/src'))
p.add_argument('--stage', required=True)
p.add_argument('--plugin-root', type=Path, required=True)
a = p.parse_args()
assert a.stage and Path(a.stage).name == a.stage and a.stage not in ('.', '..')
here = Path(__file__).resolve().parent
root = here.parents[2]
out = here / '_out'
out.mkdir(exist_ok=True)
archive = here / 'results' / a.stage
assert not archive.exists(), f'Immutable stage already exists: {archive}'
bundle = a.bundle.resolve()
core = a.core.resolve()
plugin_root = a.plugin_root.resolve()
env = dict(os.environ, MOC_RELEASE_RTS=str(bundle / 'mo-rts.wasm'), MOC_DEBUG_RTS=str(bundle / 'mo-rts-debug.wasm'))
command = [str(bundle / 'moc'), '--plugin', str(plugin_root / 'dist/history-ring'), '--package', 'fast', str(root / 'packages/fast/src'), '--package', 'core', str(core), str(here / 'main.mo'), '-o', str(out / 'main.wasm')]
inputs = [Path(__file__), here / 'main.mo', here / 'run.mjs', root / 'packages/fast/src/HistoryRing.mo', bundle / 'moc', bundle / 'mo-rts.wasm', bundle / 'mo-rts-debug.wasm']
inputs += sorted((plugin_root / 'plugins/history-ring').rglob('*.ml'))
inputs += sorted((plugin_root / 'plugins/history-ring').glob('plugin.json'))
inputs += sorted(path for path in (plugin_root / 'dist/history-ring').glob('*') if path.is_file())
inputs += sorted(core.rglob('*.mo'))
hash_file = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
before = {str(path): hash_file(path) for path in inputs}
plugin_build = json.loads((plugin_root / 'dist/history-ring/build.json').read_text())
for name, expected in plugin_build['sha256'].items():
    assert hash_file(plugin_root / 'dist/history-ring' / name) == expected, f'Plugin artifact mismatch: {name}'
for relative, expected in plugin_build['source_sha256'].items():
    if relative.startswith('plugins/history-ring/'):
        assert hash_file(plugin_root / relative) == expected, f'Plugin binary/source mismatch: {relative}'
subprocess.run(command, env=env, check=True)
assert before == {str(path): hash_file(path) for path in inputs}, 'Build inputs changed during compilation'
archive.mkdir(parents=True)
report = {'stage': a.stage, 'command': command, 'rts_environment': {k: env[k] for k in ['MOC_RELEASE_RTS', 'MOC_DEBUG_RTS']}, 'compiler_version': subprocess.check_output([str(bundle / 'moc'), '--version'], text=True, env=env).strip(), 'sha256': {**before, str(out / 'main.wasm'): hash_file(out / 'main.wasm')}, 'archive': {}}
# Do not reproduce the ignored _out/private-stage path inside tracked evidence.
for path in inputs + [out / 'main.wasm']:
    if path == out / 'main.wasm':
        relative = Path('artifacts/main.wasm.archive')
    elif path.is_relative_to(plugin_root / 'dist/history-ring'):
        relative = Path('artifacts') / (path.name + '.archive')
    elif path.is_relative_to(plugin_root / 'plugins/history-ring'):
        relative = Path('plugin') / path.relative_to(plugin_root / 'plugins/history-ring')
    elif path.is_relative_to(here):
        relative = Path('harness') / path.relative_to(here)
    elif path == root / 'packages/fast/src/HistoryRing.mo':
        relative = Path('module/HistoryRing.mo')
    else:
        continue
    target = archive / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(path.read_bytes())
    assert hash_file(target) == report['sha256'][str(path)], f'Archive mismatch: {path}'
    report['archive'][str(relative)] = {'source': str(path), 'sha256': hash_file(target)}
(archive / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
print(archive)
