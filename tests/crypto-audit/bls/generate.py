#!/usr/bin/env python3
"""Independent audit fixtures from published suites and Ethereum py_ecc 8.0.0.
Run in an environment containing py_ecc==8.0.0. Does not import plugin code.
"""
from pathlib import Path
import hashlib, json, urllib.request
from py_ecc import __version__
from py_ecc.bls import G2ProofOfPossession as Eth
from py_ecc.bls.g2_primitives import pubkey_to_G1, signature_to_G2, subgroup_check
from py_ecc.bls.hash_to_curve import hash_to_G1, hash_to_G2, map_to_curve_G1, map_to_curve_G2, clear_cofactor_G1, clear_cofactor_G2
from py_ecc.bls.point_compression import compress_G1, compress_G2
from py_ecc.optimized_bls12_381 import G1,G2,Z1,Z2,add,multiply,neg,curve_order,field_modulus,FQ,FQ2

HERE=Path(__file__).resolve().parent
rows=[]
sources=[]
def enc(p,g):
    v=compress_G1(p) if g==1 else compress_G2(p)
    return v.to_bytes(48,'big') if g==1 else b''.join(x.to_bytes(48,'big') for x in v)
def b(n,w=32): return n.to_bytes(w,'big')
def row(name,op,a=b'',c=b'',d=b'',out=b'',error=0):
    rows.append(dict(name=name,op=op,a=a.hex(),b=c.hex(),c=d.hex(),expected=out.hex(),status=error))
def fetch(url,name):
    path=HERE/name
    data=path.read_bytes() if path.exists() else urllib.request.urlopen(url).read()
    path.write_bytes(data)
    sources.append(dict(url=url,file=name,sha256=hashlib.sha256(data).hexdigest()))
    return json.loads(data)
# These raw RFC corpora were fetched independently; retained bytes make regeneration reproducible.
for g in [1,2]:
    suite=f'BLS12381G{g}_XMD:SHA-256_SSWU_RO_'
    corpus=fetch('https://raw.githubusercontent.com/cfrg/draft-irtf-cfrg-hash-to-curve/main/poc/vectors/'+suite+'.json',f'rfc9380-g{g}.json')
    def coord(x):return int(x,16)
    def compressed(p):
        if g==1:
            x,y=coord(p['x']),coord(p['y'])
            return b((1<<383) | ((y*2>field_modulus)<<381) | x,48)
        xr,xi=map(coord,p['x'].split(',')); yr,yi=map(coord,p['y'].split(','))
        sign=(yi*2>field_modulus) if yi else yr*2>field_modulus
        return b((1<<383)|(sign<<381)|xi,48)+b(xr,48)
    for i,v in enumerate(corpus['vectors']):
        row(f'rfc-g{g}-{i}',10+g,v['msg'].encode(),corpus['dst'].encode(),out=compressed(v['P']))
        row(f'non-subgroup-g{g}-{i}',g,compressed(v['Q0']),error=2)

# Official Ethereum deserialization/verification vectors, independently converted.
eth_cases=json.loads((HERE/'ethereum-v0.1.2.json').read_text())
for group in [1,2]:
    for filename,v in eth_cases.items():
        if not filename.startswith(f'deserialization_G{group}/'): continue
        file=Path(filename); a=bytes.fromhex(v['input']['pubkey'].removeprefix('0x')) if group==1 else bytes.fromhex(v['input']['signature'].removeprefix('0x'))
        row(file.stem,group,a,out=a if v['output'] else b'',error=0 if v['output'] else (1 if len(a)!=48*group else 2))
for filename,v in eth_cases.items():
    if not filename.startswith('verify/'): continue
    file=Path(filename); q=v['input']; a=bytes.fromhex(q['pubkey'][2:]); m=bytes.fromhex(q['message'][2:]); s=bytes.fromhex(q['signature'][2:])
    # Independent py_ecc decoders classify the public Result API's errors.
    error=0
    for data,width,decode in [(a,48,pubkey_to_G1),(s,96,signature_to_G2)]:
        if len(data)!=width: error=1; break
        try:
            if not subgroup_check(decode(data)): error=2; break
        except (ValueError,AssertionError): error=2; break
    if error==0 and (a==enc(Z1,1) or s==enc(Z2,2)): error=7
    row(file.stem,15,a,m,s,out=b'' if error else bytes([v['output']]),error=error)
sources.append(dict(url='https://github.com/ethereum/bls12-381-tests/releases/tag/v0.1.2',file='ethereum-v0.1.2.json',sha256=hashlib.sha256((HERE/'ethereum-v0.1.2.json').read_bytes()).hexdigest(),file_count=len(eth_cases)))

icpk=bytes.fromhex('814c0e6ec71fab583b08bd81373c255c3c371b2e84863c98a4f1e08b74235d14fb5d9c0cd546d9685f913a0c0b2cc5341583bf4b4392e467db96d65b9bb4cb717112f8472e0d5a4d14505ffd7484b01291091c5f87b98883463f98091a0baaae')
icmsg=bytes.fromhex('0d69632d73746174652d726f6f74e6c01e909b4923345ce5970962bcfe3004bfd8474a21dae28f50692502f46d90')
icsig=bytes.fromhex('ace9fcdd9bc977e05d6328f889dc4e7c99114c737a494653cb27a1f55c06f4555e0f160980af5ead098acc195010b2f7')
row('official-ic-certificate',14,icpk,icmsg,icsig,out=b'\1')
row('official-ic-wrong-frame',14,icpk,icmsg[1:],icsig,out=b'\0')
sources.append(dict(url='https://docs.rs/crate/ic-verify-bls-signature/0.6.0/source/tests/tests.rs',case='verify_valid certificate / ic-verify-bls-signature 0.6.0'))
for g,gen,identity in [(1,G1,Z1),(2,G2,Z2)]:
    for n in [0,1,2,42,2**128+15,curve_order-1]:
        row(f'scalar-g{g}-{n}',4+g,enc(gen,g),b(n),out=enc(multiply(gen,n),g))
    row(f'add-g{g}',2+g,enc(gen,g),enc(multiply(gen,2),g),out=enc(multiply(gen,3),g))
    row(f'add-cancellation-g{g}',2+g,enc(gen,g),enc(neg(gen),g),out=enc(identity,g))
    row(f'scalar-order-g{g}',4+g,enc(gen,g),b(curve_order),error=3)
    row(f'scalar-short-g{g}',4+g,enc(gen,g),b'\1',error=1)
    row(f'msm-g{g}',6+g,enc(gen,g)+enc(multiply(gen,2),g),b(5)+b(7),out=enc(multiply(gen,19),g))
    row(f'msm-mismatch-g{g}',6+g,enc(gen,g),b'',error=1)
    row(f'msm-precedence-g{g}',6+g,enc(gen,g)+b'\0'*(48*g),b(curve_order)+b(0),error=3)
    row(f'empty-msm-g{g}',6+g,out=enc(identity,g))
    row(f'limit-msm-g{g}',6+g,enc(identity,g)*128,b(0)*128,out=enc(identity,g))
    row(f'oversize-msm-g{g}',6+g,enc(identity,g)*129,b(0)*129,error=5)
    row(f'empty-aggregate-g{g}',16+g,out=enc(identity,g))
    row(f'aggregate-g{g}',16+g,enc(gen,g)+enc(multiply(gen,2),g),out=enc(multiply(gen,3),g))
    row(f'noncanonical-infinity-g{g}',g,bytes([0xe0])+b'\0'*(48*g-1),error=2)
    row(f'infinity-with-data-g{g}',g,bytes([0xc0])+b'\0'*(48*g-2)+b'\1',error=2)
    row(f'no-compression-g{g}',g,bytes([enc(gen,g)[0]&0x7f])+enc(gen,g)[1:],error=2)
    row(f'empty-dst-g{g}',10+g,b'message',error=10)
    dst=b'X'*256
    h=(hash_to_G1 if g==1 else hash_to_G2)(b'long-dst',hashlib.sha256(b'H2C-OVERSIZE-DST-'+dst).digest(),hashlib.sha256)
    row(f'oversize-dst-g{g}',10+g,b'long-dst',dst,out=enc(h,g))
for n in [0,1,2,field_modulus-1]:
    row(f'map-g1-{n}',9,b(n,48),out=enc(clear_cofactor_G1(map_to_curve_G1(FQ(n))),1))
for x,y in [(0,0),(0,1),(1,0),(1,1),(field_modulus-1,0),(0,field_modulus-1)]:
    row(f'map-g2-{x}-{y}',10,b(x,48)+b(y,48),out=enc(clear_cofactor_G2(map_to_curve_G2(FQ2([x,y]))),2))
row('empty-pairing',13,out=b'\1')
row('single-pairing',13,enc(G1,1)+enc(G2,2),out=b'\0')
row('cancel-pairing',13,enc(G1,1)+enc(G2,2)+enc(neg(G1),1)+enc(G2,2),out=b'\1')
row('wrong-sign-pairing',13,enc(G1,1)+enc(G2,2)+enc(G1,1)+enc(G2,2),out=b'\0')
row('limit-pairing',13,(enc(Z1,1)+enc(Z2,2))*128,out=b'\1')
row('oversize-pairing',13,(enc(Z1,1)+enc(Z2,2))*129,error=5)
row('noncanonical-field',9,b(field_modulus,48),error=4)
row('noncanonical-field-real',10,b(field_modulus,48)+b(0,48),error=4)
row('noncanonical-field-imaginary',10,b(0,48)+b(field_modulus,48),error=4)
row('infinity-key-malformed-sig-ic',14,enc(Z2,2),b'x',b'',error=1)
row('infinity-key-malformed-sig-eth',15,enc(Z1,1),b'x',b'',error=1)
row('identity-ic',14,enc(Z2,2),b'x',enc(G1,1),error=7)
row('identity-eth',15,enc(Z1,1),b'x',enc(G2,2),error=7)
profiles=[]
for n,msg in [(42,b'audit-A'),(99,b'audit-B')]:
    pk=Eth.SkToPk(n); sig=Eth.Sign(n,msg); proof=Eth.PopProve(n)
    profiles.append(dict(sk=n,pk=pk.hex(),msg=msg.hex(),sig=sig.hex(),pop=proof.hex()))
    row(f'py-ecc-eth-signature-{n}',15,pk,msg,sig,out=b'\1')
    row(f'py-ecc-eth-pop-{n}',16,pk,proof,out=b'\1')
    row(f'wrong-pop-domain-{n}',16,pk,Eth.Sign(n,pk),out=b'\0')
    row(f'wrong-sig-domain-{n}',15,pk,pk,proof,out=b'\0')
    row(f'wrong-key-pop-{n}',16,Eth.SkToPk(n+1),proof,out=b'\0')
    dst=b'BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_'
    row(f'py-ecc-ic-signature-{n}',14,enc(multiply(G2,n),2),msg,enc(multiply(hash_to_G1(msg,dst,hashlib.sha256),n),1),out=b'\1')

(HERE/'vectors.json').write_text(json.dumps(rows,indent=2)+'\n')
(HERE/'vectors.tsv').write_text('\n'.join('\t'.join(str(v[k]) for k in ['name','op','a','b','c','status','expected']) for v in rows)+'\n')
(HERE/'provenance.json').write_text(json.dumps(dict(py_ecc=__version__,sources=sources,cases=len(rows)),indent=2)+'\n')
# The complete primitive corpus also runs through actual interpreter and compiled Wasm.
errors=['','invalidLength','invalidPoint','invalidScalar','invalidField','tooManyItems','emptyBatch','identity','invalidProof','duplicateMessage','invalidArgument']
ops={1:('validateG1',1),2:('validateG2',1),3:('g1Add',2),4:('g2Add',2),5:('g1Mul',2),6:('g2Mul',2),7:('g1Msm',2),8:('g2Msm',2),9:('mapToG1',1),10:('mapToG2',1),11:('hashToG1',2),12:('hashToG2',2),13:('pairingCheck',1),14:('verifyIC',3),15:('verifyEthereum',3),16:('verifyEthereumProof',2),17:('g1Aggregate',1),18:('g2Aggregate',1)}
def mo(h):return '"'+''.join('\\'+h[i:i+2] for i in range(0,len(h),2))+'"'
lines=['import B "mo:fast/BLS12381";','import P "mo:⛔";']
selected=rows
for v in selected:
    name,arity=ops[v['op']]
    args=', '.join(mo(v[k]) for k in ['a','b','c'][:arity])
    expected='#err(#'+errors[v['status']]+')' if v['status'] else '#ok('+('true' if v['expected']=='01' else 'false')+')' if v['op'] in [13,14,15,16] else '#ok('+mo(v['expected'])+')'
    lines += ['// '+v['name'],f'assert B.{name}({args}) == {expected};']
lines+=['P.debugPrint("independent BLS primitive audit passed");']
(HERE/'primitives.mo').write_text('\n'.join(lines)+'\n')
# Profile compositions are tested with independent complete signatures and proofs.
a,c=profiles
scalar=lambda n:b(n).hex()
sigs=[bytes.fromhex(v['sig']) for v in profiles]
agg=Eth.Aggregate(sigs).hex()
fast=Eth.Aggregate([Eth.Sign(v['sk'],b'audit-A') for v in profiles]).hex()
lines=['import B "mo:fast/BLS12381";','import P "mo:⛔";']
for i,v in enumerate(profiles):
    for key in ['pk','msg','sig','pop']:
        if key=='sig' and i==1: continue
        lines.append(f'let {key}{i} : Blob = {mo(v[key])};')
lines += [f'let aggregate : Blob = {mo(agg)};',f'let fast : Blob = {mo(fast)};',
'assert B.aggregateVerifyEthereum([pk0,pk1],[pop0,pop1],[msg0,msg1],aggregate) == #ok(true);',
'assert B.aggregateVerifyEthereum([pk0,pk1],[pop0,pop1],[msg1,msg0],aggregate) == #ok(false);',
'assert B.aggregateVerifyEthereum([pk0,pk1],[pop1,pop0],[msg0,msg1],aggregate) == #err(#invalidProof);',
'assert B.aggregateVerifyEthereum([pk0,pk1],[pop0,pop1],[msg0,msg0],fast) == #ok(true);',
'assert B.fastAggregateVerifyEthereum([pk0,pk1],[pop0,pop1],msg0,fast) == #ok(true);',
'assert B.fastAggregateVerifyEthereum([pk0,pk1],[pop0,pop1],msg1,fast) == #ok(false);',
'assert B.aggregateVerifyEthereum([pk0],[],[msg0],sig0) == #err(#invalidLength);',
'assert B.aggregateVerifyEthereum([pk0],[pop0],[],sig0) == #err(#invalidLength);',
'assert B.aggregateVerifyEthereum([],[],[],B.g2Identity) == #err(#emptyBatch);',
'assert B.fastAggregateVerifyEthereum([],[],msg0,B.g2Identity) == #err(#emptyBatch);',
'assert B.aggregateVerifyIC([],[],B.g1Identity) == #err(#emptyBatch);',
'assert B.aggregateVerifyIC([B.g2Generator,B.g2Generator],[msg0,msg0],B.g1Generator) == #err(#duplicateMessage);',
'assert B.aggregateVerifyIC([B.g2Generator],[],B.g1Generator) == #err(#invalidLength);',
'assert B.fastAggregateVerifyEthereum([B.g1Identity],[pop0],msg0,sig0) == #err(#identity);',
]
# Rogue key: public sum equals attacker's known key, but attacker cannot prove rogue key possession.
rogue=enc(add(multiply(G1,99),neg(multiply(G1,42))),1)
lines += [f'let rogue : Blob = {mo(rogue.hex())};',f'let forged : Blob = {mo(Eth.Sign(99,b"audit-A").hex())};',
'assert B.fastAggregateVerifyEthereum([pk0,rogue],[pop0,pop1],msg0,forged) == #err(#invalidProof);']
# IC distinct-message aggregation (and deliberate message/public-key misalignment).
icpks=[enc(multiply(G2,v['sk']),2) for v in profiles]
icdst=b'BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_'
icps=[multiply(hash_to_G1(bytes.fromhex(v['msg']),icdst,hashlib.sha256),v['sk']) for v in profiles]
lines += [f'let ic0 : Blob = {mo(icpks[0].hex())};',f'let ic1 : Blob = {mo(icpks[1].hex())};',f'let icAggregate : Blob = {mo(enc(add(*icps),1).hex())};',
'assert B.aggregateVerifyIC([ic0,ic1],[msg0,msg1],icAggregate) == #ok(true);',
'assert B.aggregateVerifyIC([ic0,ic1],[msg1,msg0],icAggregate) == #ok(false);',
'assert B.aggregateVerifyIC([ic0,ic1],[msg0,msg0],icAggregate) == #err(#duplicateMessage);',
'let tooMany = P.Array_init<Blob>(129, pk0);',
'let tooManyFrozen = P.Array_tabulate<Blob>(129, func(i) { tooMany[i] });',
'assert B.fastAggregateVerifyEthereum(tooManyFrozen,tooManyFrozen,msg0,sig0) == #err(#tooManyItems);',
'assert B.aggregateVerifyEthereum(tooManyFrozen,tooManyFrozen,tooManyFrozen,sig0) == #err(#tooManyItems);',
'assert B.aggregateVerifyIC(tooManyFrozen,tooManyFrozen,B.g1Generator) == #err(#tooManyItems);',
'var evaluated = 0;',
'func once(p : Blob) : Blob { evaluated += 1; p };',
'assert B.g1Add(once(B.g1Generator),once(B.g1Identity)) == #ok(B.g1Generator);',
'assert evaluated == 2;',
'let validationAlias = B.validateG1;',
'assert validationAlias(B.g1Generator) == #ok(B.g1Generator);',
'P.debugPrint("independent BLS profile audit passed");']
(HERE/'profiles.mo').write_text('\n'.join(lines)+'\n')
print(len(rows),'native cases;',len(selected),'Motoko primitive cases; profile compositions generated')
