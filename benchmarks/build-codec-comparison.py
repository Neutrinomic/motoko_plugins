#!/usr/bin/env python3
"""Compile a generated codec comparison using an installed Mops lockfile."""
import argparse
import hashlib
import json
import shlex
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--motoko', type=Path, required=True)
parser.add_argument('--deps', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--codec', choices=('json', 'cbor'), required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
deps = args.deps.resolve()
packages = shlex.split(subprocess.check_output(
    ['mops', 'sources', '--no-install'], cwd=deps, text=True))
lock = json.loads((deps / 'mops.lock').read_text())
resolved = {}
for i in range(0, len(packages), 3):
    if packages[i] != '--package':
        raise ValueError(f'Unexpected mops sources output: {packages[i:i + 3]}')
    package_id = Path(packages[i + 2]).parent.name
    resolved[packages[i + 1]] = package_id
    packages[i + 2] = str((deps / packages[i + 2]).resolve())
expected = {alias: f'{alias.split("@")[0]}@{version}' for alias, version in lock['deps'].items()}
if resolved != expected or set(resolved.values()) != set(lock['hashes']):
    raise ValueError('Installed package resolution differs from mops.lock')
# Mops CLI 1.12.0 compares the number of aliases with unique package IDs and
# rejects this valid 20-alias/18-package graph. Verify its full per-file lock
# directly, preserving all version and integrity checks for reproduction.
for package_id, hashes in lock['hashes'].items():
    for file_id, digest in hashes.items():
        if not file_id.startswith(package_id + '/') or '..' in Path(file_id).parts:
            raise ValueError(f'Invalid lockfile path: {file_id}')
        if hashlib.sha256((deps / '.mops' / file_id).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Package file differs from mops.lock: {file_id}')
    for source in (deps / '.mops' / package_id / 'src').rglob('*.mo'):
        if source.relative_to(deps / '.mops').as_posix() not in hashes:
            raise ValueError(f'Unpinned package source: {source}')
print(f'Verified {len(resolved)} package aliases and {len(lock["hashes"])} locked packages.', flush=True)
out = args.out.resolve()
subprocess.run([str(args.motoko.resolve() / 'bin/moc'),
                '--plugin', str(root / 'dist' / args.codec), *packages,
                str(out / 'main.mo'), '-o', str(out / 'main.wasm')], check=True)
