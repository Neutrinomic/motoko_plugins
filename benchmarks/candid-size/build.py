#!/usr/bin/env python3
"""Compile against an explicit compiler/RTS bundle, without changing local tools."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bundle', type=Path, required=True, help='Directory containing moc and mo-rts{,-debug}.wasm')
args = parser.parse_args()
here = Path(__file__).resolve().parent
root = here.parent.parent
bundle = args.bundle.resolve()
out = here / '_out'
out.mkdir(exist_ok=True)
env = dict(os.environ, MOC_RELEASE_RTS=str(bundle / 'mo-rts.wasm'),
           MOC_DEBUG_RTS=str(bundle / 'mo-rts-debug.wasm'))
command = [str(bundle / 'moc'), '--plugin', str(root / 'dist/candidx'),
           '--package', 'fast', str(root / 'packages/fast/src'), str(here / 'main.mo'),
           '-o', str(out / 'main.wasm')]
subprocess.run(command, env=env, check=True)
hash_file = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
paths = [Path(__file__), here / 'main.mo', here / 'run.mjs',
         root / 'packages/fast/src/CandidX.mo', root / 'dist/candidx/plugin.cmxs',
         root / 'dist/candidx/runtime.wasm', root / 'dist/candidx/build.json',
         bundle / 'moc', bundle / 'mo-rts.wasm', bundle / 'mo-rts-debug.wasm', out / 'main.wasm']
plugin_build = json.loads((root / 'dist/candidx/build.json').read_text())
report = {'command': command, 'cwd': str(Path.cwd()),
          'rts_environment': {key: env[key] for key in ('MOC_RELEASE_RTS', 'MOC_DEBUG_RTS')},
          'compiler_version': subprocess.check_output([str(bundle / 'moc'), '--version'], env=env, text=True).strip(),
          'compiler_revision': plugin_build['motoko_revision'],
          'compiler_plugin_build_moc_sha256': plugin_build['moc_sha256'],
          'sha256': {str(path): hash_file(path) for path in paths}}
(here / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
