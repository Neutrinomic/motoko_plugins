#!/usr/bin/env python3
"""Recreate HMAC round-two cases using Python/OpenSSL independent oracles."""
from pathlib import Path
import sys,json,hmac
base=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(base))
from common import actor,blob
out=base/'round2/hmac-workloads';cases=[]
def add(mode,n,k,operation,chunk=0):
 data=bytes(i%251 for i in range(n));key=bytes(i%251 for i in range(k));suffix='Sha256' if mode=='sha256' else 'Sha512'
 name=f'hmac-{mode}-{operation}-k{k}-n{n}'+(f'-c{chunk}' if chunk else '')
 decls=f'transient let key : Blob = {blob(key)};\ntransient let input : Blob = {blob(data)};'
 setup=''
 if operation=='oneshot':op=f'result := H.{mode}(key,input);'
 elif operation=='prepared':
  decls+=f'\ntransient var prepared = H.prepare{suffix}(key);'
  setup=f'prepared := H.prepare{suffix}(key);'
  op='result := prepared.digest(input);'
 else:
  chunks=[data[i:i+chunk] for i in range(0,n,chunk)]
  decls+=f'\ntransient let chunks : [Blob] = [{",".join(blob(c) for c in chunks)}];\ntransient var stream = H.{mode.upper()}(key);'
  setup=f'stream := H.{mode.upper()}(key);'
  op='for (piece in chunks.values()) { stream.write(piece) }; result := stream.sum();'
 path=out/name/'main.mo';path.parent.mkdir(exist_ok=True);path.write_text(actor('import H "mo:fast/HMAC";',decls,setup,op,'result','Blob','""'))
 cases.append(dict(name=name,family='hmac-sha2',implementation='native',comparison='round2-'+operation,plugins=['hmac-sha2'],source=str(path.relative_to(base)),expected_hex=hmac.digest(key,data,mode).hex(),notes='Independent Python/OpenSSL hmac oracle; key and message/chunks prebuilt outside counters. Prepared/stream key setup excluded.'))
for mode in ['sha256','sha512']:
 for n in [0,32,64,1024,16384]:add(mode,n,32,'oneshot')
 for k,n in [(0,0),(65,64),(129,64),(131,1024),(1024,1024)]:add(mode,n,k,'oneshot')
 for n in [64,1024,16384]:add(mode,n,32,'prepared')
 for chunk in [1,63,128]:add(mode,1024,32,'stream',chunk)
(out/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(len(cases),out/'cases.json')
