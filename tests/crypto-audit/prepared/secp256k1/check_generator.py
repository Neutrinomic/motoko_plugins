#!/usr/bin/env python3
"""Verify every embedded G/endomorphism coordinate using Python affine integers."""
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location('oracle', ROOT / 'tests/crypto-audit/curves/run_audit.py')
oracle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oracle)
source = ROOT / 'plugins/secp256k1/runtime/vendor/k256/src/arithmetic/prepared.rs'
text = source.read_text()
start = text.index('const GENERATOR:')
end = text.index('\n];', start) + 3
fragment = text[start:end]
arrays = re.findall(r'from_bytes_unchecked\(&\[([^]]+)\]\)', fragment)
coordinates = [bytes(int(x.strip(), 16) for x in a.split(',') if x.strip()) for a in arrays]
assert len(coordinates) == 32 and all(len(x) == 32 for x in coordinates)
points = [(int.from_bytes(coordinates[i], 'big'), int.from_bytes(coordinates[i + 1], 'big')) for i in range(0,32,2)]
curve = oracle.CURVES['secp256k1']
beta = int('7AE96A2B657C07106E64479EAC3434E99CF0497512F58995C1396C28719501EE', 16)
expected = [oracle.multiply(curve, 2 * i + 1) for i in range(8)]
expected += [(x * beta % curve['p'], y) for x,y in expected]
assert points == expected
assert all(0 <= x < curve['p'] and 0 <= y < curve['p'] and (y*y-x*x*x-7) % curve['p'] == 0 for x,y in points)
report = {'passed': True, 'points':16, 'method':'Python integer affine multiplication of published G, odd factors 1..15; explicit beta endomorphism; canonical field range and on-curve equation.',
          'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
          'constant_fragment_sha256':hashlib.sha256(fragment.encode()).hexdigest(),
          'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(HERE/'generator-evidence.json').write_text(json.dumps(report,indent=2)+'\n')
print('16 shared generator points: all exact canonical values verified')
