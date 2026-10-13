#!/usr/bin/env python3
"""Independent prepared-key expectations; old audit remains unchanged."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location("prior", ROOT / "tests/crypto-audit/round3/secp256k1/generate.py")
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

HELPERS = r'''
func _preparedEcdsa(key : Blob, digest : Blob, signature : Blob) : Curve.Result<Bool> {
  switch (Curve.preparePublicKey(key)) {
    case (#err e) #err(e);
    case (#ok p) Curve.verifyPrehashPrepared(p, digest, signature);
  }
};
func _preparedSchnorr(key : Blob, message : Blob, signature : Blob) : Curve.Result<Bool> {
  switch (Curve.prepareSchnorrPublicKey(key)) {
    case (#err e) #err(e);
    case (#ok p) Curve.schnorrVerifyPrepared(p, message, signature);
  }
};
func _preparedSign(key : Blob, message : Blob, aux : Blob) : Curve.Result<Blob> {
  switch (Curve.prepareSchnorrSecretKey(key)) {
    case (#err e) #err(e);
    case (#ok p) Curve.schnorrSignPrepared(p, message, aux);
  }
};
func _expectErr<T>(result : Curve.Result<T>, expected : Curve.Error) {
  switch result { case (#ok _) assert false; case (#err error) assert error == expected }
};
func _ok<T>(result : Curve.Result<T>) : T {
  switch result { case (#ok value) value; case (#err _) { assert false; loop {} } }
};
'''

def cache(point):
    points = [v.multiply_point(point, 2*i+1) for i in range(8)]
    beta = int("7AE96A2B657C07106E64479EAC3434E99CF0497512F58995C1396C28719501EE",16)
    points += [(x*beta%v.p,y) for x,y in points]
    return b"".join(v.octets(x)+v.octets(y) for x,y in points)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plugin",type=Path,required=True)
    parser.add_argument("--out",type=Path,required=True)
    args=parser.parse_args()
    plugin,out=args.plugin.resolve(),args.out.resolve()
    subprocess.run([sys.executable,ROOT/"tests/crypto-audit/round3/secp256k1/generate.py","--plugin",plugin,"--out",out],check=True)
    run=out/"run"
    originals=sorted(run.glob("*.mo"))
    for src in originals:
        text=src.read_text()
        first,body=text.split("\n",1)
        body=body.replace("Curve.verifyPrehash(","_preparedEcdsa(").replace("Curve.schnorrVerify(","_preparedSchnorr(").replace("Curve.schnorrSign(","_preparedSign(")
        marker='import Curve "mo:fast/Secp256k1";'
        body=body.replace(marker,marker+"\n"+HELPERS)
        (run/src.name.replace("audit-secp256k1-","prepared-secp256k1-")).write_text(first+"\n"+body)
    text=v.audit.flags("secp256k1",plugin)+HELPERS
    secret=v.octets(3); point=v.multiply(3); key=v.encoded(point); x=v.octets(point[0]); digest=bytes(32)
    signature=v.audit.sign(v.curve,3,digest,True); schnorr=v.schnorr(3,digest,digest)
    for name,value in [("secret",secret),("key",key),("x",x),("digest",digest),("signature",signature),("schnorr",schnorr)]:
        text+=f"let {name} : Blob = {v.blob(value)};\n"
    text+=r'''
let ecdsa = _ok(Curve.preparePublicKey(key));
let publicSchnorr = _ok(Curve.prepareSchnorrPublicKey(x));
let signer = _ok(Curve.prepareSchnorrSecretKey(secret));
var sequence : Nat = 0;
func arg(n : Nat, value : Blob) : Blob { sequence := sequence*10+n; value };
func keyArg() : Curve.PreparedPublicKey { sequence := sequence*10+1; ecdsa };
func publicArg() : Curve.PreparedSchnorrPublicKey { sequence := sequence*10+1; publicSchnorr };
func secretArg() : Curve.PreparedSchnorrSecretKey { sequence := sequence*10+1; signer };
assert Curve.verifyPrehashPrepared(keyArg(),arg(2,digest),arg(3,signature)) == #ok(true);
assert sequence == 123;
sequence := 0;
assert Curve.verifyPrehashPrepared(keyArg(),arg(2,""),arg(3,"")) == #err(#invalidDigest);
assert sequence == 123;
sequence := 0;
assert Curve.verifyPrehashPrepared(keyArg(),arg(2,digest),arg(3,"")) == #err(#invalidSignature);
assert sequence == 123;
sequence := 0;
assert Curve.schnorrVerifyPrepared(publicArg(),arg(2,digest),arg(3,schnorr)) == #ok(true);
assert sequence == 123;
sequence := 0;
assert Curve.schnorrVerifyPrepared(publicArg(),arg(2,digest),arg(3,"")) == #err(#invalidSignature);
assert sequence == 123;
sequence := 0;
assert Curve.schnorrSignPrepared(secretArg(),arg(2,digest),arg(3,digest)) == #ok(schnorr);
assert sequence == 123;
sequence := 0;
assert Curve.schnorrSignPrepared(secretArg(),arg(2,digest),arg(3,"")) == #err(#invalidAuxiliaryRandomness);
assert sequence == 123;
let verify = Curve.verifyPrehashPrepared;
let publicVerify = Curve.schnorrVerifyPrepared;
let sign = Curve.schnorrSignPrepared;
let factories = [Curve.preparePublicKey, Curve.preparePublicKey];
assert verify(_ok(factories[1](key)),digest,signature) == #ok(true);
assert publicVerify(publicSchnorr,digest,schnorr) == #ok(true);
assert sign(signer,digest,digest) == #ok(schnorr);
// Earlier errors cannot change subsequent valid operations or any cached key.
assert Curve.verifyPrehashPrepared(ecdsa,digest,signature) == #ok(true);
assert Curve.schnorrSignPrepared(signer,digest,digest) == #ok(schnorr);
'''
    factory_cases=0
    for bad in [b"",bytes(31),bytes(32),bytes(33),v.octets(v.n),v.octets(v.n+1),bytes([255])*32]:
        text+=f"_expectErr(Curve.prepareSchnorrSecretKey({v.blob(bad)}), #invalidSecretKey);\n"
        factory_cases+=1
    for bad in [b"",b"\0",bytes(33),bytes(65),b"\6"+v.octets(point[0])+v.octets(point[1]),b"\2"+v.octets(v.p),key+b"\0",b"\4"+v.octets(point[0])+v.octets((point[1]+1)%v.p)]:
        text+=f"_expectErr(Curve.preparePublicKey({v.blob(bad)}), #invalidPublicKey);\n"
        factory_cases+=1
    for bad in [b"",bytes(31),bytes(33),bytes(32),v.octets(v.p),bytes([255])*32]:
        text+=f"_expectErr(Curve.prepareSchnorrPublicKey({v.blob(bad)}), #invalidPublicKey);\n"
        factory_cases+=1
    for r,s in [(0,1),(1,0),(v.n,1),(1,v.n),(v.n-1,v.n-1)]:
        sig=v.octets(r)+v.octets(s)
        expected="#err(#invalidSignature)" if not (0<r<v.n and 0<s<v.n) else "Curve.verifyPrehash(key,digest,"+v.blob(sig)+")"
        text+=f"assert Curve.verifyPrehashPrepared(ecdsa,digest,{v.blob(sig)}) == {expected};\n"
    for r,s in [(0,0),(v.p,0),(0,v.n),(v.p-1,v.n-1)]:
        sig=v.octets(r)+v.octets(s)
        expected="#err(#invalidSignature)" if r>=v.p or s>=v.n else "Curve.schnorrVerify(x,digest,"+v.blob(sig)+")"
        text+=f"assert Curve.schnorrVerifyPrepared(publicSchnorr,digest,{v.blob(sig)}) == {expected};\n"
    (run/"prepared-secp256k1-bridge.mo").write_text(text)
    vectors=[]
    for i in range(32):
        d=[1,2,3,v.n-1][i] if i<4 else int.from_bytes(v.generated("prepared-independent/key",i),"big")%(v.n-1)+1
        point=v.multiply(d); even=(point[0], point[1] if point[1]%2==0 else v.p-point[1]); normalized=d if point[1]%2==0 else v.n-d
        msg=(v.generated("prepared-independent/message",i)*8)[:[0,1,17,31,32,33,64,255][i%8]]
        aux=v.generated("prepared-independent/aux",i); digest=v.generated("prepared-independent/digest",i)
        fields=[v.octets(d),v.encoded(point),b"\4"+v.octets(point[0])+v.octets(point[1]),cache(point),v.octets(point[0]),cache(even),v.octets(normalized)+v.octets(point[0]),msg,aux,v.schnorr(d,msg,aux),digest,v.audit.sign(v.curve,d,digest,True)]
        vectors.append("\t".join(f.hex() for f in fields))
    (out/"native-vectors.tsv").write_text("\n".join(vectors)+"\n")
    fail=out/"fail"
    fail.mkdir(exist_ok=True)
    rejected={
        "blob-to-public": 'let bytes : Blob = ""; let forged : Curve.PreparedPublicKey = bytes;',
        "blob-to-schnorr-public": 'let bytes : Blob = ""; let forged : Curve.PreparedSchnorrPublicKey = bytes;',
        "blob-to-schnorr-secret": 'let bytes : Blob = ""; let forged : Curve.PreparedSchnorrSecretKey = bytes;',
        "cross-public": 'func wrong(key : Curve.PreparedSchnorrPublicKey) { ignore Curve.verifyPrehashPrepared(key,"","") };',
        "cross-schnorr": 'func wrong(key : Curve.PreparedPublicKey) { ignore Curve.schnorrVerifyPrepared(key,"","") };',
        "cross-secret": 'func wrong(key : Curve.PreparedSchnorrPublicKey) { ignore Curve.schnorrSignPrepared(key,"","") };',
        "reveal-payload": 'func reveal(key : Curve.PreparedSchnorrSecretKey) : Blob { key };',
        "shared-parameter": 'persistent actor { public func receive(key : Curve.PreparedPublicKey) : async () {} };',
        "stable-field": 'persistent actor { var key : ?Curve.PreparedSchnorrSecretKey = null };',
    }
    for name,body in rejected.items():
        (fail/(name+".mo")).write_text(v.audit.flags("secp256k1",plugin)+body+"\n")
    inherited=json.loads((out/"generated.json").read_text())
    report={"original":inherited,"prepared_replayed_fixtures":len(originals),"bridge_factory_error_cases":factory_cases,"rejected_type_fixtures":len(rejected),"native_independent_keys":32,"generated_native_public_points":1024,"fixture_sha256":{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(run.glob("*.mo"))},"native_vectors_sha256":hashlib.sha256((out/"native-vectors.tsv").read_bytes()).hexdigest()}
    (out/"generated.json").write_text(json.dumps(report,indent=2)+"\n")
    print(f"{len(originals)} direct plus {len(originals)+1} prepared fixtures, 32 independent native key/cache/signature sets")

if __name__ == "__main__": main()
