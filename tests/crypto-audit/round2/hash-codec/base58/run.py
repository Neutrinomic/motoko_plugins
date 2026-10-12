#!/usr/bin/env python3
"""Independent bounded Base58 raw ABI audit; needs Python and rustc, no Cargo changes."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,time
here=Path(__file__).resolve().parent
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--candidate',type=Path,required=True,help='Plugin repository root containing plugins/base58')
ap.add_argument('--out',type=Path,required=True)
a=ap.parse_args();root=a.candidate.resolve();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=root/'plugins/base58/runtime/src/lib.rs'
r={'status':'running','candidate':str(root),'source_sha256':sha(source),'commands':[],'findings':[]}
def run(argv,log,env=None):
 start=time.monotonic()
 with (out/log).open('w')as f:v=subprocess.run([str(x)for x in argv],stdout=f,stderr=subprocess.STDOUT,env=env)
 r['commands'].append({'argv':[str(x)for x in argv],'exit_code':v.returncode,'seconds':round(time.monotonic()-start,3),'log':log})
 (out/'report.json').write_text(json.dumps(r,indent=2)+'\n')
 if v.returncode:raise SystemExit((out/log).read_text())
run(['python3',here/'generate.py','--source',source,'--out',out],'generate.log')
for mode,flags in [('debug',[]),('asan',['-O','-C','debug-assertions=yes','-Z','sanitizer=address'])]:
 env=dict(os.environ,RUSTC_BOOTSTRAP='1',ASAN_OPTIONS='detect_leaks=1:halt_on_error=1')
 run(['rustc','--test','--edition=2024',*flags,out/'native.rs','-o',out/f'native-{mode}'],f'compile-{mode}.log',env)
 run([out/f'native-{mode}'],f'{mode}.log',env)
 assert '8 passed; 0 failed' in (out/f'{mode}.log').read_text()
assert sha(source)==r['source_sha256']==sha(out/'candidate.rs')
meta=root/'dist/base58/build.json'
if meta.exists():
 j=json.loads(meta.read_text());assert j['source_sha256']['plugins/base58/runtime/src/lib.rs']==r['source_sha256']
 r['build_metadata_sha256']=sha(meta);r['artifact_sha256']=j['sha256']
 for f,h in j['sha256'].items():assert sha(meta.parent/f)==h
r.update(status='passed',vector_count=1657,vector_sha256=sha(out/'vectors.tsv'),rustc=subprocess.check_output(['rustc','--version'],text=True).strip(),test_source_sha256={p.name:sha(p)for p in [here/'run.py',here/'generate.py',here/'native.rs']},coverage=['Independent Python bigint Base58 oracle: 1657 deterministic vectors covering leading zeros, 4-byte/5-digit limbs, scalar boundaries and maximum input size.','All 16 alignment offsets; exact and insufficient capacities; input immutability and output canaries.','Every invalid byte at six offsets, competing capacity/maximum-size errors, and oversized alphabet-valid values.','Read-only input pages and inaccessible pages immediately after inputs/outputs.','Debug execution and optimized AddressSanitizer execution, including original five runtime tests.'])
(out/'report.json').write_text(json.dumps(r,indent=2)+'\n')
print(out/'report.json')
