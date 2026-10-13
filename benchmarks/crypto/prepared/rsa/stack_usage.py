#!/usr/bin/env python3
"""Bound the RSA runtime's linear-memory stack from its actual Wasm call graph.

This is a deliberately strict artifact check for clang's fixed-frame prologue,
not a general Wasm analyzer. Unknown stack-pointer writes, indirect calls or
recursion fail closed. Motoko caller frames and the engine value stack are not
included in the native-chain bound.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--runtime', type=Path, required=True)
p.add_argument('--wasm2wat', required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
wat = subprocess.check_output([a.wasm2wat, '--enable-memory64', str(a.runtime)], text=True)
assert not re.search(r'\b(call_indirect|call_ref|return_call|return_call_indirect|return_call_ref)\b', wat), 'Unsupported call form'
sections = list(re.finditer(r'^  \((func|global|export|data|elem|table|memory|start)\b', wat, re.M))
functions = {}
for index, start in enumerate(sections):
    if start[1] != 'func':
        continue
    stop = sections[index+1].start() if index+1 < len(sections) else len(wat)
    body = wat[start.start():stop]
    name = re.match(r'  \(func (\$[^\s()]+)', body)[1]
    allocation = list(re.finditer(r'global.get \$__stack_pointer\s+i64.const (\d+)\s+i64.sub\s+local.tee (\d+)\s+global.set \$__stack_pointer', body))
    writes = len(re.findall(r'global.set \$__stack_pointer', body))
    if allocation:
        assert len(allocation) == 1, f'Multiple stack allocations: {name}'
        frame, local = map(int, allocation[0].groups())
        restore = re.findall(rf'local.get {local}\s+i64.const {frame}\s+i64.add\s+global.set \$__stack_pointer', body)
        assert len(restore) == 1 and writes == 2, f'Unknown stack update: {name}'
    else:
        assert writes == 0, f'Unrecognized stack frame: {name}'
        frame = 0
    functions[name] = {'frame_bytes': frame, 'calls': sorted(set(re.findall(r'\bcall (\$[^\s()]+)', body)))}

memo = {}
def bound(name, visiting=()):
    assert name in functions, f'Unaccounted imported call: {name}'
    assert name not in visiting, f'Recursion: {visiting + (name,)}'
    if name not in memo:
        own = functions[name]
        children = [bound(child, visiting + (name,)) for child in own['calls']]
        child = max(children, key=lambda x: x[0]) if children else (0, [])
        memo[name] = (own['frame_bytes'] + child[0], [name] + child[1])
    return memo[name]

exports = {}
for name, target in re.findall(r'\(export "([^"\n]+)" \(func (\$[^\s()]+)\)\)', wat):
    total, path = bound(target)
    exports[name] = {'native_chain_bytes_upper_bound': total, 'maximum_path': path}
assert exports, 'No runtime exports found'
report = {
    'runtime_sha256': hashlib.sha256(a.runtime.read_bytes()).hexdigest(),
    'wasm2wat_sha256': hashlib.sha256(Path(a.wasm2wat).read_bytes()).hexdigest(),
    'compiler_stack_reserve_bytes': 4 * 1024 * 1024,
    'scope': 'Conservative fixed native frame sum along acyclic direct calls. Excludes caller Motoko frames and engine value stack; no recursion or indirect calls. Not a whole-canister peak measurement.',
    'exports': exports, 'functions': functions,
}
a.out.parent.mkdir(parents=True, exist_ok=True)
with a.out.open('x') as output:
    output.write(json.dumps(report, indent=2) + '\n')
print(max(x['native_chain_bytes_upper_bound'] for x in exports.values()))
