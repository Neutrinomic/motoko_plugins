#!/usr/bin/env python3
"""Combine generated family manifests without discarding per-case semantics."""
import json
from pathlib import Path
here=Path(__file__).resolve().parent
paths=['cases.json','curve-cases/cases.json','bitcoin-cases/cases.json','bitcoin-tx-cases/cases.json']
cases=[];seen=set()
for name in paths:
    manifest=json.loads((here/name).read_text())
    for case in (manifest['cases'] if isinstance(manifest,dict) else manifest):
        key=(case['name'],case['implementation'])
        assert key not in seen,key
        seen.add(key);cases.append(case)
(here/'all-cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(f'{len(cases)} implementations in all-cases.json')
