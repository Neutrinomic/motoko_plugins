from pathlib import Path
import random,json,hashlib,argparse,shutil
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args()
p=args.out.resolve();p.mkdir(parents=True,exist_ok=True)
source=args.source.resolve(); (p/'candidate.rs').write_bytes(source.read_bytes())
driver=Path(__file__).resolve().parent/'native.rs'
if driver != p/'native.rs':shutil.copyfile(driver,p/'native.rs')
r=random.Random(0x58CAFE)
a=b'123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
def enc(b):
 z=len(b)-len(b.lstrip(b'\0')); n=int.from_bytes(b,'big'); out=bytearray()
 while n:n,x=divmod(n,58);out.append(a[x])
 return b'1'*z+out[::-1]
values=[]
for n in list(range(0,80))+[81,82,127,128,129,255,256,257,511,512,513,1023,1024,1025,2047,2048,2049,4095,4096]:
 for v in [b'\xff'*n,b'\0'*n,r.randbytes(n),b'\0'*(n//2)+r.randbytes(n-n//2)]:values.append(v)
for _ in range(1000):values.append(b'\0'*r.randrange(20)+r.randbytes(r.randrange(200)))
# Radix/limb and scalar fast path transitions tested against independent Python bigint.
for k in range(1,55):
 for radix in [58,256]:
  for d in [-1,0,1]:
   n=radix**k+d
   if n>=0:values.append(n.to_bytes(max(1,(n.bit_length()+7)//8),'big'))
values=list(dict.fromkeys(values))
(p/'vectors.tsv').write_text(''.join(b.hex()+'\t'+enc(b).hex()+'\n' for b in values))
print(json.dumps({'count':len(values),'sha256':hashlib.sha256((p/'vectors.tsv').read_bytes()).hexdigest()}))
