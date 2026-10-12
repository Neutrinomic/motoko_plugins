#!/usr/bin/env python3
"""Generate hash, MAC and encoding benchmarks with independent expected bytes."""
import hashlib, hmac, json
from pathlib import Path
from common import actor, blob, save_case, HERE
ROOT=HERE.parents[1]
cases=[]

def add(name,family,impl,imports,decls,op,expected,plugins=(),out='result',typ='Blob',initial='""',configure='',notes='',comparison='blob-public-api'):
    case=dict(name=name,family=family,implementation=impl,comparison=comparison,plugins=list(plugins),expected_hex=expected.hex(),notes=notes)
    cases.append(save_case(case,actor(imports,decls,configure,op,out,typ,initial)))

def input_decls(n):
    return f'transient let input : Blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>({n}, func(i) {{Prim.natToNat8(i % 251)}}));'

vectors={int(s[0]):s[1:] for l in (ROOT/'plugins/blake3/runtime/tests/official-vectors.txt').read_text().splitlines() if (s:=l.split())}
(HERE/'fixtures').mkdir(exist_ok=True)
(HERE/'fixtures/blake3-official-vectors.txt').write_text((ROOT/'plugins/blake3/runtime/tests/official-vectors.txt').read_text())
for n in [0,32,64,1024,16384]:
    data=bytes(i%251 for i in range(n)); decls=input_decls(n)
    for name,algorithm,module,method,base in [('sha256','sha256','SHA256','digest','Sha256'),('sha512','sha512','SHA512','digest','Sha512'),('sha384','sha384','SHA512','digest384','Sha512')]:
        expected=hashlib.new(algorithm,data).digest();plugin='sha256' if name=='sha256' else 'sha512'
        add(f'{name}-{n}',plugin,'native',f'import H "mo:fast/{module}";',decls,f'result := H.{method}(input);',expected,[plugin])
        add(f'{name}-{n}',plugin,'mops-sha2',f'import H "mo:sha2/{base}";',decls,f'result := H.fromBlob(#{algorithm},input);',expected)
    expected=hashlib.new('ripemd160',data).digest()
    add(f'ripemd160-{n}','ripemd160','native','import H "mo:fast/RIPEMD160";',decls,'result := H.digest(input);',expected,['ripemd160'])
    add(f'ripemd160-{n}','ripemd160','mops-bitcoin','import H "mo:bitcoin/Ripemd160";',decls,'result := Prim.arrayToBlob(H.hash(Prim.blobToArray(input)));',expected,notes='Blob to array input and array to Blob result conversions included for equivalent public Blob API.')
    if n in vectors:
        expected=bytes.fromhex(vectors[n][0][:64])
        add(f'blake3-{n}','blake3','native','import H "mo:fast/BLAKE3";',decls,'result := H.digest(input);',expected,['blake3'])
        add(f'blake3-{n}','blake3','mops-blake3','import H "mo:blake3";',decls,'result := H.digest(input);',expected)
    key=bytes(range(32)); kd=decls+f'\ntransient let key : Blob = {blob(key)};'
    for mode in ['sha256','sha512']:
        expected=hmac.digest(key,data,mode)
        add(f'hmac-{mode}-{n}','hmac-sha2','native','import H "mo:fast/HMAC";',kd,f'result := H.{mode}(key,input);',expected,['hmac-sha2'])
        add(f'hmac-{mode}-{n}','hmac-sha2','mops-bitcoin','import H "mo:bitcoin/Hmac";',kd,f'let mac = H.{mode}(Prim.blobToArray(key)); mac.writeArray(Prim.blobToArray(input)); result := mac.sum();',expected,notes='One-shot includes key preparation and Blob-to-array conversions.')
# Raw representation comparison separately avoids attributing array conversion to kernels.
for n in [64,1024,16384]:
    data=bytes(i%251 for i in range(n));expected=hashlib.new('ripemd160',data).digest()
    decls=f'transient let input : [Nat8] = Prim.Array_tabulate<Nat8>({n},func(i){{Prim.natToNat8(i % 251)}});'
    add(f'ripemd160-{n}-prepared-representation','ripemd160','mops-bitcoin','import H "mo:bitcoin/Ripemd160";',decls,'result := H.hash(input);',expected,out='Prim.arrayToBlob(result)',typ='[Nat8]',initial='[]',comparison='prepared-representation',notes='Array input is prepared outside measurement; array output conversion is outside measurement. Compare against native Blob API conservatively.')
# Keyed BLAKE3 and context derivation use official vectors. Broken Mops derive_key is excluded.
key=b'whats the Elvish word for friend';context='BLAKE3 2019-12-27 16:29:52 test vectors context';n=1024
for mode,index in [('keyed',1),('derive',2)]:
    expected=bytes.fromhex(vectors[n][index][:64]);decls=input_decls(n)+f'\ntransient let key : Blob = {blob(key)};'
    if mode=='keyed':
        add('blake3-keyed-1024','blake3','native','import H "mo:fast/BLAKE3";',decls,'result := switch(H.keyedHash(key,input)){case(#ok(x))x;case(#err(_))Prim.trap("keyed")};',expected,['blake3'])
        add('blake3-keyed-1024','blake3','mops-blake3','import H "mo:blake3";',decls,'result := H.keyed_hash(key,input);',expected)
    else:add('blake3-derive-1024','blake3','native','import H "mo:fast/BLAKE3";',decls,f'result := H.deriveKey("{context}",input);',expected,['blake3'],notes='Absolute cost only: Mops 0.1.2 ignores context so no equivalent baseline.')
# Small Bitcoin-size Base58 records; independent Python integer radix conversion.
alphabet='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
def b58(data):
    zeros=len(data)-len(data.lstrip(b'\0'));number=int.from_bytes(data,'big');out=''
    while number:number,remainder=divmod(number,58);out=alphabet[remainder]+out
    return '1'*zeros+out
for n in [25,82,256]:
    data=bytes(i%251 for i in range(n));text=b58(data);decls=f'transient let input : Blob = {blob(data)};'
    for impl,path,plugins,arg in [('native','fast/Base58',['base58'],'input'),('mops-bitcoin','bitcoin/Base58',[],'Prim.blobToArray(input)')]:
        add(f'base58-encode-{n}','base58',impl,f'import B "mo:{path}";',decls,f'result := B.encode({arg});',text.encode(),plugins,out='Prim.encodeUtf8(result)',typ='Text',initial='""')
    add(f'base58-decode-{n}','base58','native','import B "mo:fast/Base58";',f'transient let input = "{text}";','result := switch(B.decode(input)){case(#ok(x))x;case(#err(_))Prim.trap("decode")};',data,['base58'])
    add(f'base58-decode-{n}','base58','mops-bitcoin','import B "mo:bitcoin/Base58";',f'transient let input = "{text}";','result := Prim.arrayToBlob(B.decode(input));',data,notes='Result array-to-Blob conversion included.')
# Independent BIP173/BIP350 checksum implementation.
chars='qpzry9x8gf2tvdw0s3jn54khce6mua7l'
def bech32(hrp,values,const):
    chk=1
    for value in [ord(c)>>5 for c in hrp]+[0]+[ord(c)&31 for c in hrp]+list(values)+[0]*6:
        top=chk>>25;chk=((chk&0x1ffffff)<<5)^value
        for i,g in enumerate([0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3]):
            if top>>i&1:chk^=g
    chk^=const
    return hrp+'1'+''.join(chars[v] for v in values)+''.join(chars[(chk>>(5*(5-i)))&31] for i in range(6))
for n in [33,53]:
    data=bytes(i%32 for i in range(n))
    for variant,const in [('bech32',1),('bech32m',0x2bc830a3)]:
        text=bech32('bc',data,const);decls=f'transient let input : Blob = {blob(data)};'
        add(f'{variant}-encode-{n}','bech32','native','import B "mo:fast/Bech32";',decls,f'result := switch(B.encode("bc",input,#{variant})){{case(#ok(x))x;case(#err(_))Prim.trap("encode")}};',text.encode(),['bech32'],out='Prim.encodeUtf8(result)',typ='Text',initial='""')
        add(f'{variant}-encode-{n}','bech32','mops-bitcoin','import B "mo:bitcoin/Bech32";',decls,f'result := B.encode("bc",Prim.blobToArray(input),#{variant.upper()});',text.encode(),out='Prim.encodeUtf8(result)',typ='Text',initial='""')
        add(f'{variant}-decode-{n}','bech32','native','import B "mo:fast/Bech32";',f'transient let input = "{text}";','result := switch(B.decode(input)){case(#ok(x)){assert x.hrp == "bc";x.data};case(#err(_))Prim.trap("decode")};',data,['bech32'])
        add(f'{variant}-decode-{n}','bech32','mops-bitcoin','import B "mo:bitcoin/Bech32";',f'transient let input = "{text}";','result := switch(B.decode(input)){case(#ok((_,hrp,data))){assert hrp == "bc";Prim.arrayToBlob(data)};case(#err(_))Prim.trap("decode")};',data)
# Prepared HMAC key state excludes reusable key setup from the measured operation.
for n in [64,1024]:
    data=bytes(i%251 for i in range(n));key=bytes(range(32));decls=input_decls(n)+f'\ntransient let key : Blob = {blob(key)};'
    for mode in ['sha256','sha512']:
        expected=hmac.digest(key,data,mode);suffix='Sha256' if mode=='sha256' else 'Sha512'
        add(f'hmac-{mode}-prepared-{n}','hmac-sha2','native','import H "mo:fast/HMAC";',decls+f'\ntransient var prepared = H.prepare{suffix}(key);',f'result := prepared.digest(input);',expected,['hmac-sha2'],configure=f'prepared := H.prepare{suffix}(key);',notes='Prepared key reuse: precompress key pads outside measured interval; each trial uses a fresh canister and fresh message.',comparison='prepared-key-blob-api')
        add(f'hmac-{mode}-prepared-{n}','hmac-sha2','mops-bitcoin','import H "mo:bitcoin/Hmac";',decls+f'\ntransient var prepared = H.{mode}(Prim.blobToArray(key));','prepared.writeArray(Prim.blobToArray(input));result := prepared.sum();',expected,configure=f'prepared := H.{mode}(Prim.blobToArray(key));',notes='Hmac constructor performs reusable key preparation outside interval. Blob input conversion included.',comparison='prepared-key-blob-api')
# Incremental algorithms: four prebuilt chunks total1024 bytes; object/state setup
# is excluded, but every update plus final output is measured.
data=bytes(i%251 for i in range(1024))
chunks='['+','.join(blob(data[i:i+256]) for i in range(0,1024,256))+']'
decls=f'transient let chunks : [Blob] = {chunks};'
for algorithm,module,plugin,baseline,creator,write in [('sha512','SHA512','sha512','sha2/Sha512','Digest(#sha512)','writeBlob'),('ripemd160','RIPEMD160','ripemd160','bitcoin/Ripemd160','Digest()','write')]:
    expected=hashlib.new(algorithm,data).digest()
    nativeop='for(chunk in chunks.vals()){ignore state.write(chunk)}; result := state.sum();'
    add(f'{algorithm}-stream4x256',plugin,'native',f'import H "mo:fast/{module}";',decls+'\ntransient var state = H.Digest();',nativeop,expected,[plugin],configure='state := H.Digest();',comparison='incremental-prepared-state',notes='State creation outside interval, four Blob chunks update plus sum included; chunk construction excluded.')
    baseop=f'for(chunk in chunks.vals()){{state.{write}('+('chunk' if algorithm=='sha512' else 'Prim.blobToArray(chunk)')+');}; result := '+('state.sum();' if algorithm=='sha512' else 'Prim.arrayToBlob(state.sum());')
    add(f'{algorithm}-stream4x256',plugin,'mops-'+('sha2' if algorithm=='sha512' else 'bitcoin'),f'import H "mo:{baseline}";',decls+f'\ntransient var state = H.{creator};',baseop,expected,configure=f'state := H.{creator};',comparison='incremental-prepared-state',notes='Native public input is Blob; baseline array conversions included where required.')
expected=bytes.fromhex(vectors[1024][0][:64])
add('blake3-stream4x256','blake3','native','import H "mo:fast/BLAKE3";',decls+'\ntransient var state = H.new();','for(chunk in chunks.vals()){state := switch(H.update(state,chunk)){case(#ok(x))x;case(#err(_))Prim.trap("update")}};result := switch(H.finalize(state)){case(#ok(x))x;case(#err(_))Prim.trap("finalize")};',expected,['blake3'],configure='state := H.new();',comparison='incremental-prepared-state',notes='Immutable2816-byte state allocated per update; bounded state size, not allocation-free.')
add('blake3-stream4x256','blake3','mops-blake3','import H "mo:blake3";',decls+'\ntransient var state = H.init(null);','for(chunk in chunks.vals()){H.update(state,chunk)};result := H.finalize(state);',expected,configure='state := H.init(null);',comparison='incremental-prepared-state',notes='Totalinput1024 stays within supported baseline singlechunk; larger baseline streams excluded after official-vector failure.')
(HERE/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(f'Generated {len(cases)} primitive implementations')
