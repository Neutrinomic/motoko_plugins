#!/usr/bin/env python3
"""Audit SHA256 fixed-length padding and pointer bounds against Python hashlib."""
from pathlib import Path
import argparse,hashlib,json,os,random,subprocess,time
here=Path(__file__).resolve().parent
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--candidate',type=Path,required=True)
ap.add_argument('--out',type=Path,required=True)
a=ap.parse_args();root=a.candidate.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=root/'plugins/sha256/runtime/src/lib.rs';(out/'candidate.rs').write_bytes(source.read_bytes());(out/'native.rs').write_bytes((here/'native.rs').read_bytes())
rng=random.Random(0x256CAFE);values=[]
for n in [0,1,31,32,33,34,55,56,63,64,65,127,128,129,1024]:values.extend([b'\0'*n,b'\xff'*n,rng.randbytes(n)])
for n in [32,33,64]:
 for i in range(n*8):v=bytearray(n);v[i//8]=1<<(i%8);values.append(bytes(v))
 for b in range(256):values.append(bytes([b])*n)
(out/'vectors.tsv').write_text(''.join(x.hex()+'\t'+hashlib.sha256(x).hexdigest()+'\n'for x in values))
r={'status':'running','candidate':str(root),'source_sha256':sha(source),'vector_count':len(values),'commands':[],'findings':[]}
def run(argv,log,env):
 start=time.monotonic()
 with(out/log).open('w')as f:v=subprocess.run([str(x)for x in argv],stdout=f,stderr=subprocess.STDOUT,env=env)
 r['commands'].append({'argv':[str(x)for x in argv],'exit_code':v.returncode,'seconds':round(time.monotonic()-start,3),'log':log})
 (out/'report.json').write_text(json.dumps(r,indent=2)+'\n')
 if v.returncode:raise SystemExit((out/log).read_text())
for mode,flags in [('debug',[]),('asan',['-O','-C','debug-assertions=yes','-Z','sanitizer=address'])]:
 env=dict(os.environ,RUSTC_BOOTSTRAP='1',ASAN_OPTIONS='detect_leaks=1:halt_on_error=1')
 run(['rustc','--test','--edition=2024',*flags,out/'native.rs','-o',out/f'native-{mode}'],f'compile-{mode}.log',env)
 run([out/f'native-{mode}'],f'{mode}.log',env)
 assert '5 passed; 0 failed'in(out/f'{mode}.log').read_text()
assert sha(source)==r['source_sha256']==sha(out/'candidate.rs')
meta=root/'dist/sha256/build.json'
if meta.exists():
 j=json.loads(meta.read_text());assert j['source_sha256']['plugins/sha256/runtime/src/lib.rs']==r['source_sha256'];r['build_metadata_sha256']=sha(meta);r['artifact_sha256']=j['sha256']
 for f,h in j['sha256'].items():assert sha(meta.parent/f)==h
r.update(status='passed',vector_sha256=sha(out/'vectors.tsv'),rustc=subprocess.check_output(['rustc','--version'],text=True).strip(),test_source_sha256={p.name:sha(p)for p in [here/'run.py',here/'native.rs']},review=['Shared specialized path called only for lengths32/33, copy32bytes and readbyte32onlywhenlength33.','Tail big-endian bit counts256/264 correct; padding byte128 at32/33. Merkle64case secondblockbitcount512 unchanged.','All single-bit inputs and all repeatedbytevalues at32/33/64;16alignment offsets, immutable inputs,outputcanaries,read-onlyinputpages and inaccessibleendpages.','Debug and optimizedASan5tests pass; original3runtime tests included.'])
(out/'report.json').write_text(json.dumps(r,indent=2)+'\n');print(out/'report.json')
