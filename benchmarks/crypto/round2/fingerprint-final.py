#!/usr/bin/env python3
"""Pin all table plugin cohorts to the final shared production source and artifacts."""
import argparse, hashlib, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent
ROOT=BENCH.parents[1]
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--stage',action='append',required=True);a=p.parse_args()
plugins=['sha256','sha512','ripemd160','blake3','hmac-sha2','base58','bech32','secp256k1','p256','bls12-381']
paths=list((ROOT/'packages/fast/src').rglob('*.mo'))
for plugin in plugins:
    paths.extend(path for path in (ROOT/'dist'/plugin).rglob('*') if path.is_file())
pins={str(path.relative_to(ROOT)):sha(path) for path in paths}
stages={}
for stage in a.stage:
    directory=BENCH/'results'/stage
    build=json.loads((directory/'build.json').read_text())
    assert build['complete'] and all(case['returncode']==0 for case in build['cases'])
    for relative,digest in pins.items():
        assert sha(directory/'inputs'/relative)==digest, 'Production/staged fingerprint differs: '+relative
    stages[stage]={'build_sha256':sha(directory/'build.json')}
(HERE/'api-final-fingerprint.json').write_text(json.dumps({'purpose':'Exact final shared production modules and runtime/compiler plugin artifacts for every plugin cell in the public API table','source_and_artifact_sha256':pins,'stages':stages},indent=2)+'\n')
print('Verified',len(pins),'final production source/artifact pins across',len(stages),'cohort(s)')
