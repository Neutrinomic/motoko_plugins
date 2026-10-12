#!/usr/bin/env python3
"""Check unchanged retained evidence; optionally verify promoted source pins."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--production", action="store_true")
args = parser.parse_args()
here = Path(__file__).resolve().parent
root = here.parents[3]
manifest = json.loads((here / "manifest.json").read_text())
checked = 0
for entry in manifest["copied_files"]:
    data = (here / entry["path"]).read_bytes()
    assert len(data) == entry["bytes"], entry["path"]
    assert hashlib.sha256(data).hexdigest() == entry["sha256"], entry["path"]
    checked += 1
production = 0
if args.production:
    for path, entry in manifest["production_source_verification"]["files"].items():
        actual = hashlib.sha256((root / path).read_bytes()).hexdigest()
        assert actual == entry["expected_sha256"], path
        production += 1
print(f"Verified {checked} retained copies and {production} production source pins.")
