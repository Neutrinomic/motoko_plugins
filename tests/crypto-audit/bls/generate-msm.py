#!/usr/bin/env python3
"""Independent Pippenger boundary fixtures; py_ecc 8.0.0 is the only oracle."""
from pathlib import Path
from hashlib import sha512
import json
from py_ecc.bls.point_compression import compress_G1, compress_G2
from py_ecc.optimized_bls12_381 import G1,G2,multiply,curve_order
HERE=Path(__file__).resolve().parent
R=curve_order
rows=[]
def scalar(n):return n.to_bytes(32,'big')
def point(p,g):
 c=compress_G1(p) if g==1 else compress_G2(p)
 return c.to_bytes(48,'big') if g==1 else b''.join(v.to_bytes(48,'big') for v in c)
def random(i,label):return int.from_bytes(sha512(label+i.to_bytes(4,'big')).digest(),'big')%R
def emit(name,g,points,scalars,expected=b'',status=0):
 rows.append(dict(name=name,op=6+g,a=points.hex(),b=scalars.hex(),c='',status=status,expected=expected.hex()))
for g,base in [(1,G1),(2,G2)]:
 # Consecutive inputs combine identity, repeated, inverse and independently
 # derived distinct points. The expected result follows scalar linearity,
 # with a single independent scalar multiplication, not plugin bucket logic.
 factors=[0,1,R-1,1]+[random(i,b'point') if i%2==0 else (-random(i-1,b'point'))%R for i in range(4,128)]
 points=[point(multiply(base,n),g) for n in factors]
 edges=[0,1,R-1,1<<254,(1<<254)+1]
 scalars=[edges[i] if i<len(edges) else random(i,b'scalar') for i in range(128)]
 for n in [3,4,5,15,16,17,63,64,65,127,128]:
  expected=sum(x*y for x,y in zip(factors[:n],scalars[:n]))%R
  emit(f'msm-window-g{g}-n{n}',g,b''.join(points[:n]),b''.join(map(scalar,scalars[:n])),point(multiply(base,expected),g))
 # A point and its inverse with equal high scalars must cancel exactly.
 for n in [4,17,65,128]:
  fs=([1,R-1]*(n//2))+([0] if n%2 else [])
  ss=[R-1]*n
  emit(f'msm-cancel-g{g}-n{n}',g,b''.join(point(multiply(base,x),g) for x in fs),b''.join(map(scalar,ss)),point(multiply(base,0),g))
 for n in [4,128]:
  ps=points[:n].copy();ss=list(map(scalar,scalars[:n]));ps[0]=b'\0'*(48*g);ss[0]=scalar(R)
  emit(f'msm-first-point-before-scalar-g{g}-n{n}',g,b''.join(ps),b''.join(ss),status=2)
  ps=points[:n].copy();ss=list(map(scalar,scalars[:n]));ps[-1]=b'\0'*(48*g);ss[0]=scalar(R)
  emit(f'msm-first-scalar-before-later-point-g{g}-n{n}',g,b''.join(ps),b''.join(ss),status=3)
  ps=points[:n].copy();ss=list(map(scalar,scalars[:n]));ps[-1]=b'\0'*(48*g)
  emit(f'msm-last-point-g{g}-n{n}',g,b''.join(ps),b''.join(ss),status=2)
  ps=points[:n].copy();ss=list(map(scalar,scalars[:n]));ss[-1]=scalar(R)
  emit(f'msm-last-scalar-g{g}-n{n}',g,b''.join(ps),b''.join(ss),status=3)
(HERE/'msm-vectors.tsv').write_text('\n'.join('\t'.join(str(v[k]) for k in ['name','op','a','b','c','status','expected']) for v in rows)+'\n')
def mo(h):return '"'+''.join('\\'+h[i:i+2] for i in range(0,len(h),2))+'"'
lines=['import B "mo:fast/BLS12381";','import P "mo:⛔";']
errors={2:'invalidPoint',3:'invalidScalar'}
for v in rows:
 expected='#err(#'+errors[v['status']]+')' if v['status'] else '#ok('+mo(v['expected'])+')'
 lines.extend(['// '+v['name'],f'assert B.g{v["op"]-6}Msm({mo(v["a"])},{mo(v["b"])}) == {expected};'])
lines.append('P.debugPrint("independent BLS MSM boundary audit passed");')
(HERE/'msm.mo').write_text('\n'.join(lines)+'\n')
(HERE/'msm-provenance.json').write_text(json.dumps(dict(oracle='Ethereum py_ecc 8.0.0',cases=len(rows),threshold_counts=[3,4,5,15,16,17,63,64,65,127,128],point_distribution='identity, repeated generator, inverses, SHA512-derived distinct subgroup points',scalar_distribution='0,1,r-1,2^254,2^254+1,SHA512-derived full-width canonical scalars'),indent=2)+'\n')
print(len(rows),'MSM boundary fixtures',flush=True)
