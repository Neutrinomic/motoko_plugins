#!/usr/bin/env python3
"""Base58 round-two workloads with Python integer / hashlib independent answers."""
import hashlib,json,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parents[1]
sys.path.insert(0,str(BENCH))
from common import actor,blob
ALPHABET=b'123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
def encode(data):
    zeros=len(data)-len(data.lstrip(b'\x00'))
    n=int.from_bytes(data,'big');out=[]
    while n:
        n,d=divmod(n,58);out.append(ALPHABET[d])
    return b'1'*zeros+bytes(reversed(out))
def check(data):return encode(data+hashlib.sha256(hashlib.sha256(data).digest()).digest()[:4])
cases=[]
def add(name,module,data,encoded,decode=False):
    source=HERE/name/'native/main.mo';source.parent.mkdir(parents=True,exist_ok=True)
    if decode:
        decls='transient let input : Text = '+json.dumps(encoded.decode())+';'
        op='result := switch(B.decode(input)){case(#ok b)b;case(#err _)Prim.trap("invalid independent vector")};'
        text=actor(f'import B "mo:fast/{module}";',decls,'',op)
        expected=data
    else:
        decls='transient let input : Blob = '+blob(data)+';'
        text=actor(f'import B "mo:fast/{module}";',decls,'','result := B.encode(input);','Prim.encodeUtf8(result)','Text')
        expected=encoded
    source.write_text(text)
    cases.append(dict(name=name,family='base58',implementation='native',comparison='round2-same-public-api',plugins=['base58']+(['sha256'] if module=='Base58Check' else []),expected_hex=expected.hex(),source=source.relative_to(BENCH).as_posix(),notes='Independent Python big-integer Base58 and hashlib SHA256; prepared input and result conversion outside measured window.'))
for n in [0,1,25,32,78,82,256,1024,4096]:
    pattern=bytes((131*i+17)%256 for i in range(n))
    inputs={'pattern':pattern}
    if n in [25,82,256,4096]:inputs.update(leading=b'\0'*(n//3)+pattern[n//3:],ff=b'\xff'*n,zero=b'\0'*n)
    for kind,data in inputs.items():
        encoded=encode(data)
        for decode in [False,True]:add(f'base58-{("decode" if decode else "encode")}-{n}-{kind}','Base58',data,encoded,decode)
for n in [0,21,78,252,4092]:
    data=bytes((131*i+17)%256 for i in range(n));encoded=check(data)
    for decode in [False,True]:add(f'base58check-{("decode" if decode else "encode")}-{n}','Base58Check',data,encoded,decode)
(HERE/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print('Generated',len(cases),'workloads')
# Additional scalar/limb-transition workloads keep the original manifest stable.
start=len(cases)
for n in [2,4,7,8,9,10,11,12]:
    data=bytes((131*i+17)%256 for i in range(n));encoded=encode(data)
    for decode in [False,True]:add(f'base58-{("decode" if decode else "encode")}-{n}-pattern','Base58',data,encoded,decode)
(HERE/'small-cases.json').write_text(json.dumps({'cases':cases[start:]},indent=2)+'\n')
(HERE/'broad-cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print('Generated',len(cases)-start,'additional transition workloads')
