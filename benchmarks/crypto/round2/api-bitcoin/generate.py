#!/usr/bin/env python3
"""Public Bitcoin API fixtures: independent Python arithmetic/wire/hash oracles.

Every exported callable (including returned closures) gets an isolated actor.
No expected output is computed by a plugin or by the measured Motoko package.
The common actor keeps output encoding and fixture preparation outside timing.
"""
import hashlib
import hmac
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
BENCH = HERE.parents[1]
sys.path.insert(0, str(BENCH))
from common import actor, blob, save_case

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

ec = module('oracle_curve', BENCH / 'generate-curves.py')
tx = module('oracle_tx', BENCH / 'generate-bitcoin-tx.py')
curve = ec.CURVES['secp256k1']
add = lambda p, q: ec.ec_add(p, q, curve['p'])
mul = lambda n, p=curve['g']: ec.multiply(p, n, add)
sha = lambda b: hashlib.sha256(b).digest()
double = lambda b: sha(sha(b))
hash160 = lambda b: hashlib.new('ripemd160', sha(b)).digest()
tagged = lambda tag, b: sha(sha(tag.encode()) * 2 + b)
sec1 = lambda p: bytes([2 | (p[1] & 1)]) + p[0].to_bytes(32, 'big')
B58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'

def b58(b):
    n = int.from_bytes(b, 'big')
    out = ''
    while n:
        n, r = divmod(n, 58)
        out = B58[r] + out
    return '1' * (len(b) - len(b.lstrip(b'\0'))) + out

def b58decode(s):
    n = 0
    for c in s:
        n = n * 58 + B58.index(c)
    return b'\0' * (len(s)-len(s.lstrip('1'))) + n.to_bytes((n.bit_length()+7)//8, 'big')

def check58(b):
    return b58(b + double(b)[:4])

def segwit(version, program):
    acc = bits = 0
    values = [version]
    for b in program:
        acc = acc << 8 | b
        bits += 8
        while bits >= 5:
            bits -= 5
            values.append(acc >> bits & 31)
    if bits:
        values.append(acc << (5-bits) & 31)
    hrp = 'bc'
    chk = 1
    for v in [ord(c)>>5 for c in hrp] + [0] + [ord(c)&31 for c in hrp] + values + [0]*6:
        top = chk >> 25
        chk = ((chk & 0x1ffffff) << 5) ^ v
        for i, g in enumerate([0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]):
            if top >> i & 1:
                chk ^= g
    chk ^= 1 if version == 0 else 0x2bc830a3
    return hrp + '1' + ''.join('qpzry9x8gf2tvdw0s3jn54khce6mua7l'[v] for v in values + [(chk >> (5*(5-i)))&31 for i in range(6)])

def schnorr(secret, message, aux):
    point = mul(secret)
    d = secret if point[1] % 2 == 0 else curve['n'] - secret
    t = bytes(a ^ b for a,b in zip(d.to_bytes(32,'big'), tagged('BIP0340/aux', aux)))
    k = int.from_bytes(tagged('BIP0340/nonce', t + point[0].to_bytes(32,'big') + message), 'big') % curve['n']
    assert k
    r = mul(k)
    if r[1] % 2: k = curve['n'] - k
    challenge = int.from_bytes(tagged('BIP0340/challenge', r[0].to_bytes(32,'big') + point[0].to_bytes(32,'big') + message), 'big') % curve['n']
    signature = r[0].to_bytes(32,'big') + ((k + challenge*d) % curve['n']).to_bytes(32,'big')
    check = add(mul(int.from_bytes(signature[32:], 'big')), mul(curve['n']-challenge, (point[0], point[1] if point[1]%2 == 0 else curve['p']-point[1])))
    assert check[0] == r[0] and check[1] % 2 == 0
    return signature

UN = '''func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};'''
EXTRA = 'import BA "mo:core/Array";\nimport BB "mo:core/Blob";'
CASES = []
ROWS = []
GROUP = {'Hash':['sha256','ripemd160'], 'Address':['sha256','ripemd160','secp256k1','base58','bech32'], 'Bip32':['sha256','ripemd160','hmac-sha2','secp256k1','base58'], 'Script':['sha256'], 'Transaction':['sha256']}
VALIDATED = {'Bip32.'+f for f in ['fromPublicKey','fingerprint','serialize','deriveChild','derivePath','deriveTextPath','parsePath']} | {'Script.'+f for f in ['pushData','p2pkh','p2sh','witnessProgram','p2wpkh','p2wsh','p2tr','tapLeafHash','tapBranchHash']}
NODE_VALIDATOR='''
transient let parentFingerprint : [Nat8] = [0,0,0,0];
func validateNode(key:B.ExtendedPublicKey, fingerprint:[Nat8]) {
  assert key.chaincode.size()==32;
  assert fingerprint.size()==4;
  if(key.depth==0) { assert key.index==0 and fingerprint==[0,0,0,0] };
  assert key.key.size()==33;
  let point=some(VF.fromBytes(key.key,VC.secp256k1));
  let canonical=VF.toBytes(point,true);
  assert canonical==key.key;
};'''
STRICT_PATH='''
func strictPath(path:Text):?[Nat32] {
  let segments=BA.fromIter(VT.split(path,#char '/'));
  if(segments.size()==0) return null;
  let start:Nat=if(segments[0]=="m" or segments[0]=="M")1 else 0;
  let size=segments.size()-start;
  if(size > 255)return null;
  if(size==0)return ?[];
  var normalized="";
  var i=start;
  while(i < segments.size()) {
    let s=segments[i];
    if(s.size()==0)return null;
    for(c in s.chars()) {if(c < '0' or c > '9')return null};
    if(i > start)normalized#="/";
    normalized#=s;
    i+=1;
  };
  let indices=switch(B.arrayPathFromString(normalized)){case(?v)v;case(null)return null};
  for(index in indices.values()) {if(index>=0x80000000)return null};
  ?indices
};'''

def validate_peer(api, op, declarations, imports, notes):
    """Retain published computational primitives; add native input-contract checks."""
    if api in {'Bip32.fromPublicKey','Bip32.fingerprint'}:
        op=('assert chain.size()==32;' if api.endswith('fromPublicKey') else '')+'''assert key.size()==33 or key.size()==65;
let point=some(F.fromBytes(key,C.secp256k1));
let encoded=F.toBytes(point,key.size()==33);assert encoded==key;
let canonical=if(key.size()==33)encoded else F.toBytes(point,true);'''+('result := ?B.ExtendedPublicKey(canonical,chain,0,0,null);' if api.endswith('fromPublicKey') else 'let h=H.hash160(canonical);result := BA.tabulate<Nat8>(4,func(i){h[i]});')
    elif api in {'Bip32.serialize','Bip32.deriveChild','Bip32.derivePath','Bip32.deriveTextPath'}:
        imports+='\nimport VF "mo:bitcoin/ec/Affine";\nimport VC "mo:bitcoin/ec/Curves";'
        declarations+=NODE_VALIDATOR
        prefix='validateNode(parent,parentFingerprint);'
        if api.endswith('deriveChild'):prefix+='assert parent.depth < 255;'
        if api.endswith('derivePath'):prefix+='assert Prim.nat8ToNat(parent.depth)+2<=255;'
        if api.endswith('deriveTextPath'):
            imports+='\nimport VT "mo:core/Text";'
            declarations+=STRICT_PATH+'\ntransient let path="m/0/1";'
            op='switch(path.chars().next()){case(?\'m\' or ?\'M\'){assert parent.depth==0};case(_) {}};let indices=some(strictPath(path));'+prefix+'assert Prim.nat8ToNat(parent.depth)+indices.size()<=255;result := ?some(parent.derivePath(#array(indices)));'
        else:op=prefix+op
    elif api=='Bip32.parsePath':
        imports+='\nimport VT "mo:core/Text";'
        declarations+=STRICT_PATH
        op='result := some(strictPath("m/0/1"));'
    elif api.startswith('Script.'):
        fn=api.split('.')[1]
        if fn=='tapLeafHash':
            imports='import H "mo:bitcoin/Hash";\nimport U "mo:bitcoin/ByteUtils";'
            declarations=f'transient let rawScript:[Nat8]=Prim.blobToArray({blob(script)});transient let leafVersion:Nat8=0xc0;'
            op='assert leafVersion & 1 == 0;assert rawScript.size()<=0xffff_ffff_ffff_ffff;result := H.taggedHash(BA.concat([leafVersion],BA.concat(U.writeVarint(rawScript.size()),rawScript)),"TapLeaf");'
        elif fn=='tapBranchHash':
            op='assert left.size()==32 and right.size()==32;'+op
        else:
            data={'pushData':bytes(range(80)),'p2pkh':keyhash,'p2sh':keyhash,'witnessProgram':message,'p2wpkh':keyhash,'p2wsh':message,'p2tr':output_x}[fn]
            declarations=f'transient let data:[Nat8]=Prim.blobToArray({blob(data)});'
            encoded='S.toBytes('
            if fn=='pushData':
                build='''func build(data:[Nat8]):[Nat8] {
let n=data.size();assert n<=0xffff_ffff;
let instructions:S.Script=if(n==0){[#opcode(#OP_0)]}
else if(n==1 and data[0]==0x81){[#opcode(#OP_1NEGATE)]}
else if(n==1 and data[0]>=1 and data[0]<=16) {
let op:S.Opcode=switch(data[0]) {case(1)#OP_1;case(2)#OP_2;case(3)#OP_3;case(4)#OP_4;case(5)#OP_5;case(6)#OP_6;case(7)#OP_7;case(8)#OP_8;case(9)#OP_9;case(10)#OP_10;case(11)#OP_11;case(12)#OP_12;case(13)#OP_13;case(14)#OP_14;case(15)#OP_15;case(_)#OP_16};[#opcode(op)]
} else if(n < 76){[#data(data)]} else if(n<=255){[#opcode(#OP_PUSHDATA1),#data(data)]} else if(n<=65535){[#opcode(#OP_PUSHDATA2),#data(data)]} else { [#opcode(#OP_PUSHDATA4),#data(data)] };
let encoded=S.toBytes(instructions);
let start:Nat=if(encoded[0] < 253)1 else if(encoded[0]==253)3 else if(encoded[0]==254)5 else 9;
BA.tabulate<Nat8>(encoded.size()-start,func(i){encoded[start+i]})
};'''
                declarations+=build
                op='result := build(data);'
            else:
                size=20 if fn in ['p2pkh','p2sh','p2wpkh'] else 32
                prefix=f'assert data.size()=={size};'
                if fn=='witnessProgram':
                    declarations+='transient let version:Nat8=2;'
                    prefix='assert version<=16;assert data.size()>=2 and data.size()<=40;if(version==0){assert data.size()==20 or data.size()==32};'
                if fn=='p2pkh':inst='[#opcode(#OP_DUP),#opcode(#OP_HASH160),#data(data),#opcode(#OP_EQUALVERIFY),#opcode(#OP_CHECKSIG)]'
                elif fn=='p2sh':inst='[#opcode(#OP_HASH160),#data(data),#opcode(#OP_EQUAL)]'
                else:
                    opcode='#OP_1' if fn=='p2tr' else '#OP_2' if fn=='witnessProgram' else '#OP_0'
                    if fn=='witnessProgram':
                        prefix+='let opcode:S.Opcode=switch(version){case(0)#OP_0;case(1)#OP_1;case(2)#OP_2;case(3)#OP_3;case(4)#OP_4;case(5)#OP_5;case(6)#OP_6;case(7)#OP_7;case(8)#OP_8;case(9)#OP_9;case(10)#OP_10;case(11)#OP_11;case(12)#OP_12;case(13)#OP_13;case(14)#OP_14;case(15)#OP_15;case(_)#OP_16};'
                        opcode='opcode'
                    inst=f'[#opcode({opcode}),#data(data)]'
                op=prefix+f'let encoded=S.toBytes({inst});result := BA.tabulate<Nat8>(encoded.size()-1,func(i){{encoded[i+1]}});'
    notes=('Pure Motoko adapter uses published package primitives. '+
           ('Measured chain-code/fingerprint lengths, root metadata, compressed key length and canonical SEC1 point validation precede the package operation. Path depth and strict nonhardened text policy are checked where applicable.' if api in {'Bip32.serialize','Bip32.deriveChild','Bip32.derivePath','Bip32.deriveTextPath'} else
            'Measured canonical SEC1 decoding and normalization; fromPublicKey also checks chain-code length.' if api in {'Bip32.fromPublicKey','Bip32.fingerprint'} else
            'Measured adapter enforces strict nonhardened syntax, at most 255 path components and the same 2^31 index bound before returning package-parsed indices.' if api=='Bip32.parsePath' else
            'Measured adapter validates raw-script length and even leaf version, then composes package CompactSize and tagged-hash APIs on raw script bytes.' if api=='Script.tapLeafHash' else
            'Measured adapter validates both 32-byte child commitments before lexicographic sorting and package tagged hashing.' if api=='Script.tapBranchHash' else
            'Measured adapter checks applicable data lengths and witness version constraints, constructs Script instructions and removes the serializer CompactSize prefix inside timing. PUSHDATA1/2/4 and minimal integer pushes are selected from input length/value.')+
           ' Distinct validated case identity; output encoding remains outside timing.')
    return op,declarations,imports,notes

def emit(api, expected, op, declarations='', configure='', typ='Blob', initial='""', out='result', impl='native', imports='', notes=''):
    group, fun = api.split('.', 1)
    name = 'api-bitcoin-' + group.lower() + '-' + fun.replace('.', '-').replace('()', '').lower()
    comparison=name
    if impl=='mops-bitcoin' and api in VALIDATED:
        name+='-validated'
        op,declarations,imports,notes=validate_peer(api,op,declarations,imports,notes)
    imports = (f'import M "mo:fast/Bitcoin/{group}";\n' if impl == 'native' else '') + EXTRA + '\n' + imports
    case = dict(name=name, family='bitcoin', implementation=impl, comparison=comparison, public_api='Bitcoin/'+api,
                plugins=GROUP[group] if impl == 'native' else [], expected_hex=expected.hex(), notes=notes,
                fixture_provenance='round2/api-bitcoin/generate.py: independent hashlib, HMAC, affine secp256k1, BIP32 public derivation, BIP173/350 checksum and Bitcoin wire encodings; no measured implementation outputs',
                operations_per_sample=1)
    source=actor(imports, UN+'\n'+declarations, configure, op, out, typ, initial).replace('BA.concat(', 'BA.concat<Nat8>(')
    CASES.append(save_case(case, source, 'round2/api-bitcoin/actors'))
    if impl == 'native':
        ROWS.append(dict(api='Bitcoin/'+api, case=name, baseline=None, notes=notes))
    else:
        next(r for r in ROWS if r['api']=='Bitcoin/'+api)['baseline'] = impl

def pair(api, expected, op, imports, **kwargs):
    emit(api, expected, op, impl='mops-bitcoin', imports=imports, **kwargs)

def text_case(api, expected, op, **kw):
    emit(api, expected.encode(), op, typ='Text', out='Prim.encodeUtf8(result)', **kw)

secret = ec.SECRET
point = mul(secret)
key = sec1(point)
keyhash = hash160(key)
message = sha(b'Bitcoin public API benchmark full-width fixture')
script = b'\x20' + point[0].to_bytes(32,'big') + b'\xac'
xonly = point[0].to_bytes(32,'big')
tweak = int.from_bytes(tagged('TapTweak', xonly), 'big')
assert tweak < curve['n']
internal = (point[0], point[1] if point[1]%2 == 0 else curve['p']-point[1])
output = add(internal, mul(tweak))
output_x = output[0].to_bytes(32,'big')
tweaked_secret = ((secret if point[1]%2 == 0 else curve['n']-secret) + tweak) % curve['n']
assert mul(tweaked_secret) == output
aux = sha(b'Explicit deterministic BIP340 auxiliary randomness')
sig = schnorr(tweaked_secret, message, aux)
decl = f'transient let input : Blob = {blob(message)};'

for fn, expected, baseline in [('hash160',hash160(message),'hash160'), ('sha256d',double(message),'doubleSHA256'), ('digest256',double(message),'doubleSHA256')]:
    emit('Hash.'+fn, expected, f'result := M.{fn}(input);',decl)
    pair('Hash.'+fn, expected, f'result := H.{baseline}(input);','import H "mo:bitcoin/Hash";',declarations=f'transient let input : [Nat8] = Prim.blobToArray({blob(message)});',typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)')
expected = tagged('TapTweak', message)
emit('Hash.taggedHash',expected,'result := M.taggedHash("TapTweak",input);',decl)
pair('Hash.taggedHash',expected,'result := H.taggedHash(input,"TapTweak");','import H "mo:bitcoin/Hash";',declarations=f'transient let input : [Nat8] = Prim.blobToArray({blob(message)});',typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)')
emit('Hash.taggedHasher',expected,'result := ?M.taggedHasher("TapTweak");',decl,typ='?(Blob -> Blob)',initial='null',out='some(result)(input)',notes='Measure closure construction only; invoke it outside measurement to verify retained tag state.')
emit('Hash.taggedHasher.call',expected,'result := cached(input);',decl+'\ntransient var cached = M.taggedHasher("TapTweak");',configure='cached := M.taggedHasher("TapTweak");',notes='Measure returned closure invocation; tag preparation outside measurement.')
cached_import='import H "mo:sha2/Sha256";'
cached_def='''func taggedHasher(tag:Text) : Blob -> Blob {
let tagHash=H.fromBlob(#sha256,Prim.encodeUtf8(tag));
func(input:Blob):Blob {let d=H.Digest(#sha256);d.writeBlob(tagHash);d.writeBlob(tagHash);d.writeBlob(input);d.sum()}
};'''
pair('Hash.taggedHasher',expected,'result := ?taggedHasher("TapTweak");',cached_import,declarations=cached_def+decl,typ='?(Blob -> Blob)',initial='null',out='some(result)(input)',notes='Reusable tagged-hash closure composed from public pure-Motoko SHA256 APIs; construction times only tag digest and closure allocation.')
pair('Hash.taggedHasher.call',expected,'result := cached(input);',cached_import,declarations=cached_def+decl+'transient var cached=taggedHasher("TapTweak");',configure='cached := taggedHasher("TapTweak");',notes='Equivalent reusable-tag closure composition from public SHA256 APIs; tag digest prepared outside timing.')

text_case('Address.hrp','bcrt','result := M.hrp(#regtest);')
pair('Address.hrp',b'bcrt','result := hrp(network);','import T "mo:bitcoin/bitcoin/Types";',declarations='transient let network:T.Network=#Regtest;func hrp(network:T.Network):Text {switch network {case(#Mainnet)"bc";case(#Testnet)"tb";case(#Regtest)"bcrt"}};',typ='Text',out='Prim.encodeUtf8(result)',notes='Pure Motoko adapter maps published bitcoin network variants to BIP173 human-readable prefixes; package exports no named hrp helper.')
address = segwit(0,keyhash)
text_case('Address.encode',address,'result := unwrap(M.encode(#witness({version=0;program=input}),#mainnet));',declarations=f'transient let input : Blob = {blob(keyhash)};')
pair('Address.encode',address.encode(),'result := unwrap(S.encode("bc",{version=0;program=input}));','import S "mo:bitcoin/Segwit";',declarations=f'transient let input : [Nat8] = Prim.blobToArray({blob(keyhash)});',typ='Text',out='Prim.encodeUtf8(result)')
emit('Address.decode',b'\0'+keyhash,f'result := ?unwrap(M.decode("{address}",#mainnet));',typ='?M.Payload',initial='null',out='switch(some(result)){case(#witness v){BB.fromArray(BA.concat([v.version],BB.toArray(v.program)))};case(_)Prim.trap("kind")};')
pair('Address.decode',b'\0'+keyhash,f'let (hrp,v) = unwrap(S.decode("{address}")); assert hrp == "bc"; result := ?v;','import S "mo:bitcoin/Segwit";',typ='?{version:Nat8;program:[Nat8]}',initial='null',out='let v=some(result); Prim.arrayToBlob(BA.concat([v.version],v.program))',notes='Segwit decode plus expected-network check; same successful witness branch as native Address.decode.')
keydecl = f'transient let key : Blob = {blob(key)};'
for fn, value in [('p2pkh',check58(b'\0'+keyhash)), ('p2wpkh',address)]:
    text_case('Address.'+fn,value,f'result := unwrap(M.{fn}(key,#mainnet));',declarations=keydecl)
    imports='import F "mo:bitcoin/ec/Affine";\nimport C "mo:bitcoin/ec/Curves";\nimport H "mo:bitcoin/Hash";\nimport S "mo:bitcoin/Segwit";\nimport P "mo:bitcoin/bitcoin/P2pkh";'
    call='P.deriveAddress(#Mainnet,(key,C.secp256k1))' if fn=='p2pkh' else 'unwrap(S.encode("bc",{version=0;program=H.hash160(key)}))'
    pair('Address.'+fn,value.encode(),f'let point=some(F.fromBytes(key,C.secp256k1));assert F.isOnCurve(point);result := {call};',imports,declarations=f'transient let key : [Nat8] = Prim.blobToArray({blob(key)});',typ='Text',out='Prim.encodeUtf8(result)',notes='Baseline composition includes compressed point decode and on-curve validation inside timing, matching native validation on this canonical compressed fixture.')
for fn, value in [('p2sh',check58(b'\x05'+hash160(script))), ('p2wsh',segwit(0,sha(script)))]:
    text_case('Address.'+fn,value,f'result := unwrap(M.{fn}(script,#mainnet));',declarations=f'transient let script : Blob = {blob(script)};')
    if fn=='p2sh':
        op='result := B.encode(BA.concat([5],H.hash160(script)));'
        imports='import B "mo:bitcoin/Base58Check";\nimport H "mo:bitcoin/Hash";'
    else:
        op='result := unwrap(S.encode("bc",{version=0;program=BB.toArray(H.fromArray(#sha256,script))}));'
        imports='import S "mo:bitcoin/Segwit";\nimport H "mo:sha2/Sha256";'
    pair('Address.'+fn,value.encode(),op,imports,declarations=f'transient let script : [Nat8] = Prim.blobToArray({blob(script)});',typ='Text',out='Prim.encodeUtf8(result)',notes='Compose published hash and address-encoding APIs on the same script bytes.')
emit('Address.taprootOutputKey',bytes([output[1]&1])+output_x,'result := ?unwrap(M.taprootOutputKey(key,null));',f'transient let key : Blob = {blob(xonly)};',typ='?M.TaprootOutput',initial='null',out='let v=some(result); BB.fromArray(BA.concat([v.parity],BB.toArray(v.publicKey)))')
tapimports='import H "mo:bitcoin/Hash";\nimport C "mo:bitcoin/Common";\nimport Curve "mo:bitcoin/ec/Curves";\nimport T "mo:bitcoin/bitcoin/P2tr";'
tapop='let tweak=C.readBE256(H.taggedHash(key,"TapTweak"),0);assert tweak < Curve.secp256k1.r;let v=unwrap(T.tweakPublicKey(key,Curve.secp256k1.Fp(tweak)));'
pair('Address.taprootOutputKey',bytes([output[1]&1])+output_x,tapop+'result := ?v;',tapimports,declarations=f'transient let key:[Nat8]=Prim.blobToArray({blob(xonly)});',typ='?{bip340_public_key:[Nat8];is_even:Bool}',initial='null',out='let v=some(result); Prim.arrayToBlob(BA.concat([if(v.is_even)0 else 1],v.bip340_public_key))',notes='Public taggedHash+tweakPublicKey composition supports absent root; explicit scalar-order guard matches BIP341.')
emit('Address.taprootSecretKey',tweaked_secret.to_bytes(32,'big'),'result := unwrap(M.taprootSecretKey(secret,null));',f'transient let secret : Blob = {blob(secret.to_bytes(32,"big"))};',notes='Full-width local internal secret, empty Taproot tree; independent affine scalar oracle.')
emit('Address.signTaprootKeyPath',sig,'result := unwrap(M.signTaprootKeyPath(secret,null,digest,aux));',f'transient let secret : Blob = {blob(secret.to_bytes(32,"big"))};transient let digest : Blob={blob(message)};transient let aux : Blob={blob(aux)};',notes='Full local secret tweak and BIP340 signing of supplied digest; no extra prehash. No Schnorr API in bitcoin 0.2.1.')
for fn, k in [('p2trOutput',output_x), ('p2tr',xonly)]:
    args='key,#mainnet' if fn=='p2trOutput' else 'key,null,#mainnet'
    text_case('Address.'+fn,segwit(1,output_x),f'result := unwrap(M.{fn}({args}));',declarations=f'transient let key : Blob = {blob(k)};')
    if fn=='p2tr':
        pair('Address.'+fn,segwit(1,output_x).encode(),tapop+'result := unwrap(S.encode("bc",{version=1;program=v.bip340_public_key}));',tapimports+'\nimport S "mo:bitcoin/Segwit";',declarations=f'transient let key:[Nat8]=Prim.blobToArray({blob(k)});',typ='Text',out='Prim.encodeUtf8(result)')
    else:
        pair('Address.'+fn,segwit(1,output_x).encode(),'let p=some(F.fromBytes(BA.concat([2],key),C.secp256k1));assert F.isOnCurve(p);result := unwrap(S.encode("bc",{version=1;program=key}));','import F "mo:bitcoin/ec/Affine";\nimport C "mo:bitcoin/ec/Curves";\nimport S "mo:bitcoin/Segwit";',declarations=f'transient let key:[Nat8]=Prim.blobToArray({blob(k)});',typ='Text',out='Prim.encodeUtf8(result)',notes='Output point membership validation included in both implementations.')
legacy_addr=check58(b'\0'+keyhash)
legacy_script=b'\x76\xa9\x14'+keyhash+b'\x88\xac'
emit('Address.scriptPubKey',legacy_script,f'result := unwrap(M.scriptPubKey("{legacy_addr}",#mainnet));')
pair('Address.scriptPubKey',legacy_script,f'let decoded=unwrap(P.decodeAddress("{legacy_addr}"));assert decoded.network == #Mainnet;let s=unwrap(A.scriptPubKey(#p2pkh("{legacy_addr}")));let bytes=S.toBytes(s);result := BA.tabulate<Nat8>(bytes.size()-1,func(i){{bytes[i+1]}});','import P "mo:bitcoin/bitcoin/P2pkh";\nimport A "mo:bitcoin/bitcoin/Address";\nimport S "mo:bitcoin/bitcoin/Script";',typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)',notes='Baseline network validation+address script helper+raw script serialization; one-byte CompactSize removed inside measured adapter for this 25-byte script.')

# BIP32 official vector 2 root, independently decoded/derived in Python.
root='xpub661MyMwAqRbcFW31YEwpkMuc5THy2PSt5bDMsktWQcFF8syAmRUapSCGu8ED9W6oDMSgv6Zz8idoc4a6mr8BDzTJY47LJhkJ8UB7WEGuduB'
payload=b58decode(root)
assert double(payload[:-4])[:4] == payload[-4:]
payload=payload[:-4]
rootpub=payload[45:78]
chain=payload[13:45]

def ckd(payload,index):
    pub=payload[45:78]
    x=int.from_bytes(pub[1:],'big')
    y=pow((x*x*x+7)%curve['p'],(curve['p']+1)//4,curve['p'])
    if y%2 != pub[0]%2:y=curve['p']-y
    derived=hmac.digest(payload[13:45],pub+index.to_bytes(4,'big'),'sha512')
    child=add((x,y),mul(int.from_bytes(derived[:32],'big')))
    assert int.from_bytes(derived[:32],'big')<curve['n'] and child
    return payload[:4]+bytes([payload[4]+1])+hash160(pub)[:4]+index.to_bytes(4,'big')+derived[32:]+sec1(child)

child=ckd(payload,0)
child2=ckd(child,1)
assert check58(child)=='xpub69H7F5d8KSRgmmdJg2KhpAK8SR3DjMwAdkxj3ZuxV27CprR9LgpeyGmXUbC6wb7ERfvrnKZjXoUmmDznezpbZb7ap6r1D3tgFxHmwMkQTPH'
nodeout='Prim.encodeUtf8(unwrap(M.serialize(some(result))))'
nodedecl=f'transient let parent=unwrap(M.parse("{root}"));'
baseparent=f'transient let parent=some(B.parse("{root}",null));'
emit('Bip32.fromPublicKey',root.encode(),f'result := ?unwrap(M.fromPublicKey({blob(rootpub)},{blob(chain)},#mainnet));',typ='?M.ExtendedPublicKey',initial='null',out=nodeout,notes='All returned node metadata verified by serialization outside timing; validates compressed point inside public API.')
emit('Bip32.fingerprint',hash160(rootpub)[:4],f'result := unwrap(M.fingerprint({blob(rootpub)}));')
keyimports='import F "mo:bitcoin/ec/Affine";\nimport C "mo:bitcoin/ec/Curves";\nimport B "mo:bitcoin/Bip32";\nimport H "mo:bitcoin/Hash";'
keydec=f'transient let key:[Nat8]=Prim.blobToArray({blob(rootpub)});transient let chain:[Nat8]=Prim.blobToArray({blob(chain)});'
validate='let point=some(F.fromBytes(key,C.secp256k1));assert F.isOnCurve(point);'
pair('Bip32.fromPublicKey',root.encode(),validate+'result := ?B.ExtendedPublicKey(key,chain,0,0,null);',keyimports,declarations=keydec,typ='?B.ExtendedPublicKey',initial='null',out='Prim.encodeUtf8(some(result).serialize())',notes='Public affine validation and ExtendedPublicKey construction, canonical compressed point and 32-byte chain fixture; serialized record checked outside timing.')
pair('Bip32.fingerprint',hash160(rootpub)[:4],validate+'let h=H.hash160(key);result := BA.tabulate<Nat8>(4,func(i){h[i]});',keyimports,declarations=keydec,typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)',notes='Public affine validation plus HASH160 and fingerprint extraction inside timing.')
for fn,op,expected,dec in [('parse',f'M.parse("{root}")',root,''),('deriveChild','M.deriveChild(parent,0)',check58(child),nodedecl),('derivePath','M.derivePath(parent,[0,1])',check58(child2),nodedecl),('deriveTextPath','M.deriveTextPath(parent,"m/0/1")',check58(child2),nodedecl)]:
    emit('Bip32.'+fn,expected.encode(),f'result := ?unwrap({op});',dec,typ='?M.ExtendedPublicKey',initial='null',out=nodeout)
    bop={'parse':f'B.parse("{root}",null)','deriveChild':'parent.deriveChild(0)','derivePath':'parent.derivePath(#array([0,1]))','deriveTextPath':'parent.derivePath(#text("m/0/1"))'}[fn]
    pair('Bip32.'+fn,expected.encode(),f'result := ?some({bop});','import B "mo:bitcoin/Bip32";',declarations='' if fn=='parse' else baseparent,typ='?B.ExtendedPublicKey',initial='null',out='Prim.encodeUtf8(some(result).serialize())',notes='Published mainnet xpub vector; pure-Motoko derived objects retain validated parent. Output serialization outside timing.')
text_case('Bip32.serialize',root,'result := unwrap(M.serialize(parent));',declarations=nodedecl)
pair('Bip32.serialize',root.encode(),'result := parent.serialize();','import B "mo:bitcoin/Bip32";',declarations=baseparent,typ='Text',out='Prim.encodeUtf8(result)',notes='Native validates caller-built record; package method trusts its constructed class object. Retain costs, do not claim equal validation cost.')
emit('Bip32.parsePath',b'\x00\x00\x00\x00\x01\x00\x00\x00','result := unwrap(M.parsePath("m/0/1"));',typ='[Nat32]',initial='[]',out='Prim.arrayToBlob(BA.tabulate<Nat8>(result.size()*4,func(i){Prim.natToNat8(Prim.nat32ToNat(result[i/4] >> Prim.natToNat32((i%4)*8)) % 256)}))')
pair('Bip32.parsePath',b'\x00\x00\x00\x00\x01\x00\x00\x00','result := some(B.arrayPathFromString("m/0/1"));','import B "mo:bitcoin/Bip32";',typ='[Nat32]',initial='[]',out='Prim.arrayToBlob(BA.tabulate<Nat8>(result.size()*4,func(i){Prim.natToNat8(Prim.nat32ToNat(result[i/4] >> Prim.natToNat32((i%4)*8)) % 256)}))',notes='Same valid nonhardened path; package parser admits additional inputs rejected by native strict parser.')

for fn,expected,call in [('pushData',b'\x4c\x50'+bytes(range(80)),f'M.pushData({blob(bytes(range(80)))})'),('p2pkh',legacy_script,f'M.p2pkh({blob(keyhash)})'),('p2sh',b'\xa9\x14'+keyhash+b'\x87',f'M.p2sh({blob(keyhash)})'),('witnessProgram',b'\x52\x20'+message,f'M.witnessProgram(2,{blob(message)})'),('p2wpkh',b'\x00\x14'+keyhash,f'M.p2wpkh({blob(keyhash)})'),('p2wsh',b'\x00\x20'+message,f'M.p2wsh({blob(message)})'),('p2tr',b'\x51\x20'+output_x,f'M.p2tr({blob(output_x)})'),('tapLeafHash',tagged('TapLeaf',b'\xc0'+tx.field(script)),f'M.tapLeafHash({blob(script)},0xc0)'),('tapBranchHash',tagged('TapBranch',b''.join(sorted([message,sha(message)]))),f'M.tapBranchHash({blob(message)},{blob(sha(message))})')]:
    emit('Script.'+fn,expected,f'result := some({call});')
    if fn=='tapLeafHash':
        pair('Script.'+fn,expected,'result := P.leafHash(script);','import P "mo:bitcoin/bitcoin/P2tr";\nimport S "mo:bitcoin/bitcoin/Script";',declarations=f'transient let script : S.Script = [#data(Prim.blobToArray({blob(xonly)})),#opcode(#OP_CHECKSIG)];',typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)',notes='Current tapscript leaf version 0xc0; package takes parsed Script prepared outside timing, native takes raw bytes.')
    elif fn=='tapBranchHash':
        pair('Script.'+fn,expected,'let joined=if(BB.compare(left,right)==#less) BA.concat(BB.toArray(left),BB.toArray(right)) else BA.concat(BB.toArray(right),BB.toArray(left));result := H.taggedHash(joined,"TapBranch");','import H "mo:bitcoin/Hash";',declarations=f'transient let left:Blob={blob(message)};transient let right:Blob={blob(sha(message))};',typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)',notes='Compose public taggedHash with lexicographic child ordering; same fixed 32-byte validated fixture.')
    else:
        instructions={
            'pushData':f'[#opcode(#OP_PUSHDATA1),#data(Prim.blobToArray({blob(bytes(range(80)))}))]',
            'p2pkh':f'[#opcode(#OP_DUP),#opcode(#OP_HASH160),#data(Prim.blobToArray({blob(keyhash)})),#opcode(#OP_EQUALVERIFY),#opcode(#OP_CHECKSIG)]',
            'p2sh':f'[#opcode(#OP_HASH160),#data(Prim.blobToArray({blob(keyhash)})),#opcode(#OP_EQUAL)]',
            'witnessProgram':f'[#opcode(#OP_2),#data(Prim.blobToArray({blob(message)}))]',
            'p2wpkh':f'[#opcode(#OP_0),#data(Prim.blobToArray({blob(keyhash)}))]',
            'p2wsh':f'[#opcode(#OP_0),#data(Prim.blobToArray({blob(message)}))]',
            'p2tr':f'[#opcode(#OP_1),#data(Prim.blobToArray({blob(output_x)}))]',
        }[fn]
        pair('Script.'+fn,expected,f'let encoded=S.toBytes({instructions});result := BA.tabulate<Nat8>(encoded.size()-1,func(i){{encoded[i+1]}});','import S "mo:bitcoin/bitcoin/Script";',typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)',notes='Compose public Script serializer with instruction construction; remove its one-byte CompactSize prefix inside timing. Fixed valid lengths; baseline constructor does not provide native length-validation failures.')

inputs, outputs = tx.fixtures(10)
wire = tx.serialize(inputs,outputs)
nd = tx.native_declarations(inputs,outputs).replace('T.', 'M.')
bd, bc = tx.baseline_declarations(inputs,outputs)
bimports=tx.BASELINE_IMPORTS
emit('Transaction.serialize',wire,'result := some(M.serialize(tx,false));',nd)
pair('Transaction.serialize',wire,'result := some(tx).toBytesIgnoringWitness();',bimports,declarations=bd,configure=bc,typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)')
emit('Transaction.parse',wire,f'result := M.parse({blob(wire)});',typ='?M.Tx',initial='null',out='some(M.serialize(some(result),false))',notes='Parse all ten inputs/two outputs; reserialization only in output query.')
pair('Transaction.parse',wire,f'result := ?unwrap(T.fromBytes(({blob(wire)}:Blob).values()));',bimports,typ='?T.Transaction',initial='null',out='Prim.arrayToBlob(some(result).toBytesIgnoringWitness())',notes='Same valid wire transaction; serializers verify all parsed fields outside timing. Malformed-input contracts differ.')
for fn in ['txid','wtxid']:
    expected=double(wire)[::-1]
    emit('Transaction.'+fn,expected,f'result := some(M.{fn}(tx));',nd,notes='Ten-input transaction has no witness; txid and wtxid therefore match. Existing serializer workloads retain larger cases.')
    bop='result := some(tx).txid();' if fn=='txid' else 'let digest=H.doubleSHA256(some(tx).toBytes());result := BA.tabulate<Nat8>(digest.size(),func(i){digest[digest.size()-1-i]});'
    pair('Transaction.'+fn,expected,bop,bimports+'\nimport H "mo:bitcoin/Hash";',declarations=bd,configure=bc,typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)')
for fn, expected, call, bcall in [('signatureHashLegacy',tx.legacy(inputs,outputs,0),'M.signatureHashLegacy(tx,0,scriptCode,1)','some(tx).createP2pkhSignatureHash(script,0,1)'),('signatureHashSegwitV0',tx.segwit_v0(inputs,outputs,0),'M.signatureHashSegwitV0(tx,0,scriptCode,prevouts[0].value,1)',None),('signatureHashTaproot',tx.taproot(inputs,outputs,0),'M.signatureHashTaproot(tx,0,prevouts,0,null,null)','some(tx).createTaprootKeySpendSignatureHash(amounts,tapScript,0)')]:
    emit('Transaction.'+fn,expected,f'result := some({call});',nd,notes='Ten inputs, one complete public sighash call. Legacy ALL / BIP143 ALL / Taproot DEFAULT key path without annex. Equal prevout scripts fit Mops restricted API.')
    if bcall:
        pair('Transaction.'+fn,expected,f'result := {bcall};',bimports,declarations=bd,configure=bc,typ='[Nat8]',initial='[]',out='Prim.arrayToBlob(result)')
for fn,typ,expected,prepare,call in [('prepareSegwitV0','SegwitV0Hasher',tx.segwit_v0(inputs,outputs,0),'M.prepareSegwitV0(tx)','signatureHash(0,scriptCode,prevouts[0].value,1)'),('prepareTaproot','TaprootHasher',tx.taproot(inputs,outputs,0),'M.prepareTaproot(tx,prevouts)','signatureHash(0,0,null,null)')]:
    emit('Transaction.'+fn,expected,f'result := {prepare};',nd,typ='?M.'+typ,initial='null',out=f'some(some(result).{call})',notes='Measure reusable hasher creation/validation only; first digest invoked outside timing to verify returned state.')
    emit('Transaction.'+typ+'.signatureHash',expected,f'result := some(some(prepared).{call});',nd+f'\ntransient var prepared : ?M.{typ} = null;',configure=f'prepared := {prepare};',notes='First cold returned-method invocation, including lazy common hashes; prepare/validate outside timing. No prewarmed caches.')

assert len(ROWS) == 47, len(ROWS)
assert len({(c['name'],c['implementation']) for c in CASES}) == len(CASES)
(HERE/'cases.json').write_text(json.dumps({'cases':CASES},indent=2)+'\n')
(HERE/'validated-cases.json').write_text(json.dumps({'cases':[case for case in CASES if case['name'].endswith('-validated')]},indent=2)+'\n')
api_rows=[]
descriptions={
 'Hash.hash160':('SHA256 followed by RIPEMD160','32-byte message'),
 'Hash.sha256d':('Double SHA256','32-byte message'),
 'Hash.digest256':('Double SHA256 compatibility alias','32-byte message'),
 'Hash.taggedHash':('Compute BIP340 tagged SHA256','8-byte TapTweak tag + 32-byte message'),
 'Hash.taggedHasher':('Construct cached-tag hash closure','8-byte TapTweak tag; 32-byte check message outside timing'),
 'Hash.taggedHasher.call':('Invoke cached-tag hash closure','32-byte message; 8-byte tag prepared outside timing'),
 'Address.hrp':('Select regtest human-readable address prefix','1 regtest network variant'),
 'Address.encode':('Encode mainnet witness-v0 address','20-byte program'),
 'Address.decode':('Decode mainnet witness-v0 address and check network',f'{len(address)}-character address / 20-byte program'),
 'Address.p2pkh':('Validate compressed key and derive mainnet P2PKH address','33-byte compressed SEC1 public key'),
 'Address.p2sh':('HASH160 redeem script and encode mainnet P2SH address',f'{len(script)}-byte redeem script'),
 'Address.p2wpkh':('Validate compressed key and derive mainnet P2WPKH address','33-byte compressed SEC1 public key'),
 'Address.p2wsh':('SHA256 witness script and encode mainnet P2WSH address',f'{len(script)}-byte witness script'),
 'Address.taprootOutputKey':('Compute empty-tree Taproot output key and parity','32-byte internal x-only key'),
 'Address.taprootSecretKey':('Derive empty-tree Taproot signing scalar','32-byte full-width internal secret'),
 'Address.signTaprootKeyPath':('Tweak internal secret and BIP340-sign supplied key-path digest','32-byte secret + 32-byte digest + 32-byte auxiliary randomness'),
 'Address.p2trOutput':('Validate and encode tweaked mainnet Taproot output key','32-byte tweaked x-only key'),
 'Address.p2tr':('Tweak empty-tree internal key and encode mainnet Taproot address','32-byte internal x-only key'),
 'Address.scriptPubKey':('Decode and network-check P2PKH address, build locking script',f'{len(legacy_addr)}-character address / 25-byte output script'),
 'Bip32.fromPublicKey':('Validate and construct depth-zero mainnet extended public key','33-byte compressed key + 32-byte chain code'),
 'Bip32.fingerprint':('Validate compressed key and compute HASH160 fingerprint','33-byte compressed SEC1 public key / 4-byte result'),
 'Bip32.parse':('Parse and validate official BIP32 vector-2 root xpub',f'{len(root)}-character xpub / 78-byte payload'),
 'Bip32.serialize':('Serialize official BIP32 vector-2 root xpub','78-byte node payload / depth zero'),
 'Bip32.deriveChild':('Derive nonhardened child zero from official BIP32 vector-2 root','78-byte parent payload / 1 child index / depth 1'),
 'Bip32.derivePath':('Derive two nonhardened children from official BIP32 vector-2 root','78-byte parent payload / indices [0,1] / depth 2'),
 'Bip32.parsePath':('Parse strict nonhardened textual path','m/0/1 (5 UTF-8 bytes) / 2 indices'),
 'Bip32.deriveTextPath':('Parse textual path and derive two nonhardened children','78-byte parent payload + m/0/1 (5 bytes) / depth 2'),
 'Script.pushData':('Build minimally encoded PUSHDATA1','80-byte data / 82-byte script'),
 'Script.p2pkh':('Build P2PKH locking script','20-byte public-key hash / 25-byte script'),
 'Script.p2sh':('Build P2SH locking script','20-byte script hash / 23-byte script'),
 'Script.witnessProgram':('Build future witness-v2 locking script','32-byte program / 34-byte script'),
 'Script.p2wpkh':('Build witness-v0 P2WPKH locking script','20-byte key hash / 22-byte script'),
 'Script.p2wsh':('Build witness-v0 P2WSH locking script','32-byte script hash / 34-byte script'),
 'Script.p2tr':('Build witness-v1 Taproot locking script','32-byte output key / 34-byte script'),
 'Script.tapLeafHash':('Compute BIP341 current-version TapLeaf commitment','34-byte tapscript / leaf version 0xc0'),
 'Script.tapBranchHash':('Sort child commitments and compute BIP341 TapBranch hash','2 x 32-byte child hashes'),
 'Transaction.serialize':('Serialize complete legacy transaction',f'10 inputs / 2 outputs / {len(wire)} wire bytes'),
 'Transaction.parse':('Parse complete legacy transaction',f'{len(wire)} wire bytes / 10 inputs / 2 outputs'),
 'Transaction.txid':('Serialize without witness and compute display-order transaction ID',f'10 inputs / 2 outputs / {len(wire)} wire bytes'),
 'Transaction.wtxid':('Serialize with witness option and compute display-order transaction ID',f'10 inputs / 2 outputs / empty witness stacks / {len(wire)} wire bytes'),
 'Transaction.signatureHashLegacy':('Compute one complete legacy SIGHASH_ALL digest','10 inputs / 2 outputs / input index 0 / 25-byte scriptCode'),
 'Transaction.signatureHashSegwitV0':('Compute one complete BIP143 SIGHASH_ALL digest','10 inputs / 2 outputs / input index 0 / 25-byte scriptCode'),
 'Transaction.signatureHashTaproot':('Compute one complete BIP341 key-path DEFAULT digest','10 inputs / 2 outputs / input index 0 / equal 34-byte spent scripts'),
 'Transaction.prepareSegwitV0':('Validate transaction and construct lazy BIP143 hasher','10 inputs / 2 outputs; check digest outside timing'),
 'Transaction.SegwitV0Hasher.signatureHash':('Compute first cold BIP143 digest from prepared hasher','10 inputs / 2 outputs / input index 0 / ALL / 25-byte scriptCode'),
 'Transaction.prepareTaproot':('Validate transaction and prevouts, construct lazy BIP341 hasher','10 inputs / 2 outputs / 10 spent outputs; check digest outside timing'),
 'Transaction.TaprootHasher.signatureHash':('Compute first cold BIP341 digest from prepared hasher','10 inputs / 2 outputs / input index 0 / DEFAULT / 34-byte spent scripts'),
}
unavailable={
 'Bitcoin/Address.taprootSecretKey':'bitcoin 0.2.1 exposes public Taproot tweaks but no secret-key tweak API; no complete equivalent composed public API.',
 'Bitcoin/Address.signTaprootKeyPath':'bitcoin 0.2.1 and ecdsa 8.0.1 expose no BIP340 Schnorr signing implementation.',
 'Bitcoin/Transaction.signatureHashSegwitV0':'bitcoin 0.2.1 has legacy and Taproot sighashes but no BIP143/Segwit-v0 implementation.',
 'Bitcoin/Transaction.prepareSegwitV0':'bitcoin 0.2.1 has neither BIP143 nor a reusable BIP143 hasher constructor.',
 'Bitcoin/Transaction.SegwitV0Hasher.signatureHash':'bitcoin 0.2.1 has neither BIP143 nor a reusable BIP143 hasher method.',
 'Bitcoin/Transaction.prepareTaproot':'bitcoin 0.2.1 has one-shot Taproot hashing but no reusable hasher constructor; one-shot costs are measured separately.',
 'Bitcoin/Transaction.TaprootHasher.signatureHash':'bitcoin 0.2.1 has one-shot Taproot hashing but no retained common-hash API; one-shot costs are measured separately.',
}
for row in ROWS:
    group,fun=row['api'].split('/',1)[1].split('.',1)
    candidate=next(c for c in CASES if c['name']==row['case'] and c['implementation']=='native')
    pure=next((c for c in CASES if c['public_api']==row['api'] and c['implementation']=='mops-bitcoin'),None)
    assert pure or row['api'] in unavailable,row['api']
    workload,size=descriptions[group+'.'+fun]
    api_rows.append(dict(id=row['api'],module='Bitcoin/'+group,function=fun,workload=workload,size=size,plugin_case={'name':row['case'],'implementation':'native'},native_case={'name':pure['name'],'implementation':'mops-bitcoin'} if pure else None,notes=candidate['notes']+(' '+pure['notes'] if pure else ' '+unavailable[row['api']])))
(HERE/'inventory.json').write_text(json.dumps({'callable_count':len(ROWS),'native_cases':len(ROWS),'baseline_cases':len(CASES)-len(ROWS),'api_rows':api_rows},indent=2)+'\n')
print(f'Generated {len(CASES)} cases for {len(ROWS)} callable Bitcoin API surfaces')
