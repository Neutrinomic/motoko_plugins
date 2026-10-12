import json,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[4]; dest=root/'benchmarks/crypto/round2/bitcoin-extra'; dest.mkdir(exist_ok=True)
def lit(data):return '"'+''.join('\\%02x'%x for x in data)+'"'
def compact(n):return bytes([n]) if n<253 else b'\xfd'+n.to_bytes(2,'little') if n<65536 else b'\xfe'+n.to_bytes(4,'little')
def tagged(tag,data):h=hashlib.sha256(tag).digest();return hashlib.sha256(h+h+data).digest()
cases=[]
def actor(name,setup,code,expected,public,size):
 s='''import Prim "mo:⛔";\nimport T "mo:fast/Bitcoin/Transaction";\nimport S "mo:fast/Bitcoin/Script";\npersistent actor {\n  transient var result : Blob = "";\n'''+setup+'''\n  public func configure() : async () {};\n  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {\n    let a=Prim.rts_total_allocation(); let r=Prim.rts_reclaimed(); let start=Prim.performanceCounter(0);\n'''+code+'''\n    let stop=Prim.performanceCounter(0);let z=Prim.rts_total_allocation();let q=Prim.rts_reclaimed();\n    {instructions=stop-start;allocated=z-a;reclaimed=q-r;outputSize=0}\n  };\n  public query func bytesResult() : async Blob { result };\n}\n'''
 p=dest/name/'main.mo';p.parent.mkdir(exist_ok=True);p.write_text(s)
 cases.append(dict(name=name,family='bitcoin',implementation='native',plugins=['sha256'],source=str(p.relative_to(root/'benchmarks/crypto')),expected_hex=expected.hex(),public_function=public,size=size,notes='Independent hashlib/BIP wire oracle; setup and result serialization outside measured interval.'))
for n in [0,1,25,75,76,252,253,520,65536]:
 data=bytes((i*13+7)%256 for i in range(n)); prefix=bytes([n]) if n<76 else b'\x4c'+bytes([n]) if n<256 else b'\x4d'+n.to_bytes(2,'little') if n<65536 else b'\x4e'+n.to_bytes(4,'little'); exp=prefix+data
 if n==1:exp=b'\x57'
 actor('bitcoin-script-push-'+str(n),'  transient let input : Blob = '+lit(data)+';','    let ?value=S.pushData(input) else Prim.trap("push"); result:=value;',exp,'Script.pushData',n)
for n in [0,25,253,520]:
 data=bytes((i*17+3)%256 for i in range(n));actor('bitcoin-script-tapleaf-'+str(n),'  transient let input : Blob = '+lit(data)+';','    let ?value=S.tapLeafHash(input,0xc0) else Prim.trap("tapleaf"); result:=value;',tagged(b'TapLeaf',b'\xc0'+compact(n)+data),'Script.tapLeafHash',n)
a=hashlib.sha256(b'left').digest();b=hashlib.sha256(b'right').digest();actor('bitcoin-script-tapbranch-32','  transient let left : Blob = '+lit(a)+';\n transient let right : Blob = '+lit(b)+';','    let ?value=S.tapBranchHash(left,right) else Prim.trap("tapbranch"); result:=value;',tagged(b'TapBranch',min(a,b)+max(a,b)),'Script.tapBranchHash',64)
for n in [20,32]:
 data=bytes((i*11+1)%256 for i in range(n))
 if n==20:
  for f,pre,post in [('p2pkh',bytes.fromhex('76a914'),bytes.fromhex('88ac')),('p2sh',bytes.fromhex('a914'),bytes.fromhex('87')),('p2wpkh',b'\x00\x14',b'')]:actor('bitcoin-script-'+f,'  transient let input : Blob = '+lit(data)+';','    let ?value=S.'+f+'(input) else Prim.trap("script"); result:=value;',pre+data+post,'Script.'+f,n)
 else:
  for f,pre in [('p2wsh',b'\x00\x20'),('p2tr',b'\x51\x20')]:actor('bitcoin-script-'+f,'  transient let input : Blob = '+lit(data)+';','    let ?value=S.'+f+'(input) else Prim.trap("script"); result:=value;',pre+data,'Script.'+f,n)
for c in json.load(open(root/'benchmarks/crypto/all-cases.json'))['cases']:
 if c['name'].startswith('bitcoin-serialize-') and c['implementation']=='native':
  raw=bytes.fromhex(c['expected_hex']);name=c['name'].replace('serialize','parse')
  actor(name,'  transient let input : Blob = '+lit(raw)+';\n  transient var parsed : ?T.Tx = null;','    parsed:=T.parse(input); assert parsed != null;',raw,'Transaction.parse',len(raw))
  p=dest/name/'main.mo';s=p.read_text().replace('public query func bytesResult() : async Blob { result }','public query func bytesResult() : async Blob { let ?tx=parsed else Prim.trap("parse"); let ?bytes=T.serialize(tx,true) else Prim.trap("serialize"); bytes }');p.write_text(s)
(dest/'cases.json').write_text(json.dumps({'cases':cases},indent=2)+'\n')
print(len(cases))
