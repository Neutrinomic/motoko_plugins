#!/usr/bin/env python3
"""Run both distinct Cargo source identities with the same selected backend."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


parser = argparse.ArgumentParser()
parser.add_argument("--bits", choices=("32", "64"), required=True)
parser.add_argument("--target-dir", type=Path, default=Path("/tmp/motoko-ed25519-prepared-vendor-comparator"))
args = parser.parse_args()
here = Path(__file__).resolve().parent
vendor = here.parents[2]
for crate in ("curve25519-dalek", "ed25519-dalek"):
    source = vendor / crate
    provenance = json.loads((source / "upstream-source.json").read_text())
    assert sha(source / "exact.patch") == provenance["exact_patch_sha256"]
    for name, original_hash in provenance["upstream_files_sha256"].items():
        expected = provenance["changed_upstream_files"].get(name, {}).get("patched_sha256", original_hash)
        assert sha(source / name) == expected, f"Source provenance mismatch: {crate}/{name}"
flags = ["--cfg", f'curve25519_dalek_bits="{args.bits}"', "--cfg", 'curve25519_dalek_backend="serial"']
env = dict(os.environ, CARGO_ENCODED_RUSTFLAGS="\x1f".join(flags))
env.pop("RUSTFLAGS", None)
command = ["cargo", "run", "--release", "--locked", "--jobs", "1", "--manifest-path", str(here / "Cargo.toml"), "--target-dir", str(args.target_dir)]
run = subprocess.run(command, env=env, text=True, capture_output=True)
print(run.stderr, end="")
print(run.stdout, end="")
if run.returncode:
    raise SystemExit(run.returncode)
result = json.loads(run.stdout)
result.update({
    "configuration": flags,
    "command": command,
    "rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
    "cargo": subprocess.check_output(["cargo", "--version"], text=True).strip(),
    "executable_sha256": sha(args.target_dir / "release/ed25519-prepared-vendor-comparator"),
    "files_sha256": {
        "Cargo.toml": sha(here / "Cargo.toml"),
        "Cargo.lock": sha(here / "Cargo.lock"),
        "src/main.rs": sha(here / "src/main.rs"),
        "run.py": sha(Path(__file__)),
        "curve25519-dalek/exact.patch": sha(vendor / "curve25519-dalek/exact.patch"),
        "ed25519-dalek/exact.patch": sha(vendor / "ed25519-dalek/exact.patch"),
        "curve25519-dalek/upstream-source.json": sha(vendor / "curve25519-dalek/upstream-source.json"),
        "ed25519-dalek/upstream-source.json": sha(vendor / "ed25519-dalek/upstream-source.json"),
    },
})
(here / f"result-serial{args.bits}.json").write_text(json.dumps(result, indent=2) + "\n")
