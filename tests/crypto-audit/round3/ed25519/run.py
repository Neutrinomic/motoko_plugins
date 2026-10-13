#!/usr/bin/env python3
"""Run the independent Ed25519 audit inside the compiler Nix environment.

Build dist/ed25519 first. This runner does not rebuild or change the plugin.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log, cwd, env):
    start = time.monotonic()
    with log.open('w') as output:
        result = subprocess.run([str(item) for item in command], stdout=output,
                                stderr=subprocess.STDOUT, cwd=cwd, env=env)
    row = dict(exit=result.returncode, seconds=time.monotonic()-start,
               log=log.name, sha256=sha(log), command=[str(item) for item in command])
    print(json.dumps(row), flush=True)
    if result.returncode:
        print(log.read_text()[-10000:], flush=True)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--motoko', required=True, type=Path)
    args = parser.parse_args()
    motoko = args.motoko.resolve()
    env = os.environ.copy()
    env['PATH'] = str(motoko/'bin') + ':' + env['PATH']
    artifact = ROOT/'dist/ed25519'
    source_paths = [ROOT/'plugins/ed25519'/name for name in (
        'runtime/src/lib.rs', 'runtime/Cargo.toml', 'compiler/register.ml',
        'compiler/reference.ml', 'plugin.json')]
    source_paths += [ROOT/'packages/fast/src/Ed25519.mo', ROOT/'Cargo.lock']
    sources = {str(path.relative_to(ROOT)): sha(path) for path in source_paths}
    build = json.loads((artifact/'build.json').read_text())
    for name, digest in build['source_sha256'].items():
        if name.startswith('plugins/ed25519/'):
            assert sha(ROOT/name) == digest, f'stale plugin source: {name}'
    artifacts = {path.name: sha(path) for path in artifact.iterdir() if path.is_file()}
    for name, digest in build['sha256'].items():
        assert artifacts[name] == digest, f'stale plugin artifact: {name}'
    report = dict(schema=1, source_sha256=sources, artifact_sha256=artifacts,
                  corpus_cases=290, wycheproof_cases=151,
                  mixed_order={'uncofactored_valid': 8, 'cofactor_only_invalid': 8})
    native_flags = (env['CARGO_ENCODED_RUSTFLAGS'].split('\x1f')
                    if env.get('CARGO_ENCODED_RUSTFLAGS') else shlex.split(env.get('RUSTFLAGS', '')))
    runtime_flags = build.get('runtime_rustflags', [])
    for cfg in json.loads((ROOT/'plugins/ed25519/plugin.json').read_text()).get('runtime_cfg', []):
        for label, flags in [('native', native_flags), ('runtime', runtime_flags)]:
            assert any(flags[index:index+2] == ['--cfg', cfg] for index in range(len(flags))), \
                f'{label} audit would omit configured backend: {cfg}'
    report['native_rustflags'] = native_flags
    report['runtime_rustflags'] = runtime_flags
    report['native'] = run(['cargo', 'test', '--offline', '--verbose', '--manifest-path', HERE/'Cargo.toml',
                            '--lib', '--target-dir', ROOT/'_build/ed25519-audit-native'],
                           HERE/'native.log', ROOT, env)
    report['motoko'] = run(['test-runner', '-b', '-j', '1', HERE/'run'],
                           HERE/'motoko.log', motoko, env)
    report['engines'] = {}
    for fixture in sorted((HERE/'run').glob('*.mo')):
        paths = {kind: HERE/'run/_out'/(fixture.stem+'.'+kind)
                 for kind in ['run', 'run-ir', 'run-low', 'wasm-run', 'valid']}
        report['engines'][fixture.name] = {kind: sha(path) for kind, path in paths.items() if path.is_file()}
        if report['motoko']['exit'] == 0:
            assert len(report['engines'][fixture.name]) == len(paths), 'missing execution engine'
    report['fixture_sha256'] = {str(path.relative_to(HERE)): sha(path)
        for path in sorted(HERE.rglob('*')) if path.is_file()
        and path.suffix in {'.mo', '.rs', '.py', '.json', '.toml'}
        and '_out' not in path.parts and path.name not in {'evidence.json', 'report.json'}}
    assert sources == {str(path.relative_to(ROOT)): sha(path) for path in source_paths}, 'source changed during audit'
    assert artifacts == {path.name: sha(path) for path in artifact.iterdir() if path.is_file()}, 'artifact changed during audit'
    report['passed'] = report['native']['exit'] == report['motoko']['exit'] == 0
    (HERE/'evidence.json').write_text(json.dumps(report, indent=2)+'\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
