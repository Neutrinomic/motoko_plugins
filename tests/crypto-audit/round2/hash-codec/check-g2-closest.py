from pathlib import Path
import re,json,hashlib,argparse
parser=argparse.ArgumentParser(description='Check closest G2 benchmark inputs/output with independent Python affine arithmetic.')
parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[4])
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args();ROOT=args.root.resolve()
p=int('1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab',16)
def add(a,b):return((a[0]+b[0])%p,(a[1]+b[1])%p)
def neg(a):return((-a[0])%p,(-a[1])%p)
def sub(a,b):return add(a,neg(b))
def mul(a,b):return((a[0]*b[0]-a[1]*b[1])%p,(a[0]*b[1]+a[1]*b[0])%p)
def inv(a):d=pow((a[0]*a[0]+a[1]*a[1])%p,-1,p);return(a[0]*d%p,-a[1]*d%p)
def ecadd(a,b):
 if a is None:return b
 if b is None:return a
 x,y=a;u,v=b
 if x==u:
  if y==neg(v):return None
  m=mul(mul((3,0),mul(x,x)),inv(mul((2,0),y)))
 else:m=mul(sub(v,y),inv(sub(u,x)))
 z=sub(sub(mul(m,m),x),u);return(z,sub(mul(m,sub(x,z)),y))
def enc(point):
 if point is None:return b'\xc0'+bytes(95)
 x,y=point;sign=y[1]>p//2 or(y[1]==0 and y[0]>p//2);b=bytearray(x[1].to_bytes(48,'big')+x[0].to_bytes(48,'big'));b[0]|=0x80|(0x20 if sign else 0);return bytes(b)
def blob(s):return bytes(int(v,16)for v in re.findall(r'\\([0-9a-fA-F]{2})',s))
r=[]
for name in ['closest_bls12_381_validate_g2_mops','closest_bls12_381_g2_aggregate_n4_mops']:
 path=ROOT/'benchmarks/crypto/round2/api-curves/closest/cases'/name/'main.mo';s=path.read_text();raw=blob(re.search(r'transient let input : Blob = "([^\"]*)"',s).group(1));expected=blob(re.search(r'assert actual == "([^\"]*)"',s).group(1));assert len(raw)%256==0
 points=[]
 for offset in range(0,len(raw),256):
  fields=[]
  for i in range(4):
   field=raw[offset+i*64:offset+(i+1)*64];assert field[:16]==bytes(16);v=int.from_bytes(field,'big');assert v<p;fields.append(v)
  x=(fields[0],fields[1]);y=(fields[2],fields[3]);assert mul(y,y)==add(mul(mul(x,x),x),(4,4));points.append((x,y))
 result=None
 for point in points:result=ecadd(result,point)
 assert b'\0'+enc(result)==expected
 r.append({'fixture':str(path.relative_to(ROOT)),'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'point_count':len(points),'independent_affine_sum_compressed_hex':enc(result).hex()})
report={'status':'passed','findings':[],'checks':['AllEIP2537fields canonicalwith16zero-bytepadding','Allsourcepoints satisfyFp2curveequation y^2=x^3+(4,4)','IndependentPythonFp2affineaddition+IETFcompressionmatchsexactexpectedoutput'], 'rows':r}
out=args.out;out.parent.mkdir(parents=True,exist_ok=True);report['test_source_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest();out.write_text(json.dumps(report,indent=2)+'\n');print(out)
