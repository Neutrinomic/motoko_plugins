#!/usr/bin/env python3
"""Restore exact frozen source bytes from the content-addressed archive."""
import argparse,hashlib,json,tarfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--stage',required=True);p.add_argument('--out',required=True,type=Path);a=p.parse_args()
index=json.loads((HERE/'source-store.json').read_text());store=HERE/'source-store.tar.gz'
assert hashlib.sha256(store.read_bytes()).hexdigest()==index['sha256'],'Source store changed'
map_path=BENCH/'results'/a.stage/'source-map.json'
assert hashlib.sha256(map_path.read_bytes()).hexdigest()==index['stage_maps'][str(map_path.relative_to(BENCH))],'Stage source map changed'
mapping=json.loads(map_path.read_text());a.out.mkdir(parents=True,exist_ok=False)
with tarfile.open(store,'r:gz') as tar:
    content={Path(member.name).name:tar.extractfile(member).read() for member in tar if member.isfile()}
    for name,meta in mapping['files'].items():
        relative=Path(name);assert not relative.is_absolute() and '..' not in relative.parts
        data=content[meta['sha256']];assert hashlib.sha256(data).hexdigest()==meta['sha256']
        target=a.out/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data);target.chmod(meta['mode'])
print(a.out)
