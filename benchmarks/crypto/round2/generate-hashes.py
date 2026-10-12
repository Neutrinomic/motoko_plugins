#!/usr/bin/env python3
"""Additional round-two hash boundary and incremental cases; independent byte oracles."""
import hashlib, json, sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent
sys.path.insert(0,str(BENCH))
from common import actor, blob
cases=[]

def add(name,plugin,module,decls,operation,expected,configure='',notes=''):
    target=HERE/'hash-cases'/name/'native/main.mo'
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(actor(f'import H "mo:fast/{module}";',decls,configure,operation))
    cases.append(dict(name=name,family=plugin,implementation='native',comparison='round2-same-public-api',plugins=[plugin],expected_hex=expected.hex(),source=target.relative_to(BENCH).as_posix(),notes=notes))

sizes=[0,1,32,55,56,63,64,65,111,112,127,128,129,1024,16384]
for algorithm,module,plugin,method,creator in [('sha256','SHA256','sha256','digest',None),('sha512','SHA512','sha512','digest','Digest()'),('sha384','SHA512','sha512','digest384','Digest384()'),('ripemd160','RIPEMD160','ripemd160','digest','Digest()')]:
    for n in sizes:
        data=bytes(i%251 for i in range(n))
        add(f'{algorithm}-{n}',plugin,module,f'transient let input : Blob = {blob(data)};',f'result := H.{method}(input);',hashlib.new(algorithm,data).digest(),notes='Input prepared outside measurement. Independent Python hashlib oracle.')
    if creator:
        for n,chunk in [(0,1),(64,1),(129,17),(1024,256),(16384,1024)]:
            data=bytes(i%251 for i in range(n))
            chunks='['+','.join(blob(data[i:i+chunk]) for i in range(0,n,chunk))+']'
            decls=f'transient let chunks : [Blob] = {chunks}; transient var state = H.{creator};'
            add(f'{algorithm}-stream-{n}-chunks{chunk}',plugin,module,decls,'for(chunk in chunks.vals()){ignore state.write(chunk)};result := state.sum();',hashlib.new(algorithm,data).digest(),f'state := H.{creator};','State creation and chunk construction excluded; all updates and sum measured.')

vectors={int(s[0]):s[1:] for line in (BENCH/'fixtures/blake3-official-vectors.txt').read_text().splitlines() if (s:=line.split())}
key=b'whats the Elvish word for friend'
context='BLAKE3 2019-12-27 16:29:52 test vectors context'
unwrap=lambda op:f'switch({op}){{case(#ok(value))value;case(#err(_))Prim.trap("unexpected error")}}'
for n in [0,1,63,64,65,1023,1024,1025,2048,8192,16384]:
    if n not in vectors:continue
    data=bytes(i%251 for i in range(n));decls=f'transient let input : Blob = {blob(data)};'
    add(f'blake3-{n}','blake3','BLAKE3',decls,'result := H.digest(input);',bytes.fromhex(vectors[n][0][:64]),notes='Official BLAKE3 test-vector input pattern and digest.')
    if n in [0,64,1024,16384]:
        add(f'blake3-keyed-{n}','blake3','BLAKE3',decls+f'transient let key : Blob = {blob(key)};',f'result := {unwrap("H.keyedHash(key,input)")};',bytes.fromhex(vectors[n][1][:64]))
        add(f'blake3-derive-{n}','blake3','BLAKE3',decls,f'result := H.deriveKey("{context}",input);',bytes.fromhex(vectors[n][2][:64]))
        add(f'blake3-xof-{n}-seek13-length100','blake3','BLAKE3',decls,f'result := {unwrap("H.xof(input,13,100)")};',bytes.fromhex(vectors[n][0])[13:113],notes='Official 131-byte output; seek crosses two compression output blocks.')
for n,chunk in [(0,1),(64,1),(1024,256),(8192,1024),(16384,1024)]:
    data=bytes(i%251 for i in range(n));chunks='['+','.join(blob(data[i:i+chunk]) for i in range(0,n,chunk))+']'
    decls=f'transient let chunks : [Blob] = {chunks}; transient var state = H.new();'
    op=f'for(chunk in chunks.vals()){{state := {unwrap("H.update(state,chunk)")}}};result := {unwrap("H.finalize(state)")};'
    add(f'blake3-stream-{n}-chunks{chunk}','blake3','BLAKE3',decls,op,bytes.fromhex(vectors[n][0][:64]),'state := H.new();','State creation and chunk construction excluded; immutable updates and finalize measured. Official independent digest.')
(HERE/'hash-cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(f'Generated {len(cases)} round-two hash workloads')
