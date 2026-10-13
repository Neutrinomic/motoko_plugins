#!/usr/bin/env python3
"""Audit already-built prepared Ed25519 artifacts in the matching Nix environment."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import tomllib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log, cwd, env):
    start = time.monotonic()
    with log.open('w') as output:
        result = subprocess.run([str(value) for value in command], cwd=cwd, env=env,
                                stdout=output, stderr=subprocess.STDOUT)
    row = dict(exit=result.returncode, seconds=time.monotonic()-start, log=log.name,
               sha256=sha(log), command=[str(value) for value in command])
    print(json.dumps(row), flush=True)
    if result.returncode:
        print(log.read_text()[-12000:], flush=True)
    return row


def dependencies(manifest):
    data = tomllib.loads(manifest.read_text())['dependencies']
    for value in data.values():
        if isinstance(value, dict) and 'path' in value:
            value['path'] = str((manifest.parent/value['path']).resolve())
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--motoko', type=Path, required=True)
    args = parser.parse_args()
    motoko = args.motoko.resolve()
    artifact = ROOT/'dist/ed25519'
    build = json.loads((artifact/'build.json').read_text())
    compiler = motoko/'src/moc'
    assert sha(compiler) == build['moc_sha256'], 'audit compiler differs from plugin build host'
    runtimes = {name:sha(motoko/'rts'/name) for name in ('mo-rts.wasm','mo-rts-debug.wasm')}
    source_paths = [ROOT/name for name in build['source_sha256'] if name.startswith('plugins/ed25519/')]
    source_paths += [ROOT/'packages/fast/src/Ed25519.mo', ROOT/'Cargo.lock', ROOT/'Cargo.toml']
    sources = {str(path.relative_to(ROOT)): sha(path) for path in source_paths}
    for name, value in build['source_sha256'].items():
        if name.startswith('plugins/ed25519/'):
            assert sources[name] == value, f'stale source: {name}'
    artifacts = {path.name: sha(path) for path in artifact.iterdir() if path.is_file()}
    for name, value in build['sha256'].items():
        assert artifacts[name] == value, f'stale artifact: {name}'
    actual_dependencies = dependencies(HERE/'Cargo.toml')
    for name, value in dependencies(ROOT/'plugins/ed25519/runtime/Cargo.toml').items():
        assert actual_dependencies[name] == value, f'audit uses wrong runtime dependency: {name}'
    flags = []
    for cfg in json.loads((ROOT/'plugins/ed25519/plugin.json').read_text())['runtime_cfg']:
        flags.extend(['--cfg', cfg])
        assert any(build['runtime_rustflags'][index:index+2] == ['--cfg', cfg]
                   for index in range(len(build['runtime_rustflags']))), f'Wasm omits {cfg}'
    env = dict(os.environ, MOTOKO_ROOT=str(motoko), CARGO_ENCODED_RUSTFLAGS='\x1f'.join(flags))
    env['PATH'] = str(motoko/'bin')+':'+env['PATH']
    report = dict(schema=1, source_sha256=sources, artifact_sha256=artifacts,
                  compiler_sha256=sha(compiler), compiler_root=str(motoko),
                  rts_sha256=runtimes,
                  native_rustflags=flags, runtime_rustflags=build['runtime_rustflags'],
                  native_dependencies=actual_dependencies, provenance=json.loads((HERE/'provenance.json').read_text()))
    report['native'] = run(['cargo','test','--offline','--verbose','--manifest-path',HERE/'Cargo.toml',
                            '--lib','--target-dir',ROOT/'_build/prepared-ed25519-audit-native'],
                           HERE/'native.log',ROOT,env)
    report['motoko'] = run(['test-runner','-b','-j','1',HERE/'run'],HERE/'motoko.log',motoko,env)
    # Only this newly authored fail corpus gets initial expectations accepted.
    report['fail'] = run(['test-runner','-b','-a','-j','1',HERE/'fail'],HERE/'fail.log',motoko,env)
    report['engines'] = {}
    for fixture in sorted((HERE/'run').glob('*.mo')):
        outputs = {kind: HERE/'run/_out'/(fixture.stem+'.'+kind)
                   for kind in ['run','run-ir','run-low','wasm-run','valid']}
        report['engines'][fixture.name] = {kind: sha(path) for kind,path in outputs.items() if path.is_file()}
        if report['motoko']['exit'] == 0:
            assert len(report['engines'][fixture.name]) == len(outputs), 'runner omitted engine'
    report['nominal_rejections'] = {}
    for fixture in sorted((HERE/'fail').glob('*.mo')):
        output = HERE/'fail/ok'/(fixture.stem+'.tc.ok')
        if report['fail']['exit'] == 0:
            diagnostic = output.read_text()
            assert 'error [' in diagnostic, f'wrong rejection: {fixture.name}'
            if fixture.stem == 'show-handle':
                assert 'M0063' in diagnostic and 'Any' in diagnostic, 'wrong debug inspection rejection'
            else:
                assert 'Prepared' in diagnostic, f'wrong rejected type: {fixture.name}'
            if fixture.stem not in {'stable-handle','shared-handle','candid-handle','show-handle'}:
                assert 'M0096' in diagnostic, f'wrong nominal type rejection: {fixture.name}'
            else:
                word = {'stable-handle':'stable','show-handle':'show'}.get(fixture.stem,'shared')
                assert word in diagnostic, \
                    f'wrong boundary rejection: {fixture.name}'
            assert 'does not exist' not in diagnostic, 'missing dependency mistaken for nominal rejection'
            report['nominal_rejections'][fixture.name] = sha(output)
    assert sources == {str(path.relative_to(ROOT)):sha(path) for path in source_paths}, 'source changed'
    assert artifacts == {path.name:sha(path) for path in artifact.iterdir() if path.is_file()}, 'artifact changed'
    assert sha(compiler) == report['compiler_sha256'], 'compiler changed'
    assert runtimes == {name:sha(motoko/'rts'/name) for name in runtimes}, 'runtime changed'
    report['audit_sha256'] = {str(path.relative_to(HERE)):sha(path)
        for path in HERE.rglob('*') if path.is_file() and '_out' not in path.parts
        and '__pycache__' not in path.parts and path.name not in {'evidence.json','report.json'}}
    report['passed'] = all(report[stage]['exit'] == 0 for stage in ('native','motoko','fail'))
    (HERE/'evidence.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
