#!/usr/bin/env python3
"""Independent canonical constants and signed-radix proof checks; no runtime edit."""
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
curve = oracle.CURVES['secp256k1']
p, n = curve['p'], curve['n']
sources = {}

def load_points(name, expected):
    path = ROOT / 'plugins/secp256k1/runtime/vendor/k256/src/arithmetic' / name
    source = path.read_text()
    start = source.index('GENERATOR:')
    stop = source.index('\n];', start) + 3
    fragment = source[start:stop]
    raw = re.findall(r'from_bytes_unchecked\(&\[([^]]+)\]\)', fragment)
    coords = [bytes(int(x.strip(), 16) for x in a.split(',') if x.strip()) for a in raw]
    assert len(coords) == len(expected)*2 and all(len(c) == 32 for c in coords)
    points = [(int.from_bytes(coords[i], 'big'), int.from_bytes(coords[i+1], 'big')) for i in range(0,len(coords),2)]
    assert points == expected, name
    assert all(0<=x<p and 0<=y<p and (y*y-x*x*x-7)%p == 0 for x,y in points)
    sources[name] = {'sha256':hashlib.sha256(path.read_bytes()).hexdigest(), 'points':len(points)}

# Each point is independently multiplied from published G, rather than using
# the production generator's successive row doubling and repeated addition.
load_points('fixed_base_table.rs', [oracle.multiply(curve, (j+1)*pow(256,i,n)) for i in range(33) for j in range(8)])
beta = int('7AE96A2B657C07106E64479EAC3434E99CF0497512F58995C1396C28719501EE', 16)
odd = [oracle.multiply(curve, 2*i+1) for i in range(8)]
load_points('prepared.rs', odd + [(x*beta%p,y) for x,y in odd])

scalars = [0,1,n-1]
scalars += [(2**bit+delta)%n for bit in range(256) for delta in [-1,0,1]]
scalars += [int.from_bytes(hashlib.sha256(b'round4-independent-recoding'+i.to_bytes(4,'big')).digest(),'big')%n for i in range(512)]
for value in scalars:
    # Mathematical balanced-radix expansion, independent of the Rust byte loop.
    remaining = value
    digits = []
    for _ in range(64):
        digit = (remaining+8)%16-8
        digits.append(digit)
        remaining = (remaining-digit)//16
    digits.append(remaining)
    assert all(-8<=d<=7 for d in digits) and digits[64] in [0,1]
    even = sum(digits[2*i]*256**i for i in range(33))
    odd = sum(digits[2*i+1]*256**i for i in range(32))
    assert even + 16*odd == value
    for digit in digits:
        mask = digit >> 7
        magnitude = (digit+mask)^mask
        assert 0<=magnitude<=8 and magnitude == abs(digit)

report = {'passed':True, 'sources':sources, 'scalar_recoding_cases':len(scalars),
          'method':'Independent integer affine multiplication from published G for all 264 static points and 16 public-verification points; canonical field and curve checks. Mathematical balanced-radix reconstruction for boundary/random scalars, including the carry digit and signed magnitude.',
          'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
(HERE/'generator-evidence.json').write_text(json.dumps(report,indent=2)+'\n')
print('264 fixed-base and 16 public-verification constants, 1283 scalar recodings: passed')
