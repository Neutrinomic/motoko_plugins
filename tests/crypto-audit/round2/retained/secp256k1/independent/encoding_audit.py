#!/usr/bin/env python3
from pathlib import Path
import hashlib,importlib.util,json,os,subprocess
work=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('audit',work/'run_audit.py'); audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
stage=work.parent/'secp256k1-adapter'; curve=audit.CURVES['secp256k1']; n=curve['n']; p=curve['p']; be=audit.octets
rows=[]
for i in range(16):
 d=1+int.from_bytes(hashlib.sha256(b'independent secp round2 encoding'+be(i)).digest(),'big')%(n-1)
 for d in [d,n-d]:
  x,y=audit.multiply(curve,d); compressed=bytes([2+(y&1)])+be(x); uncompressed=b'\x04'+be(x)+be(y)
  for key in [compressed,uncompressed]:rows.append(dict(key=key.hex(),compressed=compressed.hex(),uncompressed=uncompressed.hex(),x=be(x).hex()))
invalid=set()
for length in range(75):
 invalid.add(bytes(length)); invalid.add(bytes([255])*length)
for prefix in [0,1,4,5,6,7,255]:invalid.add(bytes([prefix])+be(curve['g'][0]))
for prefix in [0,1,2,3,5,6,7,255]:invalid.add(bytes([prefix])+be(curve['g'][0])+be(curve['g'][1]))
for x in [p,p+1,2**256-1]:
 for prefix in [2,3]:invalid.add(bytes([prefix])+be(x))
 invalid.add(b'\x04'+be(x)+be(curve['g'][1]))
for y in [p,p+1,2**256-1,0,1]:invalid.add(b'\x04'+be(curve['g'][0])+be(y))
assert pow(7,(p-1)//2,p)==p-1
invalid.add(b'\x02'+bytes(32));invalid.add(b'\x03'+bytes(32))
rows += [dict(key=key.hex(),compressed=None,uncompressed=None,x=None) for key in sorted(invalid)]
extra=work/'encoding'; (extra/'run').mkdir(parents=True,exist_ok=True)
(extra/'vectors.json').write_text(json.dumps(rows,indent=2)+'\n')
text=audit.flags('secp256k1',stage/'dist/secp256k1')
for row in rows:
 key=audit.blob(bytes.fromhex(row['key']))
 for method,expected in [('compressPublicKey',row['compressed']),('decompressPublicKey',row['uncompressed']),('xOnlyPublicKey',row['x'])]:
  result='#err(#invalidPublicKey)' if expected is None else '#ok('+audit.blob(bytes.fromhex(expected))+')'
  text+=f'assert Curve.{method}({key}) == {result};\n'
(extra/'run/audit-secp256k1-encoding.mo').write_text(text)
addition='\n#[path='+json.dumps(str(extra/'native.rs'))+'] mod independent_round2_encoding;\n'
lib=work/'native/lib.rs'
if addition not in lib.read_text():lib.write_text(lib.read_text()+addition)
(extra/'native.rs').write_text('''use super::secp;
#[test]
fn canonical_and_malformed_sec1_fast_paths() {
    let rows: serde_json::Value = serde_json::from_str(include_str!("vectors.json")).unwrap();
    for (index,row) in rows.as_array().unwrap().iter().enumerate() {
        let key=super::bytes(row["key"].as_str().unwrap());
        let saved=key.clone();
        for (op,field,capacity) in [(1,"compressed",33),(2,"uncompressed",65),(12,"x",32)] {
            let mut output=[0xa5;74];
            let result=unsafe { secp::secp256k1_call(op,key.as_ptr(),key.len(),key.as_ptr(),0,key.as_ptr(),0,output.as_mut_ptr().add(1)) };
            if let Some(value)=row[field].as_str() {
                let expected=super::bytes(value);
                assert_eq!(result,expected.len() as i64,"case {index} op {op}");
                assert_eq!(&output[1..1+expected.len()],expected,"case {index} op {op}");
            } else {
                assert_eq!(result,-2,"case {index} op {op}");
                assert!(output[1..1+capacity].iter().all(|&x|x==0));
            }
            assert_eq!(output[0],0xa5);
            assert!(output[1+capacity..].iter().all(|&x|x==0xa5),"overrun case {index} op {op}");
            assert_eq!(key,saved);
        }
    }
}
''')
env=os.environ.copy();env.update(AUDIT_SECP_VECTORS=str(audit.WK256),AUDIT_P256_VECTORS=str(audit.WP256))
commands=[['cargo','test','--offline','--manifest-path',str(work/'native/Cargo.toml'),'--lib','--target-dir',str(work/'native/target'),'independent_round2_encoding'],['test-runner','-b',str(extra/'run')]]
reports=[]
for i,cmd in enumerate(commands):
 logfile=extra/['native.log','motoko.log'][i]
 with logfile.open('w') as log:r=subprocess.run(cmd,env=env,cwd='/srv/shared/code/motoko_experiments/motoko_sha',stdout=log,stderr=subprocess.STDOUT)
 assert r.returncode==0,logfile.read_text()
 reports.append(dict(command=cmd,exit=r.returncode,log=logfile.name,sha256=audit.sha(logfile)))
engines={suffix:audit.sha(extra/'run/_out'/('audit-secp256k1-encoding.'+suffix)) for suffix in ['run','run-ir','run-low','wasm-run','valid']}
report=dict(passed=True,valid_encodings=64,invalid_encodings=len(invalid),native_calls=len(rows)*3,motoko_assertions=len(rows)*3,artifacts={p.name:audit.sha(p) for p in (stage/'dist/secp256k1').iterdir() if p.is_file()},vectors_sha256=audit.sha(extra/'vectors.json'),generated_fixture_sha256=audit.sha(extra/'run/audit-secp256k1-encoding.mo'),generated_native_sha256=audit.sha(extra/'native.rs'),engines=engines,runs=reports)
(extra/'evidence.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
