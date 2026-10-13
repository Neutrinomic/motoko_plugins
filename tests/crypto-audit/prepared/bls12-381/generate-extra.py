#!/usr/bin/env python3
"""Independent extra fixtures. Requires py_ecc==8.0.0; all secrets are test-only."""
import hashlib
import json
from pathlib import Path
from py_ecc import __version__
from py_ecc.bls import G2ProofOfPossession as eth
from py_ecc.bls.hash_to_curve import hash_to_G1
from py_ecc.bls.point_compression import compress_G1, compress_G2
from py_ecc.optimized_bls12_381 import G2, add, multiply, curve_order

assert __version__ == '8.0.0'
HERE = Path(__file__).resolve().parent
c1 = lambda p: int(compress_G1(p)).to_bytes(48, 'big').hex()
c2 = lambda p: b''.join(int(x).to_bytes(48, 'big') for x in compress_G2(p)).hex()
secret = curve_order - 42
dst = b'BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_'
rows = []
def add_case(name, op, keys, messages, signature, status=0, value=True):
    rows.append(dict(name=name, op=op, keys=keys, messages=[m.hex() for m in messages], signature=signature, status=status, value=value))
add_case('ic-repeated-key-distinct-messages', 27, [0,0], [b'alpha',b'beta'],
         c1(multiply(add(hash_to_G1(b'alpha',dst,hashlib.sha256),hash_to_G1(b'beta',dst,hashlib.sha256)),42)))
for count,op in [(2,28),(8,28),(127,28),(128,29)]:
    add_case(f'eth-repeated-key-and-message-valid-{count}',op,[0]*count,[b'alpha']*count,eth.Sign(42*count,b'alpha').hex())
for length in [1023,1024,1025,65536]:
    message=b'x'*(length-1)+b'\x00'
    add_case(f'eth-repeated-long-message-{length}',28,[0,0],[message,message],eth.Sign(84,message).hex())
for op in [28,29]:
    add_case(f'eth-cancellation-identity-{op}',op,[0,2],[b'alpha']*2,'c0'+'00'*95,7)
    add_case(f'eth-cancellation-malformed-signature-{op}',op,[0,2],[b'alpha']*2,'',1)
    add_case(f'eth-cancellation-valid-signature-{op}',op,[0,2],[b'alpha']*2,eth.Sign(42,b'alpha').hex(),7 if op==29 else 0,False)
data = dict(oracle='py_ecc '+__version__,test_only_secret_scalars=[42,43,str(secret)],
            negative=dict(ic_key=c2(multiply(G2,secret)),eth_key=eth.SkToPk(secret).hex(),
                          eth_proof=eth.PopProve(secret).hex(),
                          eth_signature=eth.Sign(secret,b'alpha').hex(),
                          ic_signature=c1(multiply(hash_to_G1(b'alpha',dst,hashlib.sha256),secret))),
            aggregates=rows)
(HERE/'extra.json').write_text(json.dumps(data,indent=2)+'\n')
print('Independent extra cases:',len(rows))
