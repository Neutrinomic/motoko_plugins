#!/usr/bin/env python3
"""Wrap the fixed-array workloads in an option to exercise dynamic headers."""

import argparse
import json
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--out", type=Path, required=True)
args = parser.parse_args()
subprocess.run([sys.executable, str(Path(__file__).with_name("generate-static-arrays.py")),
                "--out", str(args.out)], check=True)
source_path = args.out / "main.mo"
source = source_path.read_text()
for value in ("fixed", "texts", "blobs", "octets"):
    for encoder in ("Prim.to_candid_canonical", "to_candid"):
        original = f"{encoder}({value})"
        assert original in source
        source = source.replace(original, f"{encoder}(?{value})")
source = source.replace("generate-static-arrays.py", Path(__file__).name)
source_path.write_text(source)
manifest_path = args.out / "cases.json"
manifest = json.loads(manifest_path.read_text())
manifest["suite"] = "candidx-nested-arrays"
for case in manifest["cases"]:
    if case["family"] == "candidx":
        case["name"] = case["name"].replace("candid-", "candid-optional-")
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
