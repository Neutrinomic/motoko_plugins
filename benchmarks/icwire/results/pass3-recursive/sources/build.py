#!/usr/bin/env python3
"""Freeze codec benchmark inputs, then compile with one fixed compiler and RTS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

here = Path(__file__).resolve().parent
root = here.parent.parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('label')
p.add_argument('--bundle', type=Path, default=Path('/home/devbox/.local/lib/motoko-compute'))
p.add_argument('--plugin', type=Path, default=root / 'dist/icwire')
p.add_argument('--plugin-source', type=Path, default=root / 'plugins/icwire')
p.add_argument('--candidx-plugin', type=Path, default=root / 'dist/candidx')
p.add_argument('--baseline-only', action='store_true')
p.add_argument('--recursive', action='store_true')
p.add_argument('--codec', choices=['all', 'candid', 'candidx', 'icwire'], default='all')
a = p.parse_args()
if not a.label.replace('-', '').replace('_', '').isalnum():
    p.error('label must contain only letters, digits, dashes and underscores')
out = here / 'results' / a.label
if out.exists():
    p.error(f'archive already exists: {out}')
out.mkdir(parents=True)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()

try:
    sources = out / 'sources'
    sources.mkdir()
    generator_args = [sys.executable, str(here / 'generate.py'), '--out', str(sources)]
    if a.baseline_only:
        generator_args.append('--baseline-only')
    if a.recursive:
        generator_args.append('--recursive')
    if a.codec != 'all':
        generator_args += ['--codec', a.codec]
    subprocess.run(generator_args, check=True)
    for filename in ['generate.py', 'build.py', 'summarize.py']:
        shutil.copy2(here / filename, sources / filename)
    shutil.copy2(root / 'benchmarks/run.mjs', sources / 'run.mjs')
    plugins = [('candidx', a.candidx_plugin)] if a.codec in ['all', 'candidx'] else []
    if not a.baseline_only and a.codec in ['all', 'icwire']:
        plugins.append(('icwire', a.plugin))
    plugin_args = []
    fast = sources / 'fast'
    fast.mkdir()
    for name, directory in plugins:
        target = out / 'dist' / name
        shutil.copytree(directory, target)
        manifest = json.loads((target / 'build.json').read_text())
        for relative, expected in manifest['sha256'].items():
            if sha(target / relative) != expected:
                raise RuntimeError(f'plugin artifact hash mismatch: {target / relative}')
        source = a.plugin_source if name == 'icwire' else root / 'plugins' / name
        destination = sources / 'plugins' / name
        shutil.copytree(source, destination, ignore=shutil.ignore_patterns('_out', 'ok'))
        for relative, expected in manifest['source_sha256'].items():
            if relative.startswith(f'plugins/{name}/'):
                candidate = sources / relative
                if sha(candidate) != expected:
                    raise RuntimeError(f'plugin source does not match binary: {relative}')
        module = {'candidx': 'CandidX.mo', 'icwire': 'ICWire.mo'}[name]
        shutil.copy2(root / 'packages/fast/src' / module, fast / module)
        plugin_args += ['--plugin', str(target)]

    bundle = a.bundle.resolve()
    toolchain = [bundle / name for name in ['moc', 'mo-rts.wasm', 'mo-rts-debug.wasm']]
    before = {str(path): sha(path) for path in toolchain}
    frozen = {str(path): sha(path) for path in out.rglob('*') if path.is_file()}
    env = dict(os.environ, MOC_RELEASE_RTS=str(bundle / 'mo-rts.wasm'),
               MOC_DEBUG_RTS=str(bundle / 'mo-rts-debug.wasm'))
    command = [str(bundle / 'moc'), *plugin_args, '--package', 'fast', str(fast),
               str(sources / 'main.mo'), '-o', str(out / 'main.wasm')]
    subprocess.run(command, env=env, check=True)
    for filename, expected in {**before, **frozen}.items():
        if sha(Path(filename)) != expected:
            raise RuntimeError(f'build input changed during compilation: {filename}')
    report = {'label': a.label, 'command': command,
              'compiler_version': subprocess.check_output([str(bundle / 'moc'), '--version'], env=env, text=True).strip(),
              'rts_environment': {key: env[key] for key in ['MOC_RELEASE_RTS', 'MOC_DEBUG_RTS']},
              'toolchain_sha256': before,
              'archive_sha256': {str(path.relative_to(out)): sha(path) for path in sorted(out.rglob('*')) if path.is_file()}}
    (out / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
except BaseException:
    print(f'Incomplete archive retained for inspection: {out}', file=sys.stderr)
    raise
print(out)
