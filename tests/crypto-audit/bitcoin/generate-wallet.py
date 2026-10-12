#!/usr/bin/env python3
"""Extra wallet composition expectations from the Core v29.0 oracle cache.

Run generate-oracle.py first to populate and fingerprint the upstream helpers.
"""
from pathlib import Path
import hashlib
import json
import sys
HERE = Path(__file__).resolve().parent
def blob(data):
    return '"' + ''.join('\\%02x' % b for b in data) + '"'
sys.path.insert(0, '/tmp/bitcoin-base58-audit')
from test_framework.key import compute_xonly_pubkey, tweak_add_privkey, tweak_add_pubkey, sign_schnorr, TaggedHash, ORDER
rows = []
msg = bytes(range(32))
aux = bytes(reversed(range(32)))
for integer in [1,2,3,6,ORDER-1]:
    secret = integer.to_bytes(32,'big')
    public, parity = compute_xonly_pubkey(secret)
    for root in [None, bytes(32), bytes(range(32))]:
        tweak = TaggedHash('TapTweak', public + (root or b''))
        tweaked = tweak_add_privkey(secret, tweak)
        output, output_parity = tweak_add_pubkey(public,tweak)
        signature = sign_schnorr(tweaked, msg, aux)
        rootmo = 'null' if root is None else '?' + blob(root)
        rows.append(f'  ({blob(secret)}, {blob(public)}, {rootmo}, {blob(tweaked)}, {blob(output)}, {int(output_parity)}, {blob(signature)}),')
tags = []
for tag in ['', 'TapTweak', 'é😀', '\x00TapLeaf']:
    for msg2 in [b'', bytes(range(256))]:
        digest = hashlib.sha256(tag.encode()).digest()
        expected = hashlib.sha256(digest+digest+msg2).digest()
        tagmo = json.dumps(tag,ensure_ascii=False).replace('\\u0000','\\00')
        tags.append(f'assert H.taggedHash({tagmo}, {blob(msg2)}) == {blob(expected)};')
        tags.append(f'assert H.taggedHasher({tagmo})({blob(msg2)}) == {blob(expected)};')
base = json.loads((HERE.parent/'hash-codec/bip350-segwit.json').read_text())
addresses=[]
for row in base['valid']:
    address=row['address'];version=row['version'];program=bytes.fromhex(row['program'])
    network='#mainnet' if address[:2].lower()=='bc' else '#testnet'
    wrong='#testnet' if network=='#mainnet' else '#mainnet'
    payload=f'#witness {{ version = {version}; program = {blob(program)} }}'
    script=bytes([0 if version==0 else 0x50+version,len(program)])+program
    addresses.append(f'assert A.decode("{address}", {network}) == #ok({payload});')
    addresses.append(f'assert A.encode({payload}, {network}) == #ok("{address.lower()}");')
    addresses.append(f'assert A.scriptPubKey("{address}", {network}) == #ok({blob(script)});')
    addresses.append(f'assert A.decode("{address}", {wrong}) == #err(#wrongNetwork);')
for row in base['invalid']:
    address=row['address'];network='#mainnet' if address[:2].lower()=='bc' else '#testnet'
    addresses.append(f'switch (A.decode("{address}", {network})) {{ case (#err _) {{}}; case (#ok _) assert false }};')
source='''// Additional independent wallet expectations: Core v29.0 and BIP350.
import A "mo:fast/Bitcoin/Address";
import H "mo:fast/Bitcoin/Hash";
import K "mo:fast/Secp256k1";
import Base58Check "mo:fast/Base58Check";
import Prim "mo:⛔";
func get<X,E>(x : {#ok:X;#err:E}) : X { switch x {case (#ok v) v;case (#err _) {assert false;loop{}}} };
func fill(n : Nat, b : Nat8) : Blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(n,func(_){b}));
func slice(bytes : Blob, start : Nat, n : Nat) : Blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(n,func(i){bytes[start+i]}));
'''
source += 'let rows : [(Blob,Blob,?Blob,Blob,Blob,Nat8,Blob)] = [\n'+'\n'.join(rows)+'\n];\n'
source += f'''for ((secret, publicKey, root, expectedSecret, output, parity, signature) in rows.values()) {{
  assert A.taprootSecretKey(secret,root) == #ok expectedSecret;
  assert A.taprootOutputKey(publicKey,root) == #ok({{publicKey=output;parity}});
  assert slice(get(K.derivePublicKey(expectedSecret)),1,32) == output;
  assert A.signTaprootKeyPath(secret,root,{blob(msg)},{blob(aux)}) == #ok signature;
  assert K.schnorrVerify(output,{blob(msg)},signature) == #ok true;
}};
'''
source += '\n'.join(tags+addresses)+'\n'
source += '''let secret : Blob = "\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\01";
assert A.taprootSecretKey("",null) == #err(#invalidSecretKey);
assert A.taprootSecretKey(fill(32,0),null) == #err(#invalidSecretKey);
assert A.taprootSecretKey(fill(32,0xff),null) == #err(#invalidSecretKey);
assert A.taprootSecretKey(secret,?fill(31,0)) == #err(#invalidMerkleRoot);
assert A.taprootSecretKey(secret,?fill(33,0)) == #err(#invalidMerkleRoot);
assert A.signTaprootKeyPath(secret,null,fill(31,0),fill(32,0)) == #err(#invalidDigest);
assert A.signTaprootKeyPath(secret,null,fill(33,0),fill(32,0)) == #err(#invalidDigest);
assert A.signTaprootKeyPath(secret,null,fill(32,0),fill(31,0)) == #err(#invalidAuxiliaryRandomness);
assert A.signTaprootKeyPath(secret,null,fill(32,0),fill(33,0)) == #err(#invalidAuxiliaryRandomness);
assert A.decode(Base58Check.encode(""),#mainnet) == #err(#invalidLength);
assert A.decode(Base58Check.encode(fill(20,0)),#mainnet) == #err(#invalidLength);
assert A.decode(Base58Check.encode(fill(22,0)),#mainnet) == #err(#invalidLength);
assert A.decode(Base58Check.encode(fill(21,1)),#mainnet) == #err(#invalidAddress);
let key = get(K.derivePublicKey(secret));
assert A.p2pkh(key,#testnet) == A.p2pkh(key,#regtest);
assert A.p2sh("",#testnet) == A.p2sh("",#regtest);
let reg = get(A.p2wpkh(key,#regtest));
assert A.decode(reg,#testnet) == #err(#wrongNetwork);
assert A.decode(reg,#mainnet) == #err(#wrongNetwork);
for (version in ([0,1,16,17,255] : [Nat8]).values()) {
  for (n in [0,1,2,19,20,21,31,32,33,40,41].values()) {
    let input = #witness {version;program=fill(n,0x42)};
    let result = A.encode(input,#mainnet);
    let valid = version <=16 and n>=2 and n<=40 and (version!=0 or n==20 or n==32);
    if (valid) assert A.decode(get(result),#mainnet)==#ok(input)
    else assert result==#err(#invalidWitness);
  };
};
'''
(HERE/'wallet.mo').write_text(source)
(HERE/'wallet-provenance.json').write_text(json.dumps({'oracle':'Bitcoin Core v29.0 key.py','tweak_and_signature_cases':len(rows),'bip350_valid':len(base['valid']),'bip350_invalid':len(base['invalid']),'generated_sha256':hashlib.sha256(source.encode()).hexdigest()},indent=2)+'\n')
print('Generated',len(rows),'additional secret/public/signature vectors')
