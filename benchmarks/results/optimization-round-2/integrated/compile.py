#!/usr/bin/env python3
"""Recompile the six recorded actors; run only after canonical packages are built."""
from pathlib import Path
import hashlib
import json
import shlex
import shutil
import subprocess

ROOT = Path('/srv/shared/code/motoko_experiments/plugins')
MOTOKO = ROOT.parent / 'motoko_sha'
REPORT = ROOT / 'benchmarks/results/optimization-round-2/integrated'
SCRATCH = ROOT / '_build/opt2-integrated'
DEPS = ROOT / '_build/codec-comparison/deps'
REVISION = '128a41c060d473e4307dbfcce88b4587312a29b6'
MOC_SHA = 'c5bb31568300df2bf982779755a202f290e81c3350cb35f08e149a060fab7ec3'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(argv, cwd=ROOT):
    return subprocess.check_output(argv, cwd=cwd, text=True).strip()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


assert command(['git', 'rev-parse', 'HEAD'], MOTOKO) == REVISION
assert not command(['git', 'status', '--porcelain'], MOTOKO)
assert sha(MOTOKO / 'src/moc') == MOC_SHA
version = command([str(MOTOKO / 'bin/moc'), '--version'])
lock = json.loads((DEPS / 'mops.lock').read_text())
assert sha(DEPS / 'mops.lock') == 'a5678b395e56a7a53c0c0037185c26c8f6ae087dbbb24d397bf724a639b70aee'
package_args = shlex.split(command(['mops', 'sources', '--no-install'], DEPS))
aliases = {}
for i in range(0, len(package_args), 3):
    flag, alias, path = package_args[i:i + 3]
    assert flag == '--package'
    resolved = (DEPS / path).resolve()
    package_args[i + 2] = str(resolved)
    aliases[alias] = resolved.parent.name
assert set(aliases) == set(lock['deps'])
assert set(aliases.values()) == set(lock['hashes'])
for package, files in lock['hashes'].items():
    for name, digest in files.items():
        assert sha(DEPS / '.mops' / name) == digest, name
    for source in (DEPS / '.mops' / package / 'src').rglob('*.mo'):
        assert source.relative_to(DEPS / '.mops').as_posix() in files

builds = {}
historical_builds = {
    'json': 'json/benchmarks/results/optimization-round-2/json/package-final.json',
    'cbor': 'cbor/benchmarks/results/optimization-round-2/cbor/final-build.json',
    'pure-map': 'pure-map/dist/pure-map/build.json',
    'candidx': 'candidx/benchmarks/results/optimization-round-2/candidx/candidate-build.json',
    'sha256': 'sha256/benchmarks/results/optimization-round-2/sha256/final-build.json',
}
historical_package_checks = {}
for name in ['json', 'cbor', 'pure-map', 'candidx', 'sha256']:
    package = ROOT / 'dist' / name
    build = json.loads((package / 'build.json').read_text())
    assert build['motoko_revision'] == REVISION and not build['motoko_dirty']
    assert build['motoko_version'] == version and build['moc_sha256'] == MOC_SHA
    for file, digest in build['sha256'].items():
        assert sha(package / file) == digest, (name, file)
    for file, digest in build['source_sha256'].items():
        assert sha(ROOT / file) == digest, (name, file)
    for file, digest in build['motoko_source_sha256'].items():
        assert sha(MOTOKO / file) == digest, file
    old_path = ROOT.parent / 'optimization-round-2' / historical_builds[name]
    old = json.loads(old_path.read_text())
    prefix = 'plugins/' + name + '/'
    old_sources = {p: digest for p, digest in old['source_sha256'].items() if p.startswith(prefix)}
    new_sources = {p: digest for p, digest in build['source_sha256'].items() if p.startswith(prefix)}
    assert old_sources == new_sources, name
    assert old['sha256'].get('runtime.wasm') == build['sha256'].get('runtime.wasm'), name
    historical_package_checks[name] = {
        'manifest_path': str(old_path), 'manifest_sha256': sha(old_path),
        'own_source_inputs_identical': True,
        'runtime_bytes_identical': True if 'runtime.wasm' in build['sha256'] else None,
        'historical_artifacts_sha256': old['sha256'],
    }
    builds[name] = build

support = {name: sha(MOTOKO / name) for name in
           ['bin/wrapper.sh', 'rts/mo-rts.wasm', 'rts/mo-rts-debug.wasm']}
old_map = json.loads((ROOT.parent / 'optimization-round-2/pure-map/_build/opt2-pure-map/final/after/provenance.json').read_text())
assert support == old_map['compiler']['support_sha256']
assert sha(ROOT / 'plugins/pure-map/motoko/Map.mo') == old_map['plugin']['source_sha256']['plugins/pure-map/motoko/Map.mo']
native_candidx = Path('/srv/shared/code/candidx')
native_sources = {p.relative_to(native_candidx).as_posix(): sha(p)
                  for p in sorted((native_candidx / 'motoko/src').rglob('*.mo'))}
old_candidx = json.loads((ROOT.parent / 'optimization-round-2/candidx/benchmarks/results/optimization-round-2/candidx/provenance.json').read_text())
assert native_sources == old_candidx['candidx_native_sources']
assert command(['git', 'rev-parse', 'HEAD'], native_candidx) == old_candidx['candidx_revision']
provenance = {
    'compiler_revision': REVISION, 'compiler_moc_sha256': MOC_SHA,
    'compiler_version': version, 'compiler_dirty': False,
    'compiler_support_sha256': support,
    'plugins_revision': command(['git', 'rev-parse', 'HEAD']),
    'packages': builds,
    'historical_package_checks': historical_package_checks,
    'dependencies': {'mops_lock_sha256': sha(DEPS / 'mops.lock'),
                     'aliases': aliases, 'source_sha256': lock['hashes'],
                     'native_candidx_revision': command(['git', 'rev-parse', 'HEAD'], native_candidx),
                     'native_candidx_source_sha256': native_sources},
    'actors': {},
}
actors = json.loads((REPORT / 'actors.json').read_text())
for name, actor in actors.items():
    dest = SCRATCH / name
    dest.mkdir(parents=True, exist_ok=True)
    source, cases, wasm = (Path(actor[x]) for x in ['source', 'cases', 'wasm'])
    old_results = json.loads(Path(actor['result']).read_text())
    assert sha(source) == old_results['source_sha256'], name
    assert sha(cases) == old_results['cases_sha256'], name
    assert sha(wasm) == old_results['wasm_sha256'], name
    shutil.copyfile(source, dest / 'main.mo')
    shutil.copyfile(cases, dest / 'cases.json')
    args = [str(MOTOKO / 'bin/moc')]
    for package in actor['packages']:
        args += ['--plugin', str(ROOT / 'dist' / package)]
    if actor['dependencies'] == 'codec':
        args += package_args
    else:
        if actor['dependencies'] == 'candidx':
            args += ['--package', 'candidx', str(native_candidx / 'motoko/src')]
        if actor['dependencies'] in ['sha', 'candidx']:
            args += ['--package', 'sha2', str(DEPS / '.mops/sha2@0.2.5/src')]
        args += ['--package', 'core', str(DEPS / '.mops/core@2.5.0/src')]
        if actor['dependencies'] == 'map':
            args += ['--package', 'pure-map', str(ROOT / 'plugins/pure-map/motoko'), '-A', 'M0235,M0236']
    # Read the exact historical source path, preserving embedded source locations.
    # The original source, cases, results, package and binary are never overwritten.
    args += [str(source), '-o', str(dest / 'main.wasm')]
    with (dest / 'compile.log').open('w') as log:
        subprocess.run(args, cwd=ROOT, check=True, stdout=log, stderr=subprocess.STDOUT)
    assert sha(source) == old_results['source_sha256']
    provenance['actors'][name] = {
        'command': args, 'cwd': str(ROOT),
        'historical_result_sha256': sha(Path(actor['result'])),
        'historical_provenance_sha256': sha(Path(actor['provenance'])),
        'historical_wasm_sha256': sha(wasm),
        'source_sha256': sha(source), 'cases_sha256': sha(cases),
        'integrated_wasm_sha256': sha(dest / 'main.wasm'),
        'compile_log_sha256': sha(dest / 'compile.log'),
    }
    print(name, sha(dest / 'main.wasm'), flush=True)

assert sha(MOTOKO / 'src/moc') == MOC_SHA
assert command(['git', 'rev-parse', 'HEAD'], MOTOKO) == REVISION
assert not command(['git', 'status', '--porcelain'], MOTOKO)
for name, build in builds.items():
    assert json.loads((ROOT / 'dist' / name / 'build.json').read_text()) == build
    for file, digest in build['sha256'].items():
        assert sha(ROOT / 'dist' / name / file) == digest
assert all(sha(MOTOKO / name) == digest for name, digest in support.items())
assert all(sha(native_candidx / name) == digest for name, digest in native_sources.items())
dump(REPORT / 'build.json', provenance)
