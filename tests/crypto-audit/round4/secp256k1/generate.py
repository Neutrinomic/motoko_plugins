#!/usr/bin/env python3
"""Replay published/prepared corpus, then add independent round4 arithmetic edges."""
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
spec = importlib.util.spec_from_file_location('vectors', ROOT/'tests/crypto-audit/round3/secp256k1/generate.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plugin',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    plugin,out=args.plugin.resolve(),args.out.resolve()
    subprocess.run([sys.executable,ROOT/'tests/crypto-audit/prepared/secp256k1/generate.py','--plugin',plugin,'--out',out],check=True)
    run=out/'run'
    native=[]
    def native_case(op,a,b,c,status,result=b''):
        native.append('\t'.join([str(op),a.hex(),b.hex(),c.hex(),str(status),result.hex()]))
    helpers='''
func _ok<T>(r : Curve.Result<T>) : T { switch r { case (#ok x) x; case (#err _) { assert false; loop {} } } };
'''
    text=v.audit.flags('secp256k1',plugin)+helpers
    scalar_values=[0,1,2,7,8,9,15,16,17,v.n-2,v.n-1]
    scalar_values += [(2**bit+delta)%v.n for bit in [8,64,128,252,255] for delta in [-1,0,1]]
    scalar_values += [int.from_bytes(bytes([b])*32,'big')%v.n for b in [0x77,0x88,0xff]]
    scalar_values=list(dict.fromkeys(scalar_values))
    secret=6
    point=v.multiply(secret)
    normalized=secret if point[1]%2==0 else v.n-secret
    key=v.encoded(point)
    for scalar in scalar_values:
        raw=v.octets(scalar)
        for op,expr,result in [
            (5,f'baseMultiply({v.blob(raw)})',v.multiply(scalar)),
            (6,f'tweakPublicKey({v.blob(key)},{v.blob(raw)})',v.multiply((secret+scalar)%v.n)),
            (15,f'tweakXOnlyPublicKey({v.blob(v.octets(point[0]))},{v.blob(raw)})',v.multiply((normalized+scalar)%v.n))]:
            expected='#err(#pointAtInfinity)' if result is None else '#ok('+v.blob(v.encoded(result))+')'
            text+=f'assert Curve.{expr} == {expected};\n'
            a=raw if op==5 else key if op==6 else v.octets(point[0])
            native_case(op,a,b'' if op==5 else raw,b'',-7 if result is None else 33,b'' if result is None else v.encoded(result))
        if scalar:
            expected=v.encoded(v.multiply(scalar))
            text+=f'assert Curve.derivePublicKey({v.blob(raw)}) == #ok({v.blob(expected)});\n'
            native_case(0,raw,b'',b'',33,expected)
        tweaked=(normalized+scalar)%v.n
        text+=f'assert Curve.tweakXOnlySecretKey({v.blob(v.octets(secret))},{v.blob(raw)}) == '+('#err(#pointAtInfinity)' if tweaked==0 else '#ok('+v.blob(v.octets(tweaked))+')')+';\n'
        native_case(16,v.octets(secret),raw,b'',-7 if tweaked==0 else 32,b'' if tweaked==0 else v.octets(tweaked))
    # Cancellation/invalid scalars exercise the same fixed-G call sites.
    for op,expr,scalar in [(6,'tweakPublicKey',v.n-secret),(15,'tweakXOnlyPublicKey',v.n-normalized)]:
        source=key if op==6 else v.octets(point[0])
        text+=f'assert Curve.{expr}({v.blob(source)},{v.blob(v.octets(scalar))}) == #err(#pointAtInfinity);\n'
        native_case(op,source,v.octets(scalar),b'',-7)
    text+=f'assert Curve.tweakXOnlySecretKey({v.blob(v.octets(secret))},{v.blob(v.octets(v.n-normalized))}) == #err(#pointAtInfinity);\n'
    native_case(16,v.octets(secret),v.octets(v.n-normalized),b'',-7)
    for bad in [b'',b'\1',bytes(31),v.octets(v.n),bytes([255])*32,bytes(33)]:
        text+=f'assert Curve.baseMultiply({v.blob(bad)}) == #err(#invalidScalar);\n'
        text+=f'assert Curve.derivePublicKey({v.blob(bad)}) == #err(#invalidSecretKey);\n'
        native_case(5,bad,b'',b'',-3)
        native_case(0,bad,b'',b'',-1)
    (run/'round4-fixed-generator.mo').write_text(text)

    # Construct Q from a chosen verification point R: z=0,s=1,Q=r^-1 R.
    # This creates valid rare x=r+n cases and invalid field-wrap false positives.
    def lift(x):
        if not 0<=x<v.p: return None
        y=pow((x*x*x+7)%v.p,(v.p+1)//4,v.p)
        return (x,y) if (y*y-x*x*x-7)%v.p==0 else None
    delta=v.p-v.n
    cases=[]
    for start,direction,label in [(v.n+1,1,'rare-low'),(v.p-1,-1,'rare-upper'),(delta-1,-1,'ordinary-threshold-low'),(delta,1,'ordinary-threshold-high')]:
        x=start
        for _ in range(6):
            while lift(x) is None: x+=direction
            cases.append((lift(x),x%v.n,True,label))
            x+=direction
    x=1
    for _ in range(12):
        while lift(x) is None: x+=1
        cases.append((lift(x),delta+x,False,'forbidden-field-wrap'))
        x+=1
    text=v.audit.flags('secp256k1',plugin)+helpers
    for i,(point,r,valid,label) in enumerate(cases):
        assert 0<r<v.n and (point[0]%v.n==r)==valid
        keypoint=v.multiply_point(point,pow(r,-1,v.n))
        assert v.multiply_point(keypoint,r)==point
        key=v.encoded(keypoint)
        text+=f'// {label}, x={point[0]:064x}, r={r:064x}\n'
        text+=f'let k{i} = _ok(Curve.preparePublicKey({v.blob(key)}));\n'
        for s in [1,v.n-1]:
            signature=v.octets(r)+v.octets(s)
            expected='true' if valid else 'false'
            text+=f'assert Curve.verifyPrehash({v.blob(key)},{v.blob(bytes(32))},{v.blob(signature)}) == #ok({expected});\n'
            text+=f'assert Curve.verifyPrehashPrepared(k{i},{v.blob(bytes(32))},{v.blob(signature)}) == #ok({expected});\n'
            native_case(8,key,bytes(32),signature,int(valid))
    (run/'round4-inversionless-ecdsa.mo').write_text(text)
    (out/'round4-native.tsv').write_text('\n'.join(native)+'\n')
    square_values=[0,1,v.n-1]
    square_values += [(2**bit+delta)%v.n for bit in range(256) for delta in [-1,0,1]]
    square_values += [int.from_bytes(v.generated('round4-independent-square',i),'big')%v.n for i in range(512)]
    (out/'scalar-squares.tsv').write_text('\n'.join(v.octets(s).hex()+'\t'+v.octets(s*s%v.n).hex() for s in square_values)+'\n')
    inherited=json.loads((out/'generated.json').read_text())
    inherited['round4']={'fixed_scalar_cases':len(scalar_values),'constructed_verification_points':len(cases),'verification_checks':len(cases)*4,'native_cases':len(native),'native_vectors_sha256':hashlib.sha256((out/'round4-native.tsv').read_bytes()).hexdigest(),'independent_scalar_square_cases':len(square_values),'scalar_squares_sha256':hashlib.sha256((out/'scalar-squares.tsv').read_bytes()).hexdigest()}
    inherited['fixture_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(run.glob('*.mo'))}
    (out/'generated.json').write_text(json.dumps(inherited,indent=2)+'\n')
    print(json.dumps(inherited['round4']))
if __name__=='__main__': main()
