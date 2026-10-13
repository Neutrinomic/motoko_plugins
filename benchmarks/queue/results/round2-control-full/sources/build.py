#!/usr/bin/env python3
"""Freeze and build a Queue benchmark variant using fixed compiler/RTS paths."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

here = Path(__file__).resolve().parent
root = here.parent.parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('label')
p.add_argument('--bundle', type=Path, default=Path('/home/devbox/.local/lib/motoko-compute'))
p.add_argument('--core', type=Path, default=Path('/srv/shared/code/takt/.mops/core@2.6.2/src'))
p.add_argument('--plugin-dir', type=Path, default=root / 'dist/queue')
p.add_argument('--plugin-source', type=Path, default=root / 'plugins/queue')
p.add_argument('--module', type=Path, default=root / 'packages/fast/src/Queue.mo')
a = p.parse_args()
if not a.label.replace('-', '').replace('_', '').isalnum():
    p.error('label must contain only letters, digits, dashes and underscores')
out = here / 'results' / a.label
if out.exists():
    p.error(f'archive exists: {out}')
stage = here / '_out' / 'stage'
stage.mkdir(parents=True, exist_ok=True)
(stage / 'fast').mkdir(exist_ok=True)
shutil.copy2(here / 'main.mo', stage / 'main.mo')
shutil.copy2(a.module, stage / 'fast/Queue.mo')
for name, source in [('plugin', a.plugin_dir), ('plugin-source', a.plugin_source)]:
    dest = stage / name
    if dest.exists(): shutil.rmtree(dest)
    shutil.copytree(source, dest, ignore=shutil.ignore_patterns('_out'))
hash_file = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
plugin_build = json.loads((stage / 'plugin/build.json').read_text())
for path, expected in plugin_build['source_sha256'].items():
    if path.startswith('plugins/queue/'):
        source = stage / 'plugin-source' / path.removeprefix('plugins/queue/')
        assert hash_file(source) == expected, f'plugin source does not match plugin binary build: {source}'
for path, expected in plugin_build['sha256'].items():
    assert hash_file(stage / 'plugin' / path) == expected, f'plugin binary build hash mismatch: {path}'
bundle = a.bundle.resolve()
core = a.core.resolve()
env = dict(os.environ, MOC_RELEASE_RTS=str(bundle / 'mo-rts.wasm'), MOC_DEBUG_RTS=str(bundle / 'mo-rts-debug.wasm'))
inputs = [bundle / 'moc', bundle / 'mo-rts.wasm', bundle / 'mo-rts-debug.wasm']
input_hashes = {str(file): hash_file(file) for file in inputs}
stage_hashes = {str(file): hash_file(file) for file in stage.rglob('*') if file.is_file() and file.suffix != '.wasm'}
core_digest = hashlib.sha256()
for file in sorted(core.rglob('*.mo')):
    core_digest.update(str(file.relative_to(core)).encode() + b'\0' + file.read_bytes())
core_before = core_digest.hexdigest()
command = [str(bundle / 'moc'), '--plugin', str(stage / 'plugin'), '--package', 'fast', str(stage / 'fast'),
           '--package', 'core', str(core), str(stage / 'main.mo'), '-o', str(stage / 'main.wasm')]
subprocess.run(command, env=env, check=True)
for path, expected in {**input_hashes, **stage_hashes}.items():
    assert hash_file(Path(path)) == expected, f'build input changed during compilation: {path}'
out.mkdir(parents=True)
shutil.copy2(stage / 'main.wasm', out / 'main.wasm')
for source, dest in [(stage / 'main.mo', out / 'sources/main.mo'), (here / 'run.mjs', out / 'sources/run.mjs'),
                     (here / 'build.py', out / 'sources/build.py'),
                     (stage / 'fast/Queue.mo', out / 'sources/Queue.mo')]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)
shutil.copytree(stage / 'plugin-source', out / 'sources/plugin')
shutil.copytree(stage / 'plugin', out / 'dist')
core_digest = hashlib.sha256()
for file in sorted(core.rglob('*.mo')):
    core_digest.update(str(file.relative_to(core)).encode() + b'\0' + file.read_bytes())
assert core_digest.hexdigest() == core_before, "core sources changed during compilation"
report = {'label': a.label, 'command': command,
          'compiler_version': subprocess.check_output([str(bundle / 'moc'), '--version'], env=env, text=True).strip(),
          'rts_environment': {key: env[key] for key in ['MOC_RELEASE_RTS', 'MOC_DEBUG_RTS']},
          'core_source_sha256': core_digest.hexdigest(), 'toolchain_sha256': input_hashes,
          'archive_sha256': {str(file.relative_to(out)): hash_file(file) for file in sorted(out.rglob('*')) if file.is_file()}}
(out / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
print(out)
