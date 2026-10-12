#!/usr/bin/env python3
"""Compile only: the parent benchmark harness owns execution and timing."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import os
import subprocess

HERE = Path(__file__).resolve().parent
CRYPTO = HERE.parents[2]
ROOT = CRYPTO.parents[1]
BASELINE = ROOT / '_build/crypto-optimization-round2/baseline'
BUNDLE = Path('/home/devbox/.local/lib/motoko-compute')
lock = json.loads((CRYPTO / 'dependencies/mops.lock').read_text())
args = []
for alias, version in lock['deps'].items():
    package = f'{alias.split("@")[0]}@{version}'
    args += ['--package', alias, str(CRYPTO / 'dependencies/.mops' / package / 'src')]
args += ['--package', 'fast', str(BASELINE / 'packages/fast/src')]
env = dict(os.environ, MOC_RELEASE_RTS=str(BUNDLE / 'mo-rts.wasm'),
           MOC_DEBUG_RTS=str(BUNDLE / 'mo-rts-debug.wasm'))

def check(case):
    dest = HERE / 'compile-checks' / case['name'] / case['implementation']
    dest.mkdir(parents=True, exist_ok=True)
    command = [str(BUNDLE / 'moc'), *args]
    for plugin in case['plugins']:
        command += ['--plugin', str(BASELINE / 'dist' / plugin)]
    source = CRYPTO / case['source']
    command += [str(source), '-o', str(dest / 'main.wasm')]
    result = subprocess.run(command, env=env, capture_output=True, text=True)
    (dest / 'compile.log').write_text(result.stdout + result.stderr)
    return {'name': case['name'], 'implementation': case['implementation'],
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'returncode': result.returncode, 'command': command,
            'compile_log': str((dest / 'compile.log').relative_to(HERE))}

with ThreadPoolExecutor(max_workers=4) as executor:
    results = list(executor.map(check, json.loads((HERE / 'cases.json').read_text())['cases']))
(HERE / 'compile-checks.json').write_text(json.dumps({'cases': results}, indent=2) + '\n')
failed = [r for r in results if r['returncode']]
for result in failed:
    print(result['name'], result['implementation'])
    print((HERE / result['compile_log']).read_text())
print(f'{len(results) - len(failed)}/{len(results)} fixtures compile')
raise SystemExit(bool(failed))
