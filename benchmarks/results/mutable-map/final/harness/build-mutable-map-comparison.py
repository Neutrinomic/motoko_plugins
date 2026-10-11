#!/usr/bin/env python3
"""Compile a generated mutable-map actor and record its exact compiler/plugin inputs."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--motoko', required=True, type=Path)
parser.add_argument('--deps', required=True, type=Path)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--require-clean-compiler', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
motoko, deps, out = args.motoko.resolve(), args.deps.resolve(), args.out.resolve()
package = 'core@2.5.0'
lock = json.loads((deps / 'mops.lock').read_text())
if lock['deps'].get('core') != '2.5.0' or package not in lock['hashes']:
    raise ValueError('The comparison requires locked core@2.5.0')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


for name, digest in lock['hashes'][package].items():
    if not name.startswith(package + '/') or '..' in Path(name).parts:
        raise ValueError(f'Invalid lockfile path: {name}')
    if sha(deps / '.mops' / name) != digest:
        raise ValueError(f'Core file differs from lock: {name}')
for source in (deps / '.mops' / package / 'src').rglob('*.mo'):
    if source.relative_to(deps / '.mops').as_posix() not in lock['hashes'][package]:
        raise ValueError(f'Unpinned Core source: {source}')

compiler = motoko / 'src/moc'
plugin = root / 'dist/mutable-map'
build = json.loads((plugin / 'build.json').read_text())
for name, digest in build['sha256'].items():
    if sha(plugin / name) != digest:
        raise ValueError(f'Plugin build manifest differs from artifact: {name}')


def git(directory, *arguments):
    return subprocess.check_output(['git', '-C', str(directory), *arguments], text=True).strip()


revision = git(motoko, 'rev-parse', 'HEAD')
dirty = bool(git(motoko, 'status', '--porcelain'))
version = subprocess.check_output([str(motoko / 'bin/moc'), '--version'], text=True).strip()
if (build['motoko_revision'], build['motoko_dirty'], build['motoko_version']) != (revision, dirty, version):
    raise ValueError('Plugin was built against a different compiler source/version state; rebuild it')
if args.require_clean_compiler and dirty:
    raise ValueError('Final measurements require a committed, clean compiler checkout')
if build.get('moc_sha256') != sha(compiler):
    raise ValueError('Plugin build does not identify this compiler binary; rebuild with current build script')
build_sources = build.get('source_sha256', {})
required_inputs = {path.relative_to(root).as_posix()
                   for path in (root / 'plugins/mutable-map/compiler').iterdir()
                   if path.suffix in ('.ml', '.mli')}
required_inputs.add('plugins/mutable-map/plugin.json')
if not required_inputs <= set(build_sources):
    raise ValueError('Plugin build manifest omits compiler source inputs; rebuild with current build script')
for name, digest in build_sources.items():
    if Path(name).is_absolute() or '..' in Path(name).parts or sha(root / name) != digest:
        raise ValueError(f'Plugin source differs from its built artifact: {name}')
compiler_sources = build.get('motoko_source_sha256', {})
if not compiler_sources:
    raise ValueError('Plugin build does not identify compiler source inputs; rebuild with current build script')
for name, digest in compiler_sources.items():
    if Path(name).is_absolute() or '..' in Path(name).parts or sha(motoko / name) != digest:
        raise ValueError(f'Compiler source differs from plugin build: {name}')

source_paths = sorted((root / 'plugins/mutable-map/compiler').glob('*')) + sorted(
    (root / 'plugins/mutable-map/motoko').glob('*.mo')) + [root / 'plugins/mutable-map/plugin.json']
source_hashes = {path.relative_to(root).as_posix(): sha(path)
                 for path in source_paths if path.is_file()}
support_paths = ('bin/wrapper.sh', 'rts/mo-rts.wasm', 'rts/mo-rts-debug.wasm')
support_hashes = {name: sha(motoko / name) for name in support_paths}
before = {'moc': sha(compiler), 'plugin': sha(plugin / 'plugin.cmxs'),
          'source': sha(out / 'main.mo'), 'build_manifest': sha(plugin / 'build.json')}
subprocess.run([str(motoko / 'bin/moc'), '--plugin', str(plugin),
                '--package', 'core', str(deps / '.mops' / package / 'src'),
                '--package', 'mutable-map', str(root / 'plugins/mutable-map/motoko'),
                '-A', 'M0235,M0236', str(out / 'main.mo'),
                '-o', str(out / 'main.wasm')], check=True)
after = {'moc': sha(compiler), 'plugin': sha(plugin / 'plugin.cmxs'),
         'source': sha(out / 'main.mo'), 'build_manifest': sha(plugin / 'build.json')}
if (before != after or any(sha(root / path) != digest for path, digest in source_hashes.items()) or
        any(sha(motoko / path) != digest for path, digest in compiler_sources.items()) or
        any(sha(motoko / path) != digest for path, digest in support_hashes.items())):
    raise RuntimeError('A compiler/plugin/source input changed during compilation; retry on a stable snapshot')
if (git(motoko, 'rev-parse', 'HEAD'), bool(git(motoko, 'status', '--porcelain'))) != (revision, dirty):
    raise RuntimeError('Compiler source state changed during compilation; retry on a stable snapshot')
provenance = {
    'compiler': {'revision': revision, 'dirty': dirty, 'version': version,
                 'moc_sha256': before['moc'], 'plugin_abi': 1,
                 'support_sha256': support_hashes},
    'plugin': {'revision': git(root, 'rev-parse', 'HEAD'),
               'dirty': bool(git(root, 'status', '--porcelain')),
               'build': build, 'source_sha256': source_hashes},
    'dependencies': {'package': package, 'mops_lock_sha256': sha(deps / 'mops.lock'),
                     'source_sha256': lock['hashes'][package]},
    'artifacts': {'main.mo': sha(out / 'main.mo'), 'main.wasm': sha(out / 'main.wasm')},
}
(out / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
manifest_path = out / 'cases.json'
manifest = json.loads(manifest_path.read_text())
manifest['provenance'] = {
    'compiler_revision': provenance['compiler']['revision'],
    'compiler_dirty': provenance['compiler']['dirty'],
    'moc_sha256': before['moc'], 'plugin_cmxs_sha256': before['plugin'],
    'plugin_source_sha256': source_hashes,
    'core_version': '2.5.0', 'mops_lock_sha256': sha(deps / 'mops.lock'),
    'full_provenance_sha256': sha(out / 'provenance.json'),
}
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
print(out / 'main.wasm')
