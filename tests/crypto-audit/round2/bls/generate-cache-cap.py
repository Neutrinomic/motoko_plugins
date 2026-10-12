#!/usr/bin/env python3
"""Independent Ethereum PoP fixtures for the bounded message cache."""
from pathlib import Path
import json
from py_ecc import __version__
from py_ecc.bls import G2ProofOfPossession as eth

assert __version__ == '8.0.0'
HERE=Path(__file__).resolve().parent
secrets=[42,43]
keys=[eth.SkToPk(s) for s in secrets]
proofs=[eth.PopProve(s) for s in secrets]
def blob(b): return '"'+''.join('\\%02x'%x for x in b)+'"'
def arr(bs): return '['+','.join(blob(b) for b in bs)+']'
cases=[]
messages=[]
def message(size,last):
    value=b'x'*(size-1)+bytes([last])
    try:return messages.index(value)
    except ValueError:messages.append(value);return len(messages)-1
def case(name,indices,ms,expected='#ok(true)',bad_proof=False,wrong_signature=False,short_signature=False):
    sig=eth.Aggregate([eth.Sign(secrets[i],messages[m]+(b'!' if wrong_signature else b'')) for i,m in zip(indices,ms)])
    if short_signature:sig=b''
    ps=[proofs[i] for i in indices]
    if bad_proof:ps[-1]=proofs[1-indices[-1]]
    expression=f'B.aggregateVerifyEthereum({arr([keys[i] for i in indices])},{arr(ps)},['+','.join('m'+str(m) for m in ms)+'],'+blob(sig)+')'
    cases.append((name,expression,expected))
for size in [1023,1024,1025,65536]:
    a,b=message(size,0),message(size,1)
    case(f'repeated-{size}',[0,0],[a,a])
    case(f'common-prefix-distinct-{size}',[0,1,0],[a,b,a])
    case(f'wrong-message-{size}',[0,0],[a,a],expected='#ok(false)',wrong_signature=True)
small=message(1024,2);large=message(1025,2)
case('mixed-short-long-nonadjacent',[0,1,0,0,1],[large,small,large,small,large])
case('long-invalid-late-proof',[0,0,0],[large,large,large],expected='#err(#invalidProof)',bad_proof=True)
case('long-invalid-signature-precedence',[0,0,0],[large,large,large],expected='#err(#invalidLength)',bad_proof=True,short_signature=True)
lines=['import B "mo:fast/BLS12381";','import P "mo:⛔";']
for i,m in enumerate(messages):lines.append(f'let m{i} : Blob = {blob(m)};')
for name,expression,expected in cases:
    lines += ['// '+name,f'assert {expression} == {expected};']
lines.append(f'P.debugPrint("independent cache-cap profile checks passed: {len(cases)}");')
(HERE/'cache-cap.mo').write_text('\n'.join(lines)+'\n')
(HERE/'cache-cap-provenance.json').write_text(json.dumps(dict(oracle='Ethereum py_ecc '+__version__,cases=len(cases),sizes=[1023,1024,1025,65536],test_only_secret_scalars=secrets,names=[x[0] for x in cases]),indent=2)+'\n')
print(len(cases),'cache-cap profile fixtures')
