#!/usr/bin/env python3
"""Independent prepared-RSA audit. All keys here are PUBLIC TEST KEYS.

Old vectors are read-only. New logs, generated drivers and binaries stay in _out.
--generate is lightweight; execute --native/--motoko only with a scheduled slot.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import random
import re
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OLD = ROOT / 'tests/crypto-audit/round3/rsa'
OUT = HERE / '_out'
RUNTIME = ROOT / 'plugins/rsa/runtime'
spec = importlib.util.spec_from_file_location('old_oracle', OLD / 'audit.py')
oracle = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True
spec.loader.exec_module(oracle)
ERRORS = {-1:'invalidSecretKey', -2:'invalidPublicKey', -3:'invalidDigest', -4:'invalidSalt', -5:'invalidSignature'}


def run(command, name):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (OUT / (name + '.log')).write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError(f'{name} exited {result.returncode}: {result.stdout.decode(errors="replace")[-8000:]}')
    return result.stdout


def i31(value, bits):
    limbs = (bits + 30) // 31
    return struct.pack('<' + 'I'*(limbs+2), (bits//31)*32 + bits%31,
                       *[(value >> (31*i)) & 0x7fffffff for i in range(limbs)], 0)


def public_layout(raw):
    if len(raw)!=384 or not raw[0]&128 or not raw[-1]&1:
        return b''
    n = int.from_bytes(raw, 'big')
    return i31(n,3072) + i31(pow(2,6200,n),3072) + struct.pack('<II',(-pow(n,-1,1<<31))&0x7fffffff,0)


def private_layout(raw):
    if len(raw)!=960:
        return b''
    p,q,dp,dq,iq = [int.from_bytes(raw[i:i+192],'big') for i in range(0,960,192)]
    if (p.bit_length()!=1536 or q.bit_length()!=1536 or not(p&q&1) or p==q
            or (p*q).bit_length()!=3072 or not 0<dp<p-1 or not 0<dq<q-1 or not 0<iq<p
            or dp*65537%(p-1)!=1 or dq*65537%(q-1)!=1 or iq*q%p!=1):
        return b''
    return (public_layout((p*q).to_bytes(384,'big')) + i31(p,1536) + i31(q,1536)
            + i31(iq*pow(2,1550,p)%p,1536) + raw[384:768]
            + struct.pack('<II',(-pow(p,-1,1<<31))&0x7fffffff,(-pow(q,-1,1<<31))&0x7fffffff))


def all_keys():
    numbers = oracle.key_numbers((OLD/'vectors/PUBLIC-TEST-ONLY-private.der').read_bytes())
    first = b''.join(oracle.fixed(x) for x in numbers[3:])
    fixture = json.loads((ROOT/'plugins/rsa/vectors/openssl3072.json').read_text())
    second = bytes.fromhex(fixture['privateKey'])
    result=[]
    for raw in [first,second]:
        p,q,dp,dq,iq = [int.from_bytes(raw[i:i+192],'big') for i in range(0,960,192)]
        assert iq*q%p==1 and dp*65537%(p-1)==1 and dq*65537%(q-1)==1
        result += [raw,b''.join(oracle.fixed(x) for x in [q,p,dq,dp,pow(p,-1,q)])]
    assert first!=second
    return result


def expected_mo(value):
    if isinstance(value,str): return '#ok('+oracle.blob(value)+')'
    if value<0: return '#err(#'+ERRORS[value]+')'
    return '#ok('+('true' if value else 'false')+')'


def generate():
    OUT.mkdir(parents=True,exist_ok=True)
    cases = json.loads((OLD/'vectors/cases.json').read_text())
    # CRT consistency deliberately does not prove primality. This shaped key
    # has qInv=3 (191 leading zero bytes), exercising normalization to p's
    # fixed i31 header and the mandatory post-sign fault check.
    cp=2**1536-3; cq=(2*cp+1)//3
    cdp=pow(65537,-1,cp-1); cdq=pow(65537,-1,cq-1)
    assert cq*3%cp==1
    short_inverse=b''.join(oracle.fixed(x) for x in [cp,cq,cdp,cdq,3])
    encoded=int.from_bytes(oracle.pss(hashlib.sha256(b'short inverse fault').digest(),bytes(32)),'big')
    m1=pow(encoded,cdp,cp); m2=pow(encoded,cdq,cq)
    assert pow(m2+cq*((m1-m2)*3%cp),65537,cp*cq)!=encoded
    oracle.add(cases,'prepared-short-qInv-layout','validatePrivateKey',[short_inverse],1)
    oracle.add(cases,'prepared-short-qInv-fault','sign',[short_inverse,b'short inverse fault',bytes(32)],-1)
    records = bytearray(struct.pack('<I',len(cases)))
    mo=['import RSA "mo:fast/RSA";', 'import Prim "mo:⛔";',
        'func unwrap<T>(r : RSA.Result<T>) : T { switch r { case (#ok x) x; case (#err _) Prim.trap("prepare failed") } };']
    opcodes=['validatePrivateKey','validatePublicKey','publicKey','sign','verify']
    for case in cases:
        op=case['op']; args=[bytes.fromhex(a) for a in case['args']]; expected=case['expected']
        output=bytes.fromhex(expected) if isinstance(expected,str) else b''
        status=384 if output else expected
        padded=args+[b'']*(3-len(args))
        layout=(public_layout if op in ['validatePublicKey','verify'] else private_layout)(args[0])
        records += struct.pack('<IIiIIIII',opcodes.index(op),case['prehash'],status,*map(len,padded),len(output),len(layout))
        records += b''.join(padded)+output+layout
        name=op+('Prehash' if case['prehash'] else '')
        mo += ['// '+case['name'],f'assert RSA.{name}({", ".join(map(oracle.blob,case["args"]))}) == {expected_mo(expected)};']
        factory='preparePublicKey' if op in ['validatePublicKey','verify'] else 'prepareSecretKey'
        if op in ['sign','verify']:
            hot=op+('Prehash' if case['prehash'] else '')+'Prepared'
            tail=', '.join(map(oracle.blob,case['args'][1:]))
            mo += [f'assert (switch (RSA.{factory}({oracle.blob(case["args"][0])})) {{ case (#err error) #err(error); case (#ok key) RSA.{hot}(key, {tail}) }}) == {expected_mo(expected)};']
        else:
            expected_factory=expected_mo(-2 if op=='validatePublicKey' else -1) if not layout else '#ok(true)'
            mo += [f'assert (switch (RSA.{factory}({oracle.blob(case["args"][0])})) {{ case (#err error) #err(error); case (#ok _) #ok(true) }}) == {expected_factory};']
    (OUT/'vectors.bin').write_bytes(records)
    keys=all_keys()
    for i,raw in enumerate(keys):
        p,q=[int.from_bytes(raw[j:j+192],'big') for j in [0,192]]
        pk=(p*q).to_bytes(384,'big')
        mo += [f'let secret{i} = unwrap(RSA.prepareSecretKey({oracle.blob(raw.hex())}));',
               f'let public{i} = unwrap(RSA.preparePublicKey({oracle.blob(pk.hex())}));']
    for turn in range(3):
        for key in [0,2,1,3]:
            raw=keys[key]; p,q=[int.from_bytes(raw[j:j+192],'big') for j in [0,192]]
            d=pow(65537,-1,math.lcm(p-1,q-1)); n=p*q
            message=f'interleaving {turn}'.encode(); salt=bytes([turn+key])*32
            digest=hashlib.sha256(message).digest(); encoded=oracle.pss(digest,salt)
            signature=pow(int.from_bytes(encoded,'big'),d,n).to_bytes(384,'big')
            mo += [f'assert RSA.signPrepared(secret{key}, {oracle.blob(message.hex())}, {oracle.blob(salt.hex())}) == #ok({oracle.blob(signature.hex())});',
                   f'assert RSA.verifyPrehashPrepared(public{key}, {oracle.blob(digest.hex())}, {oracle.blob(signature.hex())}) == #ok(true);']
            other=(key+2)%4; otherraw=keys[other]
            othern=int.from_bytes(otherraw[:192],'big')*int.from_bytes(otherraw[192:384],'big')
            wrong=-5 if int.from_bytes(signature,'big')>=othern else 0
            mo += [f'assert RSA.verifyPrepared(public{other}, {oracle.blob(message.hex())}, {oracle.blob(signature.hex())}) == {expected_mo(wrong)};']
    (OUT/'audit.mo').write_text('\n'.join(mo)+'\n')
    rng=random.Random(0x65537)
    moduli=[2**3071+1,2**3071+3,2**3071+65537,2**3072-1,2**3072-3,2**3072-65537]
    moduli += [rng.getrandbits(3072)|2**3071|1 for _ in range(96)]
    public=bytearray(); public_count=0
    for n in moduli:
        for x in [0,1,2,n-1,n,n+1,2**3072-1]+[rng.randrange(n) for _ in range(5)]:
            if x>=2**3072: continue
            valid=x<n; y=pow(x,65537,n) if valid else 0
            public += (n.to_bytes(384,'big')+x.to_bytes(384,'big')+y.to_bytes(384,'big')+bytes([valid])
                       +public_layout(n.to_bytes(384,'big')))
            public_count+=1
    (OUT/'public.bin').write_bytes(struct.pack('<I',public_count)+public)
    private_cases=[]
    for key,raw in enumerate(keys):
        p,q=[int.from_bytes(raw[j:j+192],'big') for j in [0,192]]
        n=p*q; d=pow(65537,-1,math.lcm(p-1,q-1))
        inputs=[0,1,2,p,q,n-1,n,n+1,2**3072-1]+[rng.randrange(n) for _ in range(8)]
        for x in inputs:
            private_cases.append((key,int(x<n),x.to_bytes(384,'big'),pow(x,d,n).to_bytes(384,'big')))
    # Deliberately interleave genuine distinct keys and reversed factor order.
    rng.shuffle(private_cases)
    private=bytearray(struct.pack('<I',len(private_cases))+b''.join(key+private_layout(key) for key in keys))
    for key,valid,x,y in private_cases: private+=struct.pack('<II',key,valid)+x+y
    (OUT/'private.bin').write_bytes(private)
    old_source=(HERE/'baseline/rsa_i31_priv.c').read_bytes()
    provenance=json.loads((HERE/'baseline/provenance.json').read_text())
    assert hashlib.sha256(old_source).hexdigest()==provenance['sha256']
    assert b'#define TLEN   (8 * U)' in old_source
    (OUT/'original8u.c').write_bytes(old_source.replace(b'br_rsa_i31_private(',b'audit_original_private('))
    summary=dict(vectors=len(cases),wycheproof=108,public_math_cases=public_count,public_moduli=len(moduli),
                 private_math_cases=len(private_cases),genuine_private_keys=2,factor_order_contexts=4,
                 native_fault_injections=20,motoko_interleavings=12,seed=0x65537,
                 original8u_sha256=hashlib.sha256(old_source).hexdigest(),
                 vector_hash=hashlib.sha256((OLD/'vectors/cases.json').read_bytes()).hexdigest())
    (OUT/'fixtures.json').write_text(json.dumps(summary,indent=2)+'\n')
    return summary


def source_hashes():
    sources=[p for p in (ROOT/'plugins/rsa').rglob('*') if p.is_file() and not any(x in p.parts for x in ['target','_out'])]
    sources += [ROOT/'packages/fast/src/RSA.mo']
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generate',action='store_true')
    parser.add_argument('--native',action='store_true')
    parser.add_argument('--motoko',action='store_true')
    parser.add_argument('--imports',action='store_true')
    parser.add_argument('--cc',default='cc')
    parser.add_argument('--moc',default='/srv/shared/code/motoko_experiments/prepared-crypto/sdk/bin/moc')
    parser.add_argument('--plugin',type=Path,default=ROOT/'dist/rsa')
    parser.add_argument('--wasmtime',default='wasmtime')
    parser.add_argument('--openssl',default='openssl')
    args=parser.parse_args()
    summary=generate()
    if not any([args.native,args.motoko,args.imports]):
        print(json.dumps(summary)); return
    before=source_hashes()
    report=dict(fixtures=summary,source_hashes=before,
                baseline_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip(),
                audit_sources={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE/'audit.py',HERE/'driver.c']})
    direct_source=(RUNTIME/'vendor/bearssl/src/rsa/rsa_i31_priv.c').read_text()
    prepared_source=(RUNTIME/'src/rsa.c').read_text()
    report['direct_workspace_slots']=int(re.search(r'#define TLEN\s+\((\d+) \* U\)',direct_source)[1])
    report['prepared_exponentiation_workspace_words']=52*int(re.search(r'tmp\[(\d+) \* WORDS\]',prepared_source)[1])
    if args.native:
        sources=sorted((RUNTIME/'vendor/bearssl/src').rglob('*.c'))
        command=[args.cc,'-std=c11','-O1','-g','-fno-strict-aliasing','-fno-omit-frame-pointer','-fsanitize=address,undefined',
                 '-fno-sanitize-recover=all','-DBR_MAX_RSA_SIZE=3072','-DBR_MAX_RSA_FACTOR=1536',
                 '-I'+str(RUNTIME/'src'),'-I'+str(RUNTIME/'vendor/bearssl/inc'),'-I'+str(RUNTIME/'vendor/bearssl/src'),
                 HERE/'driver.c',OUT/'original8u.c',*sources,'-o',OUT/'driver']
        run(command,'native-build')
        for name in ['vectors','public','private']:
            print(run([OUT/'driver',name,OUT/(name+'.bin')],'native-'+name).decode(),end='')
        report['native_asan_ubsan']='pass'
        report['native_binary_sha256']=hashlib.sha256((OUT/'driver').read_bytes()).hexdigest()
        report['native_compiler_version']=run([args.cc,'--version'],'cc-version').decode().splitlines()[0]
        (OUT/'native-report.json').write_text(json.dumps(report,indent=2)+'\n')
    if args.motoko:
        compiler_binary=Path(args.moc).parent.parent/'src/moc'
        compiler_hashes={str(Path(args.moc)):hashlib.sha256(Path(args.moc).read_bytes()).hexdigest()}
        if compiler_binary.is_file():
            compiler_hashes[str(compiler_binary.resolve())]=hashlib.sha256(compiler_binary.read_bytes()).hexdigest()
        common=[args.moc,'--package','fast',ROOT/'packages/fast/src','--plugin',args.plugin]
        run(common+['-r',OUT/'audit.mo'],'interpreter')
        run(common+['-wasi-system-api','--sanity-checks','-o',OUT/'audit.wasm',OUT/'audit.mo'],'compile')
        run([args.wasmtime,'-W','memory64=y',OUT/'audit.wasm'],'wasm')
        report.update(interpreter='pass',wasm_sanity='pass',
                      wasm_sha256=hashlib.sha256((OUT/'audit.wasm').read_bytes()).hexdigest(),
                      plugin_artifacts={name:hashlib.sha256((args.plugin/name).read_bytes()).hexdigest() for name in ['runtime.wasm','plugin.cmxs']},
                      compiler_sha256=compiler_hashes,
                      compiler_version=run([args.moc,'--version'],'compiler-version').decode().strip())
        assert all(hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest for path,digest in compiler_hashes.items()),'compiler changed during audit'
        print('Portable OCaml and compiled Wasm prepared/direct vectors and interleaving pass')
    if args.imports:
        report['openssl_version']=run([args.openssl,'version'],'openssl-version').decode().strip()
        # Recheck ordinary forms as well as restriction preservation, without
        # invoking the old preparation script or overwriting its evidence.
        ordinary=OUT/'ordinary-imports'; ordinary.mkdir(exist_ok=True)
        pem=OLD/'vectors/PUBLIC-TEST-ONLY-private.pem'
        der=OLD/'vectors/PUBLIC-TEST-ONLY-private.der'
        pubpem=OLD/'vectors/public.pem'
        pkcs8der=ordinary/'pkcs8.der'; pkcs1pem=ordinary/'pkcs1.pem'
        spkider=ordinary/'spki.der'; pkcs1pub=ordinary/'pkcs1-public.der'
        run([args.openssl,'pkcs8','-topk8','-nocrypt','-in',pem,'-outform','DER','-out',pkcs8der],'openssl-pkcs8')
        run([args.openssl,'rsa','-in',pem,'-traditional','-out',pkcs1pem],'openssl-pkcs1-pem')
        run([args.openssl,'pkey','-in',pem,'-pubout','-outform','DER','-out',spkider],'openssl-spki-der')
        run([args.openssl,'rsa','-in',pem,'-RSAPublicKey_out','-outform','DER','-out',pkcs1pub],'openssl-pkcs1-public')
        n,_,_,p,q,dp,dq,qi=oracle.key_numbers(der.read_bytes())
        expected_public=n.to_bytes(384,'big')
        expected_secret=b''.join(oracle.fixed(x) for x in [p,q,dp,dq,qi])
        conversions=[('pkcs8-pem',pem,True),('pkcs1-der',der,True),('spki-pem',pubpem,False),
                     ('pkcs8-der',pkcs8der,True),('pkcs1-pem',pkcs1pem,True),
                     ('spki-der',spkider,False),('pkcs1-public-der',pkcs1pub,False)]
        for label,source,private in conversions:
            publicout=ordinary/(label+'.public'); secretout=ordinary/(label+'.secret')
            publicout.unlink(missing_ok=True); secretout.unlink(missing_ok=True)
            command=['python3',ROOT/'plugins/rsa/tools/import_key.py','--openssl',args.openssl,
                     '--private-key' if private else '--public-key',source,'--public-out',publicout]
            if private: command+=['--private-out',secretout]
            run(command,'import-'+label)
            assert publicout.read_bytes()==expected_public
            if private:
                assert secretout.read_bytes()==expected_secret
                assert secretout.stat().st_mode & 0o777 == 0o600
        report['ordinary_import_formats']=[label for label,_,_ in conversions]
        restricted=sorted((OLD/'vectors/restricted').glob('*'))
        tested=[]
        for source in restricted:
            if source.suffix not in ['.pem','.der']: continue
            private='private' in source.name
            publicout=OUT/(source.name+'.public-out'); secretout=OUT/(source.name+'.secret-out')
            publicout.unlink(missing_ok=True); secretout.unlink(missing_ok=True)
            command=['python3',ROOT/'plugins/rsa/tools/import_key.py','--openssl',args.openssl,
                     '--private-key' if private else '--public-key',source,'--public-out',publicout]
            if private: command+=['--private-out',secretout]
            result=subprocess.run(list(map(str,command)),stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            assert result.returncode and not publicout.exists() and not secretout.exists(),source
            tested.append(dict(source=str(source.relative_to(ROOT)),status=result.returncode,diagnostic=result.stdout.decode()))
        assert len(tested)==16
        (OUT/'restricted-imports.json').write_text(json.dumps(tested,indent=2)+'\n')
        report['restricted_imports_rejected']=len(tested)
        print('All 16 RSA-PSS restricted imports rejected without output files')
    assert before==source_hashes(),'implementation changed during audit; repeat after source freeze'
    (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__': main()
