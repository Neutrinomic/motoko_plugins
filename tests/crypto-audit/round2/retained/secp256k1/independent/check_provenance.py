#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import tarfile

WORK = Path(__file__).resolve().parent
ROOT = WORK.parents[2]
STAGE = WORK.parent / 'secp256k1-adapter'
BASELINE = WORK.parent / 'baseline'
VENDOR = STAGE / 'plugins/secp256k1/runtime/vendor/k256'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

provenance = json.loads((VENDOR / 'upstream-source.json').read_text())
archive = next(Path('/home/devbox/.cargo/registry/cache').glob('*/k256-0.13.4.crate'))
assert sha(archive) == provenance['archive_sha256']
with tarfile.open(archive) as tf:
    original = {
        member.name.removeprefix('k256-0.13.4/'): tf.extractfile(member).read()
        for member in tf.getmembers() if member.isfile()
    }
assert set(original) == set(provenance['upstream_files_sha256'])
changes = {}
for path, data in original.items():
    assert hashlib.sha256(data).hexdigest() == provenance['upstream_files_sha256'][path]
    actual = (VENDOR / path).read_bytes()
    if data != actual:
        assert path in provenance['changed_upstream_files']
        assert hashlib.sha256(actual).hexdigest() == provenance['changed_upstream_files'][path]['patched_sha256']
        changes[path] = dict(upstream=hashlib.sha256(data).hexdigest(), patched=hashlib.sha256(actual).hexdigest())
assert set(changes) == set(provenance['changed_upstream_files'])
assert sha(VENDOR / 'exact.patch') == provenance['exact_patch_sha256']
original_dir = WORK / 'original-k256'
if original_dir.exists():
    shutil.rmtree(original_dir)
original_dir.mkdir()
for path, data in original.items():
    output = original_dir / path
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
patch = subprocess.run(['patch', '-p1', '--input', str(VENDOR / 'exact.patch')], cwd=original_dir, capture_output=True, text=True)
assert patch.returncode == 0, patch.stdout + patch.stderr
assert all((original_dir / path).read_bytes() == (VENDOR / path).read_bytes() for path in original)
manifest = json.loads((STAGE / 'dist/secp256k1/build.json').read_text())
source_checked = []
for path, digest in manifest['source_sha256'].items():
    if path.startswith('plugins/secp256k1/') or path in ['Cargo.toml', 'Cargo.lock']:
        assert sha(STAGE / path) == digest, path
        source_checked.append(path)
artifact_checked = {path: sha(STAGE / 'dist/secp256k1' / path) for path in manifest['sha256']}
assert artifact_checked == manifest['sha256']
unchanged = []
for path in (BASELINE / 'plugins/secp256k1/compiler').rglob('*'):
    if path.is_file():
        rel = path.relative_to(BASELINE)
        assert path.read_bytes() == (STAGE / rel).read_bytes()
        unchanged.append(str(rel))
for name in ['packages/fast/src/Secp256k1.mo', 'plugins/secp256k1/plugin.json']:
    assert (BASELINE / name).read_bytes() == (STAGE / name).read_bytes()
    unchanged.append(name)
tag = hashlib.sha256(b'BIP0340/challenge').digest()
runtime = (STAGE / 'plugins/secp256k1/runtime/src/lib.rs').read_text()
tag_literal = re.search(r'const TAG: \[u8; 32\] = \[(.*?)\];', runtime).group(1)
assert bytes(int(value.strip(), 16) for value in tag_literal.split(',')) == tag
report = dict(passed=True, archive=str(archive), archive_sha256=sha(archive), upstream_files=len(original),
              changed_files=changes, patch_sha256=sha(VENDOR / 'exact.patch'), exact_patch_reapplied=True,
              manifest_source_files_checked=source_checked, artifacts=artifact_checked,
              unchanged_files=unchanged, challenge_tag=tag.hex())
(WORK / 'provenance.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: value for key, value in report.items() if key not in ['manifest_source_files_checked', 'unchanged_files']}, indent=2))
