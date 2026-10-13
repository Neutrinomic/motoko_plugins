#!/usr/bin/env python3
"""Retain small immutable audit evidence, excluding native targets and executables."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("source",type=Path)
parser.add_argument("destination",type=Path)
args=parser.parse_args()
source,dest=args.source.resolve(),args.destination.resolve()
assert not dest.exists(),"never overwrite retained evidence"
dest.mkdir(parents=True)
paths=sorted(source.glob("*.log"))+sorted(source.glob("*.json"))+sorted(source.glob("*.tsv"))
for subdir in ["run","fail","fail-corrected"]: paths+=sorted((source/subdir).glob("*.mo"))
manifest={}
for path in paths:
    relative=path.relative_to(source)
    output=dest/relative
    output.parent.mkdir(parents=True,exist_ok=True)
    raw=path.read_bytes()
    if path.suffix not in [".json"]:
        output=output.with_name(output.name+".gz")
        output.write_bytes(gzip.compress(raw,compresslevel=9,mtime=0))
    else: output.write_bytes(raw)
    manifest[str(relative)]={"sha256":hashlib.sha256(raw).hexdigest(),"bytes":len(raw),"retained":str(output.relative_to(dest)),"retained_sha256":hashlib.sha256(output.read_bytes()).hexdigest()}
(dest/"retained-files.json").write_text(json.dumps(manifest,indent=2)+"\n")
print(f"retained {len(manifest)} evidence files")
