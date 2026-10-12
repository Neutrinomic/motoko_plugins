#!/usr/bin/env python3
"""Composed Bitcoin hashing, address and BIP32 workflows; published BIP32/BIP86 vectors."""
import hashlib,json
from common import actor,blob,save_case,HERE
cases=[]
un='func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};'
def add(name,impl,imports,decls,op,expected,plugins=(),configure='',typ='Blob',out='result',initial='""',notes=''):
    case=dict(name=name,family='bitcoin-composition',implementation=impl,comparison='complete-public-api',plugins=list(plugins),expected_hex=expected.hex(),notes=notes)
    cases.append(save_case(case,actor(imports,un+'\n'+decls,configure,op,out,typ,initial),'bitcoin-cases'))
key=bytes.fromhex('0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798')
for mode,expected,base in [('hash160',hashlib.new('ripemd160',hashlib.sha256(key).digest()).digest(),'hash160'),('sha256d',hashlib.sha256(hashlib.sha256(key).digest()).digest(),'doubleSHA256')]:
    for impl,path,plugins,arg in [('native','fast/Bitcoin/Hash',['sha256','ripemd160'],'input'),('mops-bitcoin','bitcoin/Hash',[],'Prim.blobToArray(input)')]:
        expr=f'H.{mode}(input)' if impl=='native' else f'Prim.arrayToBlob(H.{base}({arg}))'
        add(f'bitcoin-{mode}-pubkey',impl,f'import H "mo:{path}";',f'transient let input : Blob = {blob(key)};',f'result := {expr};',expected,plugins)
# P2PKH: native validates curve membership while baseline hashes bytes directly.
add('bitcoin-p2pkh','native','import A "mo:fast/Bitcoin/Address";',f'transient let key : Blob = {blob(key)};','result := unwrap(A.p2pkh(key,#mainnet));',b'1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',['sha256','ripemd160','secp256k1','base58','bech32'],typ='Text',out='Prim.encodeUtf8(result)',notes='Native validates SEC1 curve membership; baseline hashes SEC1 bytes without validation. Full public API cost includes extra native checking.')
add('bitcoin-p2pkh','mops-bitcoin','import A "mo:bitcoin/bitcoin/P2pkh";\nimport Curve "mo:bitcoin/ec/Curves";',f'transient let key : Blob = {blob(key)};','result := A.deriveAddress(#Mainnet,(Prim.blobToArray(key),Curve.secp256k1));',b'1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH',typ='Text',out='Prim.encodeUtf8(result)',notes='Baseline does not validate key; valid vector is equivalent output.')
# SegWit encoding workflow, including HASH160. Native additionally validates compressed key.
address=b'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'
add('bitcoin-p2wpkh','native','import A "mo:fast/Bitcoin/Address";',f'transient let key : Blob = {blob(key)};','result := unwrap(A.p2wpkh(key,#mainnet));',address,['sha256','ripemd160','secp256k1','base58','bech32'],typ='Text',out='Prim.encodeUtf8(result)',notes='Native validates compressed SEC1 curve membership; baseline composition starts from trusted bytes.')
add('bitcoin-p2wpkh','mops-bitcoin','import H "mo:bitcoin/Hash";\nimport S "mo:bitcoin/Segwit";',f'transient let key : Blob = {blob(key)};','result := unwrap(S.encode("bc",{version=0;program=H.hash160(Prim.blobToArray(key))}));',address,typ='Text',out='Prim.encodeUtf8(result)')
# Explicit payload API matches the Mops byte-hashing contract without key validation.
for kind,address in [('p2pkh',b'1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH'),('p2wpkh',b'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4')]:
    payload='#p2pkh(H.hash160(key))' if kind=='p2pkh' else '#witness({version=0;program=H.hash160(key)})'
    add(f'bitcoin-{kind}','native-prevalidated','import A "mo:fast/Bitcoin/Address";\nimport H "mo:fast/Bitcoin/Hash";',f'transient let key : Blob = {blob(key)};',f'result := unwrap(A.encode({payload},#mainnet));',address,['sha256','ripemd160','secp256k1','base58','bech32'],typ='Text',out='Prim.encodeUtf8(result)',notes='Explicit payload API performs HASH160+address encode on trusted public-key bytes, matching Mops validation semantics; curve membership validation intentionally outside this API contract.')
# Public derivation from BIP32 test vector 2. Parsing outside preparation; serialize included.
root='xpub661MyMwAqRbcFW31YEwpkMuc5THy2PSt5bDMsktWQcFF8syAmRUapSCGu8ED9W6oDMSgv6Zz8idoc4a6mr8BDzTJY47LJhkJ8UB7WEGuduB'
child='xpub69H7F5d8KSRgmmdJg2KhpAK8SR3DjMwAdkxj3ZuxV27CprR9LgpeyGmXUbC6wb7ERfvrnKZjXoUmmDznezpbZb7ap6r1D3tgFxHmwMkQTPH'
plugins=['sha256','ripemd160','hmac-sha2','secp256k1','base58']
add('bitcoin-bip32-child0','native','import B "mo:fast/Bitcoin/Bip32";',f'transient var parent = unwrap(B.parse("{root}"));','result := unwrap(B.serialize(unwrap(B.deriveChild(parent,0))));',child.encode(),plugins,configure=f'parent := unwrap(B.parse("{root}"));',typ='Text',out='Prim.encodeUtf8(result)',notes='BIP32 official vector2. Parse outside measurement; deriveChild and serialized xpub complete output inside.')
add('bitcoin-bip32-child0','mops-bitcoin','import B "mo:bitcoin/Bip32";',f'transient var parent = switch(B.parse("{root}",null)){{case(?x)x;case(null)Prim.trap("parse")}};','let ?child = parent.deriveChild(0) else Prim.trap("derive");result := child.serialize();',child.encode(),configure=f'parent := switch(B.parse("{root}",null)){{case(?x)x;case(null)Prim.trap("parse")}};',typ='Text',out='Prim.encodeUtf8(result)')
# Complete account-xpub to receive-address workflow. Mops helper requires 32-byte
# root, so compose its public tagged hash and tweak primitive to support empty tree.
account='xpub6BgBgsespWvERF3LHQu6CnqdvfEvtMcQjYrcRzx53QJjSxarj2afYWcLteoGVky7D3UKDP9QyrLprQ3VCECoY49yfdDEHGCtMMj92pReUsQ'
expected=b'bc1p5cyxnuxmeuwuvkwfem96lqzszd02n6xdcjrs20cac6yqjjwudpxqkedrcr'
imports='import B "mo:fast/Bitcoin/Bip32";\nimport A "mo:fast/Bitcoin/Address";\nimport S "mo:fast/Secp256k1";'
op=f'let account = unwrap(B.parse("{account}"));let child = unwrap(B.derivePath(account,[0,0]));let internal = unwrap(S.xOnlyPublicKey(child.publicKey));result := unwrap(A.p2tr(internal,null,#mainnet));'
add('bitcoin-bip86-receive-address','native',imports,'',op,expected,plugins+['bech32'],typ='Text',out='Prim.encodeUtf8(result)',notes='Complete published BIP86 account parse, two public child derivations, empty-tree TapTweak and Bech32m address. All conversion, validation and serialization included.')
imports='import B "mo:bitcoin/Bip32";\nimport H "mo:bitcoin/Hash";\nimport C "mo:bitcoin/Common";\nimport Curve "mo:bitcoin/ec/Curves";\nimport T "mo:bitcoin/bitcoin/P2tr";\nimport S "mo:bitcoin/Segwit";'
op=f'let ?account = B.parse("{account}",?(#fingerprint([]))) else Prim.trap("parse");let ?child = account.derivePath(#array([0,0])) else Prim.trap("derive");let internal = Prim.Array_tabulate<Nat8>(32,func(i){{child.key[i+1]}});let tweak = C.readBE256(H.taggedHash(internal,"TapTweak"),0);assert tweak < Curve.secp256k1.r;let out = unwrap(T.tweakPublicKey(internal,Curve.secp256k1.Fp(tweak)));result := unwrap(S.encode("bc",{{version=1;program=out.bip340_public_key}}));'
add('bitcoin-bip86-receive-address','mops-bitcoin',imports,'',op,expected,typ='Text',out='Prim.encodeUtf8(result)',notes='Equivalent empty-tree BIP86 composition using public taggedHash + tweakPublicKey because tweakFromKeyAndHash rejects empty roots. Scalar-order guard explicitly matches BIP341.')
(HERE/'bitcoin-cases/cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(f'Generated {len(cases)} Bitcoin composition implementations')
