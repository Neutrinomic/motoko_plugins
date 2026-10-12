#!/usr/bin/env python3
"""Compile the new self-contained actors, without creating benchmark stages."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
ROOT = BENCH.parents[1]
BASELINE = ROOT/'_build/crypto-optimization-round2/baseline'
BUNDLE = Path('/home/devbox/.local/lib/motoko-compute')
lock = json.loads((BENCH/'dependencies/mops.lock').read_text())
args = [str(BUNDLE/'moc')]
for alias, version in lock['deps'].items():
    args += ['--package', alias, str(BENCH/'dependencies/.mops'/(alias.split('@')[0]+'@'+version)/'src')]
args += ['--package', 'fast', str(BASELINE/'packages/fast/src')]
env = dict(os.environ, MOC_RELEASE_RTS=str(BUNDLE/'mo-rts.wasm'), MOC_DEBUG_RTS=str(BUNDLE/'mo-rts-debug.wasm'))
results = []
previous_path = HERE/'compile-checks.json'
previous = {(c['name'], c['implementation']): c for c in json.loads(previous_path.read_text())['cases']} if previous_path.exists() else {}
for case in json.loads((HERE/'cases.json').read_text())['cases']:
    target = HERE/'compile-checks'/case['name']/case['implementation']
    target.mkdir(parents=True, exist_ok=True)
    command = args[:]
    for plugin in case['plugins']:
        command += ['--plugin', str(BASELINE/'dist'/plugin)]
    command += [str(BENCH/case['source']), '-o', str(target/'main.wasm')]
    source_sha256 = hashlib.sha256((BENCH/case['source']).read_bytes()).hexdigest()
    old = previous.get((case['name'], case['implementation']))
    if old and old['source_sha256'] == source_sha256 and old['returncode'] == 0 and old['command'] == command and (target/'main.wasm').exists():
        results.append(old)
        continue
    result = subprocess.run(command, env=env, text=True, capture_output=True)
    (target/'compile.log').write_text(result.stdout+result.stderr)
    results.append(dict(name=case['name'], implementation=case['implementation'], returncode=result.returncode,
                        source_sha256=source_sha256,
                        compile_log=str((target/'compile.log').relative_to(HERE)), command=command))
    print(case['name'], case['implementation'], result.returncode, flush=True)
(HERE/'compile-checks.json').write_text(json.dumps({'cases': results}, indent=2)+'\n')
assert all(case['returncode'] == 0 for case in results), 'Inspect compile-checks.json and logs'
