#!/usr/bin/env python3
"""Freeze nested oracle generators and input resources without rewriting measured records."""
import argparse, hashlib, json, shutil
from datetime import datetime, timezone
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent
ROOT=BENCH.parents[1]

def capture(destination,phase):
    assert not destination.exists(), 'Oracle snapshot already exists'
    paths=set()
    for base in [HERE,BENCH/'fixtures']:
        for path in base.rglob('*'):
            if not path.is_file() or any(part in ['stage-manifests','comparisons','__pycache__'] for part in path.relative_to(base).parts):continue
            if path.suffix in ['.py','.json','.csv','.txt','.md','.mo'] and path.name not in ['source-store.json','round1-preservation.json']:
                paths.add(path)
    paths.update(BENCH/name for name in ['common.py','generate.py','generate-curves.py','generate-bitcoin.py','generate-bitcoin-tx.py'])
    paths.update((ROOT/'tests/crypto-audit/bls').glob('rfc9380*.json'))
    pins={str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}
    destination.mkdir(parents=True)
    for name,digest in pins.items():
        source=ROOT/name;target=destination/name
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        assert hashlib.sha256(target.read_bytes()).hexdigest()==digest
        assert hashlib.sha256(source.read_bytes()).hexdigest()==digest, 'Oracle resource changed during snapshot'
    metadata={'captured_utc':datetime.now(timezone.utc).isoformat(),'capture_phase':phase,'note':'Emitted Motoko fixtures and expected outputs are independently frozen by build.json. For late snapshots these generator bytes are supplementary reproducibility evidence, not a claim that their hashes were recorded before measurement.','sha256':pins}
    (destination/'oracle-provenance.json').write_text(json.dumps(metadata,indent=2)+'\n')
    return metadata

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--stage',required=True);a=p.parse_args()
    stage=BENCH/'results'/a.stage
    assert a.stage.startswith('round2-') and (stage/'build.json').exists()
    destination=stage/'inputs/benchmark-oracles'
    metadata=capture(destination,'after measurement; emitted fixtures already pinned during build')
    (stage/'oracle-provenance.json').write_text(json.dumps(metadata,indent=2)+'\n')
    print(f'Captured {len(metadata["sha256"])} oracle resources for {a.stage}')
