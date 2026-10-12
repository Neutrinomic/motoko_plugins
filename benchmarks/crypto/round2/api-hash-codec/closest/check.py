#!/usr/bin/env python3
"""Compile only the additional closest-code actors against pinned Mops."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[2]
BUNDLE = Path('/home/devbox/.local/lib/motoko-compute')
args = [str(BUNDLE/'moc')]
for alias, version in json.loads((BENCH/'dependencies/mops.lock').read_text())['deps'].items():
    args += ['--package', alias, str(BENCH/'dependencies/.mops'/(alias.split('@')[0]+'@'+version)/'src')]
env = dict(os.environ, MOC_RELEASE_RTS=str(BUNDLE/'mo-rts.wasm'), MOC_DEBUG_RTS=str(BUNDLE/'mo-rts-debug.wasm'))
results = []
for case in json.loads((HERE/'cases.json').read_text())['cases']:
    target = HERE/'compile-checks'/case['name']/case['implementation']
    target.mkdir(parents=True, exist_ok=True)
    command = args+[str(BENCH/case['source']), '-o', str(target/'main.wasm')]
    result = subprocess.run(command, env=env, text=True, capture_output=True)
    (target/'compile.log').write_text(result.stdout+result.stderr)
    results.append(dict(name=case['name'], implementation=case['implementation'],
                        returncode=result.returncode, command=command,
                        source_sha256=hashlib.sha256((BENCH/case['source']).read_bytes()).hexdigest(),
                        compile_log=(target/'compile.log').relative_to(HERE).as_posix()))
    print(case['name'], case['implementation'], result.returncode, flush=True)
(HERE/'compile-checks.json').write_text(json.dumps({'cases': results}, indent=2)+'\n')
assert all(c['returncode'] == 0 for c in results), 'Inspect compile logs'
