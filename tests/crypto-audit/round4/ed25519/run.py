#!/usr/bin/env python3
"""Validate the frozen round4 artifact, retaining earlier audit evidence unchanged."""
import argparse
import importlib.util
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
previous = ROOT/'tests/crypto-audit/prepared/ed25519/run.py'
spec = importlib.util.spec_from_file_location('audit_tools', previous)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
sha, run = audit.sha, audit.run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--motoko', type=Path, required=True)
    args = parser.parse_args()
    sdk = args.motoko.resolve()
    artifact = ROOT/'dist/ed25519'
    build = json.loads((artifact/'build.json').read_text())
    compiler = sdk/'src/moc'
    assert sha(compiler) == build['moc_sha256'], 'wrong compiler'
    sources = {name:sha(ROOT/name) for name in build['source_sha256'] if name.startswith('plugins/ed25519/')}
    for name, value in sources.items():
        assert value == build['source_sha256'][name], f'stale source: {name}'
    for name in ('packages/fast/src/Ed25519.mo','Cargo.toml','Cargo.lock'):
        sources[name] = sha(ROOT/name)
    artifacts = {path.name:sha(path) for path in artifact.iterdir() if path.is_file()}
    for name, value in build['sha256'].items():
        assert artifacts[name] == value, f'stale artifact: {name}'
    native_dependencies = audit.dependencies(HERE/'Cargo.toml')
    for name, value in audit.dependencies(ROOT/'plugins/ed25519/runtime/Cargo.toml').items():
        assert native_dependencies[name] == value, f'native dependency differs: {name}'
    flags = []
    for cfg in json.loads((ROOT/'plugins/ed25519/plugin.json').read_text())['runtime_cfg']:
        flags.extend(['--cfg',cfg])
        assert any(build['runtime_rustflags'][i:i+2] == ['--cfg',cfg]
            for i in range(len(build['runtime_rustflags']))), f'Wasm omits cfg: {cfg}'
    provenance = json.loads((HERE/'provenance.json').read_text())
    for name, value in provenance['input_sha256'].items():
        assert sha(ROOT/name) == value, f'changed independent fixture: {name}'
    helper_paths = [previous,ROOT/'tests/crypto-audit/prepared/ed25519/native.rs']
    helper_hashes = {str(path.relative_to(ROOT)):sha(path) for path in helper_paths}
    rts = {name:sha(sdk/'rts'/name) for name in ('mo-rts.wasm','mo-rts-debug.wasm')}
    env = dict(os.environ, MOTOKO_ROOT=str(sdk), CARGO_ENCODED_RUSTFLAGS='\x1f'.join(flags))
    env['PATH'] = str(sdk/'bin')+':'+env['PATH']
    report = dict(schema=1, compiler_sha256=sha(compiler), compiler_root=str(sdk),
        rts_sha256=rts, source_sha256=sources, artifact_sha256=artifacts,
        native_rustflags=flags, runtime_rustflags=build['runtime_rustflags'],
        native_dependencies=native_dependencies, provenance=provenance,
        reused_test_sources_sha256=helper_hashes)
    report['native'] = run(['cargo','test','--offline','--verbose','--manifest-path',HERE/'Cargo.toml',
        '--lib','--target-dir',ROOT/'_build/round4-ed25519-audit-native'],HERE/'native.log',ROOT,env)
    report['motoko'] = run(['test-runner','-b','-j','1',HERE/'run'],HERE/'motoko.log',sdk,env)
    report['engines'] = {}
    for fixture in sorted((HERE/'run').glob('*.mo')):
        outputs = {kind:HERE/'run/_out'/(fixture.stem+'.'+kind)
            for kind in ('run','run-ir','run-low','wasm-run','valid')}
        report['engines'][fixture.name] = {kind:sha(path) for kind,path in outputs.items() if path.is_file()}
        if report['motoko']['exit'] == 0:
            assert len(report['engines'][fixture.name]) == len(outputs), 'missing engine'
    assert sources == {name:sha(ROOT/name) for name in sources}, 'source changed during audit'
    assert artifacts == {path.name:sha(path) for path in artifact.iterdir() if path.is_file()}, 'artifact changed'
    assert sha(compiler) == report['compiler_sha256'], 'compiler changed'
    assert rts == {name:sha(sdk/'rts'/name) for name in rts}, 'RTS changed'
    assert helper_hashes == {str(path.relative_to(ROOT)):sha(path) for path in helper_paths}, 'helper changed'
    report['audit_sha256'] = {str(path.relative_to(HERE)):sha(path) for path in HERE.rglob('*')
        if path.is_file() and '_out' not in path.parts and '__pycache__' not in path.parts
        and path.name not in {'evidence.json','report.json'}}
    report['passed'] = report['native']['exit'] == report['motoko']['exit'] == 0
    (HERE/'evidence.json').write_text(json.dumps(report,indent=2)+'\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
