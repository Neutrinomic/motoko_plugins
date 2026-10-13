#!/usr/bin/env python3
"""Run frozen round4 audit using the retained prepared-audit protocol."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
prior=ROOT/'tests/crypto-audit/prepared/secp256k1/run.py'
spec=importlib.util.spec_from_file_location('protocol',prior)
protocol=importlib.util.module_from_spec(spec)
spec.loader.exec_module(protocol)
# Only the selected fixtures/native harness and evidence destination change.
# Retained round3/prepared corpus files are inputs and are never overwritten.
protocol.HERE=HERE
protocol.ROOT=ROOT
dependencies=[prior,ROOT/'tests/crypto-audit/prepared/secp256k1/generate.py',ROOT/'tests/crypto-audit/round3/secp256k1/generate.py',ROOT/'tests/crypto-audit/curves/run_audit.py']
pins={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in dependencies}
result=protocol.main()
assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in pins.items())
(HERE/'protocol-dependencies.json').write_text(json.dumps(pins,indent=2)+'\n')
raise SystemExit(result)
