#!/usr/bin/env python3
"""Independent curve audit; run inside the matching compiler's Nix shell.

Requires --secp and --p256 isolated dist package directories. All generated
fixtures, compiler products, native targets and logs go under root _build.
"""
import argparse
import csv
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import subprocess
import tomllib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
WORK = ROOT / "_build/crypto-audit/curves"
WP256 = ROOT / "plugins/p256/tests/vectors/wycheproof-ecdsa-secp256r1-sha256.json"
WK256 = HERE / "vectors/wycheproof-secp256k1-sha256.json"
CURVES = {
    "secp256k1": dict(
        p=int("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F",16),
        n=int("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141",16),
        a=0,
        g=(int("79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798",16),
           int("483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8",16)),
        module="Secp256k1", corpus=WK256),
    "p256": dict(
        p=int("FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF",16),
        n=int("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551",16),
        a=-3,
        g=(int("6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296",16),
           int("4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5",16)),
        module="P256", corpus=WP256),
}


def octets(n):
    return n.to_bytes(32, "big")


def add(curve, left, right):
    if left is None:
        return right
    if right is None:
        return left
    x,y = left
    u,v = right
    p = curve["p"]
    if x == u:
        if (y+v) % p == 0:
            return None
        slope = (3*x*x + curve["a"]) * pow(2*y, -1, p) % p
    else:
        slope = (v-y) * pow(u-x, -1, p) % p
    rx = (slope*slope-x-u) % p
    return rx, (slope*(x-rx)-y) % p


def multiply(curve, scalar):
    total = None
    point = curve["g"]
    while scalar:
        if scalar & 1:
            total = add(curve,total,point)
        point = add(curve,point,point)
        scalar >>= 1
    return total


def sign(curve, secret, digest, low_s):
    """RFC6979 section 3.2, using Python integers and hashlib only."""
    n = curve["n"]
    z = int.from_bytes(digest,"big")
    material = octets(secret) + octets(z % n)
    key,value = bytes(32),bytes([1])*32
    mac = lambda k,m: hmac.new(k,m,hashlib.sha256).digest()
    key = mac(key,value+b"\0"+material)
    value = mac(key,value)
    key = mac(key,value+b"\1"+material)
    value = mac(key,value)
    while True:
        value = mac(key,value)
        nonce = int.from_bytes(value,"big")
        if 0 < nonce < n:
            r = multiply(curve,nonce)[0] % n
            s = pow(nonce,-1,n)*(z+r*secret) % n
            if r and s:
                if low_s:
                    s = min(s,n-s)
                return octets(r)+octets(s)
        key = mac(key,value+b"\0")
        value = mac(key,value)


def compact_from_der(encoded, n):
    """Independent strict DER decoder for expected public API status values."""
    if len(encoded)<8 or len(encoded)>72 or encoded[0]!=48 or encoded[1]!=len(encoded)-2:
        return None
    offset=2
    values=[]
    for _ in range(2):
        if offset+2>len(encoded) or encoded[offset]!=2:
            return None
        length=encoded[offset+1]
        raw=encoded[offset+2:offset+2+length]
        if not 1<=length<=33 or len(raw)!=length or raw[0]>=128:
            return None
        if length>1 and raw[0]==0 and raw[1]<128:
            return None
        value=int.from_bytes(raw,"big")
        if not 0<value<n:
            return None
        values.append(octets(value))
        offset+=2+length
    return b"".join(values) if offset==len(encoded) else None


def blob(value):
    return '"'+''.join(f'\\{x:02x}' for x in value)+'"'


def flags(name,path):
    return (f'//MOC-FLAG --package fast {path.parent.parent / "packages/fast/src"} --plugin {path} --sanity-checks\n'
            f'import Curve "mo:fast/{CURVES[name]["module"]}";\n')


def fixtures(name,path):
    curve=CURVES[name]
    corpus=json.loads(curve["corpus"].read_text())
    text=flags(name,path)+'''type Vector = { key : Blob; digest : Blob; der : Blob; compact : ?Blob; valid : Bool };
let vectors : [Vector] = [
'''
    count=0
    for group in corpus["testGroups"]:
        key=bytes.fromhex(group["publicKey"]["uncompressed"])
        for vector in group["tests"]:
            der=bytes.fromhex(vector["sig"])
            digest=hashlib.sha256(bytes.fromhex(vector["msg"])).digest()
            compact=compact_from_der(der,curve["n"])
            encoded='null' if compact is None else '?'+blob(compact)
            text+=(f'  // Wycheproof tcId {vector["tcId"]}\n'
                   f'  {{ key={blob(key)}; digest={blob(digest)}; der={blob(der)}; compact={encoded}; valid={str(vector["result"]=="valid").lower()} }},\n')
            count+=1
    text+=''' ];
for (v in vectors.values()) {
  switch (v.compact) {
    case null { assert Curve.signatureFromDer(v.der) == #err(#invalidSignature); assert not v.valid };
    case (?compact) {
      assert Curve.signatureFromDer(v.der) == #ok(compact);
      assert Curve.signatureToDer(compact) == #ok(v.der);
      assert Curve.verifyPrehash(v.key,v.digest,compact) == #ok(v.valid);
    };
  };
};
'''
    (WORK/"run"/f"audit-{name}-wycheproof.mo").write_text(text)
    text=flags(name,path)
    cases=[]
    n=curve["n"]
    for secret in [1,3,n-1]:
        for z in [0,1,n-1,n,n+1,2**256-1]:
            x,y=multiply(curve,secret)
            key=bytes([2+(y&1)])+octets(x)
            digest=octets(z)
            signature=sign(curve,secret,digest,name=="secp256k1")
            cases.append(dict(secret=octets(secret).hex(),digest=digest.hex(),public=key.hex(),signature=signature.hex()))
            text+=(f'assert Curve.derivePublicKey({blob(octets(secret))}) == #ok({blob(key)});\n'
                   f'assert Curve.signPrehash({blob(octets(secret))},{blob(digest)}) == #ok({blob(signature)});\n'
                   f'assert Curve.verifyPrehash({blob(key)},{blob(digest)},{blob(signature)}) == #ok(true);\n')
    (WORK/"run"/f"audit-{name}-rfc6979.mo").write_text(text)
    extra={}
    if name == "secp256k1":
        text=flags(name,path)
        vector_path=path.parent.parent/"plugins/secp256k1/tests/vectors/bip340.csv"
        rows=list(csv.DictReader(vector_path.open()))
        for row in rows:
            key=bytes.fromhex(row["public key"])
            message=bytes.fromhex(row["message"])
            signature=bytes.fromhex(row["signature"])
            x=int.from_bytes(key,"big")
            rhs=(x*x*x+7)%curve["p"]
            root=pow(rhs,(curve["p"]+1)//4,curve["p"])
            if len(key)!=32 or x>=curve["p"] or root*root%curve["p"]!=rhs:
                expected='#err(#invalidPublicKey)'
            elif len(signature)!=64 or int.from_bytes(signature[:32],"big")>=curve["p"] or int.from_bytes(signature[32:],"big")>=n:
                expected='#err(#invalidSignature)'
            else:
                expected='#ok('+str(row["verification result"]=="TRUE").lower()+')'
            text+=f'assert Curve.schnorrVerify({blob(key)},{blob(message)},{blob(signature)}) == {expected};\n'
            if row["secret key"]:
                secret=bytes.fromhex(row["secret key"])
                aux=bytes.fromhex(row["aux_rand"])
                text+=f'assert Curve.schnorrSign({blob(secret)},{blob(message)},{blob(aux)}) == #ok({blob(signature)});\n'
        for secret in [1,2,3,n-1]:
            px,py=multiply(curve,secret)
            normalized=secret if py%2==0 else n-secret
            for tweak in [0,1,n-normalized,n-1,n,n+1]:
                result=(normalized+tweak)%n
                expected=('#err(#invalidScalar)' if tweak>=n else
                          '#err(#pointAtInfinity)' if result==0 else '#ok('+blob(octets(result))+')')
                text+=f'assert Curve.tweakXOnlySecretKey({blob(octets(secret))},{blob(octets(tweak))}) == {expected};\n'
                if tweak<n and result:
                    x,y=multiply(curve,result)
                    public=bytes([2+y%2])+octets(x)
                    text+=f'assert Curve.tweakXOnlyPublicKey({blob(octets(px))},{blob(octets(tweak))}) == #ok({blob(public)});\n'
        text+=(f'assert Curve.schnorrVerify({blob(octets(curve["g"][0]))},"",{blob(bytes(64))}) == #ok(false);\n'
               f'assert Curve.baseMultiply({blob(bytes(32))}) == #err(#pointAtInfinity);\n')
        (WORK/"run"/"audit-secp256k1-bip340-tweaks.mo").write_text(text)
        extra=dict(bip340_vectors=len(rows),bip341_secret_tweak_cases=24)
    return dict(wycheproof=count,rfc6979_boundary_cases=len(cases),signing_vectors=cases,**extra)


def run(command, logfile, env=None, cwd=ROOT):
    with logfile.open("w") as log:
        result=subprocess.run([str(x) for x in command],cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
    print(f'{logfile.name}: exit {result.returncode}',flush=True)
    if result.returncode:
        print(logfile.read_text()[-12000:],flush=True)
    return result.returncode


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motoko",type=Path,required=True)
    parser.add_argument("--secp",type=Path,required=True)
    parser.add_argument("--p256",type=Path,required=True)
    args=parser.parse_args()
    paths={"secp256k1":args.secp.resolve(),"p256":args.p256.resolve()}
    WORK.mkdir(parents=True,exist_ok=True)
    (WORK/"run").mkdir(exist_ok=True)
    # Validate the independent oracle against the exact published RFC6979 A.2.5 answer.
    expected="efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8"
    assert sign(CURVES["p256"],int("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721",16),hashlib.sha256(b"sample").digest(),False).hex()==expected
    report={"schema":1,"scope":"independent secp256k1 and P256 source/IR/lowered/Wasm/native audit", "plugins":{}}
    sources={}
    for name,path in paths.items():
        stage=path.parent.parent
        source=stage/"plugins"/name
        assert source.is_dir(),f"Expected isolated stage sources for {path}"
        sources[name]=source
        manifest=json.loads((path/"build.json").read_text())
        prefix=f"plugins/{name}/"
        for filename,digest in manifest["source_sha256"].items():
            if filename.startswith(prefix):
                assert sha(stage/filename)==digest, f"Stale source for {name}: {filename}"
        artifacts={p.name:sha(p) for p in path.iterdir() if p.is_file()}
        for filename,digest in manifest["sha256"].items():
            assert artifacts[filename]==digest
        inspection=subprocess.check_output(["wasm-objdump","-x",str(path/"runtime.wasm")],text=True)
        (WORK/f"{name}-runtime.txt").write_text(inspection)
        import_section=inspection.split("Import[",1)[1].split("\nFunction[",1)[0]
        assert "func[" not in import_section, "Curve runtime unexpectedly imports native functions"
        globals_section=inspection.split("\nGlobal[",1)
        if len(globals_section)>1:
            assert "mutable=1" not in globals_section[1].split("\nExport[",1)[0]
        report["plugins"][name]={"artifact_directory":str(path),"artifact_sha256":artifacts,
            "source_sha256":{str(p.relative_to(source)):sha(p) for p in source.rglob("*") if p.is_file() and "_out" not in p.parts},
            "public_module_sha256":sha(stage/"packages/fast/src"/(CURVES[name]["module"]+".mo")),
            "runtime_imports":import_section.splitlines()[1:],
            "runtime_static_bytes":int(re.search(r"mem_size\s*:\s*(\d+)",inspection).group(1)),
            "runtime_wasm_bytes":(path/"runtime.wasm").stat().st_size,
            **fixtures(name,path)}
    native=WORK/"native"
    native.mkdir(exist_ok=True)
    # Audit the exact dependency used by the kernel, including the local k256
    # constructor patch; compiling against the registry copy would miss it.
    dependency=tomllib.loads((sources["secp256k1"]/"runtime/Cargo.toml").read_text())["dependencies"]["k256"]
    assert dependency["version"]=="=0.13.4"
    k256_path=""
    if "path" in dependency:
        resolved=(sources["secp256k1"]/"runtime"/dependency["path"]).resolve()
        assert (resolved/"Cargo.toml").is_file()
        k256_path=",path="+json.dumps(str(resolved))
    report["native_k256_dependency"]={**dependency,"resolved_path":str(resolved) if k256_path else None}
    (native/"Cargo.toml").write_text('''[package]
name = "independent-curve-audit"
version = "0.0.0"
edition = "2024"
[workspace]
[lib]
path = "lib.rs"
[dependencies]
k256 = {version="=0.13.4"K256_PATH,default-features=false,features=["ecdsa","schnorr"]}
p256 = {version="=0.13.2",default-features=false,features=["ecdsa"]}
ecdsa = {version="=0.16.9",default-features=false,features=["signing","verifying"]}
sha2 = {version="=0.10.9",default-features=false}
serde_json = "=1.0.149"
'''.replace("K256_PATH",k256_path))
    (native/"lib.rs").write_text(
        '#[path='+json.dumps(str(sources["secp256k1"]/"runtime/src/lib.rs"))+'] mod secp;\n'
        '#[path='+json.dumps(str(sources["p256"]/"runtime/src/lib.rs"))+'] mod p256_kernel;\n'
        +(HERE/"native.rs").read_text())
    env=os.environ.copy()
    env.update(AUDIT_SECP_VECTORS=str(WK256),AUDIT_P256_VECTORS=str(WP256))
    report["native_exit"]=run(["cargo","test","--offline","--manifest-path",native/"Cargo.toml","--lib","--target-dir",native/"target"],WORK/"native.log",env=env)
    report["motoko_exit"]=run(["test-runner","-b","-j","2",WORK/"run"],WORK/"motoko.log",cwd=args.motoko.resolve())
    report["corpus_sha256"]={str(p.relative_to(ROOT)):sha(p) for p in [WP256,WK256]}
    report["audit_sha256"]={str(p.relative_to(HERE)):sha(p) for p in [HERE/"native.rs",Path(__file__).resolve()]}
    report["generated_fixture_sha256"]={p.name:sha(p) for p in sorted((WORK/"run").glob("*.mo"))}
    report["executed_engines"]={}
    for fixture in sorted((WORK/"run").glob("*.mo")):
        expected=["run","run-ir","run-low","wasm-run","valid"]
        files={suffix:WORK/"run/_out"/(fixture.stem+"."+suffix) for suffix in expected}
        report["executed_engines"][fixture.name]={suffix:sha(path) for suffix,path in files.items() if path.is_file()}
        if report["motoko_exit"]==0:
            assert all(path.is_file() for path in files.values()), "Runner omitted a required execution engine"
    report["logs"]={p.name:sha(p) for p in [WORK/"native.log",WORK/"motoko.log"]}
    report["passed"]=report["native_exit"]==0 and report["motoko_exit"]==0
    destination=HERE/"evidence.json"
    destination.write_text(json.dumps(report,indent=2)+"\n")
    print(f'Evidence: {destination}; passed={report["passed"]}',flush=True)
    raise SystemExit(0 if report["passed"] else 1)


if __name__=="__main__":
    main()
