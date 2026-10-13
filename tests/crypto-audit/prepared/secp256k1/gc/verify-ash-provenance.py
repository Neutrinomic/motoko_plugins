#!/usr/bin/env python3
"""Read-only verification of the shared Ash copy used by prepared GC tests."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--provenance", type=Path, default=Path(
    "/srv/shared/code/motoko_experiments/plugins/_build/prepared-crypto/rsa/_build/prepared-validation/ash-source-provenance.json"))
args = parser.parse_args()
manifest = args.provenance.resolve()
raw = manifest.read_bytes()
provenance = json.loads(raw)
copied = manifest.parent / "ash-local"
expected_sdk = "/srv/shared/code/motoko_experiments/prepared-crypto/sdk/bin/moc"
assert provenance["sdk_moc_override"] == expected_sdk
modified = []
for relative, hashes in provenance["files"].items():
    actual = hashlib.sha256((copied / relative).read_bytes()).hexdigest()
    assert actual == hashes["copied_sha256"], f"Copied source changed: {relative}"
    if hashes["original_sha256"] != hashes["copied_sha256"]:
        modified.append(relative)
assert modified == ["src/binaries.ts"], f"Unexpected copied modifications: {modified}"
source_files = {str(path.relative_to(copied)) for path in (copied / "src").rglob("*") if path.is_file()}
recorded_sources = {name for name in provenance["files"] if name.startswith("src/")}
assert source_files == recorded_sources, "Copied source inventory differs from provenance"
assert f'if (binaryName === \'moc\') return "{expected_sdk}";' in (copied / "src/binaries.ts").read_text()
print(json.dumps({"verified": True, "manifest": str(manifest),
                  "manifest_sha256": hashlib.sha256(raw).hexdigest(),
                  "copied_files_checked": len(provenance["files"]),
                  "sdk_moc_override": expected_sdk, "canister_executed": False}, indent=2))
