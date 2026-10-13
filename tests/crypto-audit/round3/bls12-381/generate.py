#!/usr/bin/env python3
"""Independent aggregate rejection matrix from retained published/py_ecc fixtures."""
import hashlib, json, re, subprocess
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASELINE = '7a0211b97d2da0910d6982ad5b7111df376f4f9f'
fixture = ROOT/'plugins/bls12-381/runtime/vectors/aggregate.rs'
s = fixture.read_text()
get_array = lambda name: re.findall(r'"([0-9a-f]+)"', re.search(r'pub const '+name+r':.*?= \[(.*?)\];',s).group(1))
get_one = lambda name: re.search(r'pub const '+name+r': &str = "([0-9a-f]+)"',s).group(1)
ek = get_array('ETH_KEYS'); ep=get_array('ETH_PROOFS'); es=get_array('ETH_SIGNATURES')
ik=get_array('IC_KEYS'); isig=get_array('IC_SIGNATURES'); msgs=get_array('MESSAGES')
rfc = ROOT/'plugins/bls12-381/runtime/vectors/rfc9380.rs'
rs=rfc.read_text(); q1=re.search('q0: "([a-f0-9]+)"',rs).group(1); q2=re.search('q0: "([a-f0-9]+)"',rs.split('pub const G2_VECTORS')[1]).group(1)
p=int('1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab',16)
identity=lambda n:'c0'+'00'*(n-1)
def malformed(n,q):
    return [ ('empty','',1),('short','00'*(n-1),1),('long','00'*(n+1),1),
             ('flags-zero','00'*n,2),('infinity-sign','e0'+'00'*(n-1),2),
             ('infinity-nonzero','c0'+'00'*(n-2)+'01',2),
             ('field-modulus', ((p|(1<<383)).to_bytes(48,'big')+bytes(n-48)).hex(),2),
             ('outside-subgroup',q,2)]
bad1=malformed(48,q1);bad2=malformed(96,q2)
cases=[]
def case(name,op,keys,proofs,messages,sig,status=0,value=True):
    assert len(keys)==len(messages)
    if op!=19: assert len(keys)==len(proofs)
    cases.append(dict(name=name,op=op,keys=keys,proofs=proofs,messages=messages,signature=sig,status=status,value=value))
# Independent valid fixtures (no implementation-generated signature oracle).
case('ic-py-ecc-valid',19,ik,[],msgs,get_one('IC_AGGREGATE'))
case('eth-py-ecc-valid',20,ek,ep,msgs,get_one('ETH_AGGREGATE'))
case('fast-py-ecc-valid',21,ek,ep,[msgs[0]]*2,get_one('ETH_SAME_MESSAGE_AGGREGATE'))
case('ic-message-mutated',19,ik,[],[msgs[0],'00'],get_one('IC_AGGREGATE'),value=False)
case('eth-message-mutated',20,ek,ep,[msgs[0],'00'],get_one('ETH_AGGREGATE'),value=False)
case('fast-message-mutated',21,ek,ep,['00']*2,get_one('ETH_SAME_MESSAGE_AGGREGATE'),value=False)
# Untrusted points must still pass canonical + subgroup decoding in every position.
for name,bad,err in bad1:
    case('ic-sig-'+name,19,[ik[0]],[],[msgs[0]],bad,err)
    case('eth-key-'+name,20,[bad],[ep[0]],[msgs[0]],es[0],err)
    case('fast-key-'+name,21,[bad],[ep[0]],[msgs[0]],es[0],err)
for name,bad,err in bad2:
    case('ic-key-'+name,19,[bad],[],[msgs[0]],isig[0],err)
    case('eth-sig-'+name,20,[ek[0]],[ep[0]],[msgs[0]],bad,err)
    case('eth-proof-'+name,20,[ek[0]],[bad],[msgs[0]],es[0],err)
    case('fast-proof-'+name,21,[ek[0]],[bad],[msgs[0]],es[0],err)
# Combined invalid operands assert public error order instead of merely rejection.
for sn,sig,se in bad1:
    for kn,key,ke in bad2:
        case('ic-order-'+sn+'-'+kn,19,[key],[],[msgs[0]],sig,se)
for kn,key,ke in bad1:
    for pn,proof,pe in bad2:
        case('fast-order-'+kn+'-'+pn,21,[key],[proof],[msgs[0]],'00'*96,ke)
for sn,sig,se in bad2:
    case('eth-sig-order-'+sn,20,[''],[''],[msgs[0]],sig,se)
    case('eth-identity-before-key-'+sn,20,[q1],[sig],[msgs[0]],identity(96),7)
    case('fast-proof-before-key-identity-'+sn,21,[identity(48)],[sig],[msgs[0]],'',se)
# Exact per-call successful proof caching, never key-only or global cache.
for op in [20,21]:
    case(f'cached-key-different-proof-{op}',op,[ek[0],ek[0]],[ep[0],ep[1]],[msgs[0]]*2,es[0],8)
    case(f'cached-key-invalid-subgroup-proof-{op}',op,[ek[0],ek[0]],[ep[0],q2],[msgs[0]]*2,es[0],2)
    case(f'first-invalid-proof-{op}',op,[ek[0],ek[0]],[ep[1],ep[0]],[msgs[0]]*2,es[0],8)
    case(f'proof-other-key-{op}',op,[ek[0],ek[1]],[ep[0],ep[0]],[msgs[0]]*2,es[0],8)
    case(f'key-identity-{op}',op,[identity(48)],[ep[0]],[msgs[0]],es[0],7)
    case(f'proof-identity-{op}',op,[ek[0]],[identity(96)],[msgs[0]],es[0],7)
    case(f'next-call-unproved-{op}',op,[ek[0]],[ep[1]],[msgs[0]],es[0],8)
    case(f'next-call-valid-{op}',op,[ek[0]],[ep[0]],[msgs[0]],es[0])
# IC duplicate rejection precedes all cryptography, exact bytes including NUL.
for count in [2,15,16,17,127]:
    for where in sorted({0,count//2,count-2} - {count-1}):
        mm=[(bytes(64)+i.to_bytes(2,'big')).hex() for i in range(count)]
        mm[-1]=mm[where]
        case(f'ic-duplicate-{count}-{where}',19,['']*count,[],mm,'',9)
case('ic-binary-distinct',19,['']*3,[],['00','0000','0001'],'',1)
case('ic-sig-identity-before-key',19,[''],[],[msgs[0]],identity(48),7)
case('ic-key-identity',19,[identity(96)],[],[msgs[0]],isig[0],7)
pool = list(dict.fromkeys(h for c in cases for h in c['keys']+c['proofs']+c['messages']+[c['signature']]))
indices = {h:i for i,h in enumerate(pool)}
index_list = lambda hs: ';'.join(str(indices[h]) for h in hs)
(HERE/'blobs.tsv').write_text('\n'.join(pool)+'\n')
(HERE/'cases.json').write_text(json.dumps([dict(c, keys=[indices[h] for h in c['keys']], proofs=[indices[h] for h in c['proofs']], messages=[indices[h] for h in c['messages']], signature=indices[c['signature']]) for c in cases],indent=2)+'\n')
(HERE/'cases.tsv').write_text('\n'.join('\t'.join([c['name'],str(c['op']),index_list(c['keys']),index_list(c['proofs']),index_list(c['messages']),str(indices[c['signature']]),str(c['status']),str(int(c['value']))]) for c in cases)+'\n')
old = subprocess.check_output(['git','show',BASELINE+':packages/fast/src/BLS12381.mo'],cwd=ROOT,text=True)
(HERE/'FrozenWrapper.mo').write_text('// Test-only pre-fusion public wrapper from '+BASELINE+'; never used in production.\n'+old)
blob=lambda h:'"'+''.join('\\'+h[i:i+2] for i in range(0,len(h),2))+'"'
literal=blob
blob=lambda h:'b'+str(indices[h])
array=lambda hs:'['+','.join(blob(h) for h in hs)+']'
errors={1:'invalidLength',2:'invalidPoint',5:'tooManyItems',6:'emptyBatch',7:'identity',8:'invalidProof',9:'duplicateMessage'}
# Fixed-name wrappers make assertion source compact despite long-prefix cases.
lines=['import B "mo:fast/BLS12381";','import Old "FrozenWrapper";','import Prim "mo:⛔";','var checked = 0;'] + ['let b'+str(i)+' : Blob = '+literal(h)+';' for i,h in enumerate(pool)]
for c in cases:
    args=[array(c['keys'])]
    if c['op']!=19: args.append(array(c['proofs']))
    args += [blob(c['messages'][0]) if c['op']==21 else array(c['messages']),blob(c['signature'])]
    name={19:'aggregateVerifyIC',20:'aggregateVerifyEthereum',21:'fastAggregateVerifyEthereum'}[c['op']]
    expect='#err(#'+errors[c['status']]+')' if c['status'] else '#ok('+str(c['value']).lower()+')'
    # Constant rows share the literal; Motoko equality is structural by design.
    lines += ['// '+c['name'], 'do { let actual = B.'+name+'('+','.join(args)+'); assert actual == '+expect+'; assert actual == Old.'+name+'('+','.join(args)+'); checked += 1 };']
# Shape validation order and argument effects cross the generated bridge.
lines += ['''
func repeat(n : Nat, value : Blob) : [Blob] { Prim.Array_tabulate<Blob>(n,func(_) {value}) };
for (n in [0,1,127,128,129].values()) {
  let keys=repeat(n, "");
  assert B.aggregateVerifyIC(keys, repeat(n+1, ""), "") == #err(#invalidLength);
  assert B.aggregateVerifyEthereum(keys, repeat(n+1, ""), repeat(n, ""), "") == #err(#invalidLength);
  assert B.fastAggregateVerifyEthereum(keys, repeat(n+1, ""), "", "") == #err(#invalidLength);
  checked += 3;
};
assert B.aggregateVerifyIC([], [], "") == #err(#emptyBatch); checked += 1;
assert B.aggregateVerifyEthereum([], [], [], "") == #err(#emptyBatch); checked += 1;
assert B.fastAggregateVerifyEthereum([], [], "", "") == #err(#emptyBatch); checked += 1;
assert B.aggregateVerifyIC(repeat(128,""),repeat(128,""),"") == #err(#tooManyItems); checked += 1;
assert B.aggregateVerifyEthereum(repeat(128,""),repeat(128,""),repeat(128,""),"") == #err(#tooManyItems); checked += 1;
assert B.fastAggregateVerifyEthereum(repeat(129,""),repeat(129,""),"","") == #err(#tooManyItems); checked += 1;
var phase=0;
func argArray(want : Nat) : [Blob] { assert phase==want; phase += 1; [""] };
func argBlob(want : Nat) : Blob { assert phase==want; phase += 1; "" };
assert B.aggregateVerifyIC(argArray(0),argArray(1),argBlob(2)) == #err(#invalidLength); assert phase==3; checked += 1;
phase:=0;
assert B.aggregateVerifyEthereum(argArray(0),argArray(1),argArray(2),argBlob(3)) == #err(#invalidLength); assert phase==4; checked += 1;
phase:=0;
assert B.fastAggregateVerifyEthereum(argArray(0),argArray(1),argBlob(2),argBlob(3)) == #err(#invalidLength); assert phase==4; checked += 1;
Prim.debugPrint("independent aggregate public cases: " # debug_show checked);
''']
(HERE/'public.mo').write_text('\n'.join(lines)+'\n')
(HERE/'provenance.json').write_text(json.dumps(dict(baseline=BASELINE,case_count=len(cases),public_case_count=len(cases)+24,inputs={str(x.relative_to(ROOT)):hashlib.sha256(x.read_bytes()).hexdigest() for x in [fixture,rfc]},sources=['Retained py_ecc 8.0.0 profiles.json fixtures','Published RFC 9380 Q0 points before cofactor clearing','Explicit canonical-encoding and error-order expectations','Frozen pre-fusion public wrapper used only as a second oracle']),indent=2)+'\n')
print('generated',len(cases),'ABI cases,',len(cases)+24,'public cases')
