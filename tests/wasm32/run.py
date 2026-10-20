#!/usr/bin/env python3
"""Compile and execute the five RRT plugins on both Tripwire memory targets."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--motoko', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--compiler', type=Path)
parser.add_argument('--core', type=Path, default=Path.home() /
                    '.cache/mops/packages/core@2.6.2/src')
args = parser.parse_args()
sdk, output = args.motoko.resolve(), args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
compiler = args.compiler.absolute() if args.compiler else sdk / 'bin/tripwire'
env = os.environ.copy()
env['MOC_RELEASE_RTS'] = str(sdk / 'rts/mo-rts.wasm')
env['MOC_DEBUG_RTS'] = str(sdk / 'rts/mo-rts-debug.wasm')
plugins = ['icwire', 'mutable-map', 'queue', 'history-ring', 'sha256']
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
inputs = [compiler, sdk / 'src/_build/default/exes/moc.exe',
          Path(env['MOC_RELEASE_RTS']), Path(env['MOC_DEBUG_RTS'])]
inputs += [p for p in HERE.iterdir() if p.is_file()]
inputs += list((ROOT / 'packages/fast/src').rglob('*.mo'))
inputs += list(args.core.resolve().rglob('*.mo'))
for name in plugins:
    inputs += [p for p in (ROOT / 'dist' / name).iterdir() if p.is_file()]
pins = {str(path): digest(path) for path in sorted(set(inputs))}
report = {'passed': False, 'inputs': pins, 'processes': [], 'artifacts': {},
          'scope': 'Five RRT plugins; two memory targets and codec policies.'}


def save():
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


def run(name, command, runtime_env=env):
    result = subprocess.run(list(map(str, command)), env=runtime_env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = output / f'{name}.stdout', output / f'{name}.stderr'
    stdout.write_bytes(result.stdout)
    stderr.write_bytes(result.stderr)
    report['processes'].append({'name': name, 'command': list(map(str, command)),
        'returncode': result.returncode, 'stdout': stdout.name,
        'stderr': stderr.name, 'stdoutSha256': digest(stdout),
        'stderrSha256': digest(stderr)})
    save()
    if result.returncode:
        raise RuntimeError(f'{name} exited {result.returncode}: {stderr}')
    return result.stdout.decode(errors='replace')


try:
    run('compiler-version', [compiler, '--version'])
    base = [compiler, '--package', 'core', args.core.resolve(), '--package',
            'fast', ROOT / 'packages/fast/src', '--enhanced-orthogonal-persistence',
            '--icwire-internal', '--trap-on-candid', '--force-gc', '-Werror', '-g']
    for name in plugins:
        base += ['--plugin', ROOT / 'dist' / name]
    for policy in ['speed', 'compact']:
        for target in ['default32', 'wasm64']:
            name = f'{target}-{policy}'
            wasm = output / f'{name}.wasm'
            flags = [] if target == 'default32' else ['--wasm64']
            run(name, [*base, *flags, '--icwire-opt', policy,
                       '-o', wasm, HERE / 'runtime.mo'])
            run(name + '-validate', ['wasm-validate', '--enable-memory64', wasm])
            sections = run(name + '-sections', ['wasm-objdump', '-x', wasm])
            memory = [line.strip() for line in sections.splitlines()
                      if 'memory[' in line and 'pages:' in line]
            table = [line.strip() for line in sections.splitlines()
                     if 'table[' in line and 'funcref' in line]
            if len(memory) != 1 or len(table) != 1:
                raise AssertionError(f'{name}: unexpected memory/table {memory}/{table}')
            expected64 = target == 'wasm64'
            if ('i64' in memory[0]) != expected64:
                raise AssertionError(f'{name}: incorrect memory type {memory}')
            if ('i64' in table[0]) != expected64:
                raise AssertionError(f'{name}: incorrect table type {table}')
            if not expected64:
                run(name + '-memory32-validate', ['wasm-validate', wasm])
            report['artifacts'][name] = {'file': wasm.name, 'bytes': wasm.stat().st_size,
                'sha256': digest(wasm), 'memory': memory, 'table': table}
            save()
    explicit = output / 'explicit32-speed.wasm'
    run('explicit32-speed', [*base, '--wasm32', '--icwire-opt', 'speed',
                            '-o', explicit, HERE / 'runtime.mo'])
    assert explicit.read_bytes() == (output / 'default32-speed.wasm').read_bytes()
    report['defaultEqualsExplicit32'] = True
    runtime_env = env.copy()
    runtime_env['TRIPWIRE_PLUGIN_WASM32_OUTPUT'] = str(output)
    run('pocket-ic', ['node', HERE / 'runtime.mjs'], runtime_env)
    runtime = json.loads((output / 'runtime-results.json').read_text())
    assert runtime['passed'] is True
    report['runtime'] = {'checks': len(runtime['checks']), 'calls': len(runtime['calls']),
                         'sha256': digest(output / 'runtime-results.json')}
    for path, pin in pins.items():
        if digest(Path(path)) != pin:
            raise AssertionError(f'Input changed during test: {path}')
    report['passed'] = True
    save()
    print(json.dumps({'passed': True, 'summary': str(output / 'summary.json'),
                      'runtime': report['runtime']}, indent=2))
except BaseException as error:
    report['error'] = str(error)
    save()
    raise
