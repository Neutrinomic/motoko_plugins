#!/usr/bin/env python3
"""Fill closest published-code Bitcoin peers without editing frozen API actors."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
BENCH=HERE.parents[2]
sys.path.insert(0,str(BENCH))
from common import actor,blob,save_case

spec=importlib.util.spec_from_file_location('curve_oracle',BENCH/'generate-curves.py')
ec=importlib.util.module_from_spec(spec)
spec.loader.exec_module(ec)
curve=ec.CURVES['secp256k1']
add=lambda p,q:ec.ec_add(p,q,curve['p'])
mul=lambda n:ec.multiply(curve['g'],n,add)
sha=lambda b:hashlib.sha256(b).digest()
secret=ec.SECRET
point=mul(secret)
tag=sha(b'TapTweak')
tweak=int.from_bytes(sha(tag+tag+point[0].to_bytes(32,'big')),'big')
assert tweak<curve['n']
normalized=secret if point[1]%2==0 else curve['n']-secret
result=(normalized+tweak)%curve['n']
assert result
expected=result.to_bytes(32,'big')
assert mul(result)==add((point[0],point[1] if point[1]%2==0 else curve['p']-point[1]),mul(tweak))
native=json.loads((HERE.parent/'cases.json').read_text())['cases']
by_api={c['public_api']:c for c in native if c['implementation']=='native'}
assert expected.hex()==by_api['Bitcoin/Address.taprootSecretKey']['expected_hex']

imports='''import A "mo:core/Array";
import V "mo:core/VarArray";
import J "mo:bitcoin/ec/Jacobi";
import C "mo:bitcoin/ec/Curves";
import U "mo:bitcoin/Common";
import H "mo:bitcoin/Hash";'''
declarations=f'''transient let secret:Blob={blob(secret.to_bytes(32,'big'))};
func scalar(bytes:Blob, allowZero:Bool):Nat {{
  assert bytes.size()==32;
  let n=U.readBE256(Prim.blobToArray(bytes),0);
  assert n < C.secp256k1.r and (allowZero or n!=0);
  n
}};
func tweakXOnlySecretKey(secret:Blob,tweak:Blob):Blob {{
  let d=scalar(secret,false);
  let t=scalar(tweak,true);
  // This is the already-audited public Jacobi/Common composition from the
  // curve benchmark peer, with variable-time Nat/NAF reference arithmetic.
  let normalized:Nat=switch(J.toAffine(J.mulBase(d,C.secp256k1))) {{
    case(#infinity(_)) Prim.trap("invalid secret");
    case(#point(_,y,_)) {{if(y.value%2==0)d else C.secp256k1.r-d}};
  }};
  let sum=(normalized+t)%C.secp256k1.r;
  assert sum!=0;
  let bytes=V.repeat<Nat8>(0,32);
  U.writeBE256(bytes,0,sum);
  Prim.arrayToBlob(bytes.toArray())
}};
func taprootSecretKey(secret:Blob,merkleRoot:?Blob):Blob {{
  let d=scalar(secret,false);
  let encodedPublic=J.toBytes(J.mulBase(d,C.secp256k1),true);
  let internal=A.tabulate<Nat8>(32,func(i){{encodedPublic[i+1]}});
  let message=switch(merkleRoot){{
    case(null)internal;
    case(?root){{assert root.size()==32;A.concat(internal,Prim.blobToArray(root))}};
  }};
  let tweak=Prim.arrayToBlob(H.taggedHash(message,"TapTweak"));
  tweakXOnlySecretKey(secret,tweak)
}};'''
notes=('Published bitcoin 0.2.1 Jacobi/Common scalar and curve primitives plus Hash.taggedHash compose the complete empty-tree BIP341 secret-key tweak. '
       'Both public-key derivation and the existing even-Y secret-tweak composition execute inside timing; scalar lengths/ranges, root length and nonzero result are checked. '
       'Pure Motoko Nat/NAF secret arithmetic is variable-time reference code; it does not share the native constant-time security contract. Output scalar bytes match the independent affine oracle exactly.')
name='closest-bitcoin-address-taproot-secret-key-composed'
case=dict(name=name,family='bitcoin',implementation='mops-bitcoin',plugins=[],comparison=by_api['Bitcoin/Address.taprootSecretKey']['name'],
          public_api='Bitcoin/Address.taprootSecretKey',expected_hex=expected.hex(),notes=notes,benchmark_kind='closest-variable-time-secret-composition',
          operations_per_sample=1,fixture_provenance='round2/api-bitcoin/closest/generate.py: independent Python affine secp256k1 and hashlib BIP341 tagged hash; verifies tweaked scalar point equation and matches pre-existing frozen API expected bytes.')
case=save_case(case,actor(imports,declarations,'','result := taprootSecretKey(secret,null);'),'round2/api-bitcoin/closest/actors')
cases=[case]
overrides={'Bitcoin/Address.taprootSecretKey':dict(id='Bitcoin/Address.taprootSecretKey',native_case={'name':name,'implementation':'mops-bitcoin'},native_source=case['source'],
        plugin_case={'name':by_api['Bitcoin/Address.taprootSecretKey']['name'],'implementation':'native'},contract='closest-variable-time-secret-composition',equivalent_api_contract=False,
        visible_footnote='Bitcoin-secret-composed',notes=notes)}

# Reuse the already-measured published one-shot implementation verbatim. The
# function is a closest-operation comparator to the native cold prepared method;
# it is not relabelled as a package-prepared API or a cache-construction cost.
source=next(c for c in native if c['public_api']=='Bitcoin/Transaction.signatureHashTaproot' and c['implementation']=='mops-bitcoin')
target=by_api['Bitcoin/Transaction.TaprootHasher.signatureHash']
assert source['expected_hex']==target['expected_hex']
notes=('Closest published bitcoin 0.2.1 createTaprootKeySpendSignatureHash one-shot operation versus the plugin prepared hasher first cold signatureHash call. '
       'Both compute input 0 SIGHASH_DEFAULT on the identical ten-input/two-output transaction, with equal 34-byte spent scripts and no annex. '
       'Package transaction/script parsing and native prepareTaproot occur outside timing. Native lazy common hashes are cold and included; the pure package recomputes its common hashes per call and exposes no retained cache. '
       'Any ratio describes uncached package operation versus prepared-cold plugin operation, not equivalent reusable-hasher APIs.')
name='closest-bitcoin-taproot-prepared-cold-vs-uncached'
case={**source,'name':name,'comparison':target['name'],'public_api':target['public_api'],'notes':notes,'benchmark_kind':'closest-uncached-versus-prepared-cold'}
case=save_case(case,(BENCH/source['source']).read_text(),'round2/api-bitcoin/closest/actors')
cases.append(case)
overrides[target['public_api']]=dict(id=target['public_api'],native_case={'name':name,'implementation':'mops-bitcoin'},native_source=case['source'],
       plugin_case={'name':target['name'],'implementation':'native'},contract='closest-uncached-versus-prepared-cold',equivalent_api_contract=False,
       visible_footnote='Bitcoin-uncached',notes=notes)

unavailable={
 'Bitcoin/Address.signTaprootKeyPath':'No BIP340 Schnorr signing implementation in pinned bitcoin 0.2.1 or ecdsa 8.0.1; ECDSA signing computes a different signature scheme.',
 'Bitcoin/Transaction.signatureHashSegwitV0':'Pinned bitcoin 0.2.1 implements legacy and Taproot signature hashes but no BIP143 message construction. SHA256 alone is not a matching signature-hash operation.',
 'Bitcoin/Transaction.prepareSegwitV0':'No BIP143 implementation or reusable BIP143 common-hash constructor in the pinned package.',
 'Bitcoin/Transaction.SegwitV0Hasher.signatureHash':'No BIP143 implementation or reusable BIP143 hasher method in the pinned package.',
 'Bitcoin/Transaction.prepareTaproot':'The package exposes one-shot Taproot hashing but no retained common-hash-state constructor. A fabricated wrapper constructor or full one-shot hash would measure different work.',
}
(HERE/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
(HERE/'override.json').write_text(json.dumps(overrides,indent=2)+'\n')
(HERE/'unavailable.json').write_text(json.dumps(unavailable,indent=2)+'\n')
(HERE/'oracle.json').write_text(json.dumps({'secret_hex':secret.to_bytes(32,'big').hex(),'public_x_hex':point[0].to_bytes(32,'big').hex(),'public_y_odd':bool(point[1]&1),'tweak_hex':tweak.to_bytes(32,'big').hex(),'expected_secret_hex':expected.hex(),'oracle':'Python affine modular arithmetic and hashlib; verifies output-point scalar equation independently of every measured Motoko implementation.'},indent=2)+'\n')
print('Generated 2 closest Bitcoin peers; retained 5 explicit unavailable APIs')
