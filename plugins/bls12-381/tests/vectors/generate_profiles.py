#!/usr/bin/env python3
"""Independent public test fixtures; requires py_ecc==8.0.0 (MIT).
Run this script to regenerate profiles.json. Secrets are test constants only.
"""
import hashlib
import json
from pathlib import Path
from py_ecc.bls import G2ProofOfPossession as eth
from py_ecc.bls.hash_to_curve import hash_to_G1
from py_ecc.bls.point_compression import compress_G1, compress_G2
from py_ecc.optimized_bls12_381 import G1, G2, add, multiply, curve_order

def c1(p): return int(compress_G1(p)).to_bytes(48, 'big').hex()
def c2(p): return b''.join(int(z).to_bytes(48, 'big') for z in compress_G2(p)).hex()
sk = [42, 43]
messages = [b'alpha', b'beta']
ic_dst = b'BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_'
ic_sigs = [multiply(hash_to_G1(m, ic_dst, hashlib.sha256), s) for s,m in zip(sk,messages)]
msm_scalars = [curve_order-1, int('123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',16), 2, 0]
msm_sum = sum(a*b for a,b in zip([1,42,43,0],msm_scalars)) % curve_order
data = {
  'msm_scalars': [s.to_bytes(32,'big').hex() for s in msm_scalars],
  'g1_msm': c1(multiply(G1,msm_sum)),
  'g2_msm': c2(multiply(G2,msm_sum)),
  'source': 'Independent py_ecc 8.0.0; test-only secret scalars42,43',
  'messages': [x.hex() for x in messages],
  'eth_keys': [eth.SkToPk(s).hex() for s in sk],
  'eth_proofs': [eth.PopProve(s).hex() for s in sk],
  'eth_signatures': [eth.Sign(s,m).hex() for s,m in zip(sk,messages)],
  'eth_aggregate': eth.Aggregate([eth.Sign(s,m) for s,m in zip(sk,messages)]).hex(),
  'eth_same_message_aggregate': eth.Aggregate([eth.Sign(s,messages[0]) for s in sk]).hex(),
  'ic_keys': [c2(multiply(G2,s)) for s in sk],
  'ic_signatures': [c1(p) for p in ic_sigs],
  'ic_aggregate': c1(add(*ic_sigs)),
}
Path(__file__).with_name('profiles.json').write_text(json.dumps(data, indent=2)+'\n')
