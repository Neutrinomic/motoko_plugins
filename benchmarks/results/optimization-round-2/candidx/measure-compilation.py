import hashlib,json,resource,subprocess,time
from pathlib import Path
root=Path('/srv/shared/code/motoko_experiments/optimization-round-2/candidx')
out=root/'_build/opt2-candidx'
rows=[]
for trial,labels in enumerate([['baseline','candidate'],['candidate','baseline'],['baseline','candidate']]):
 for label in labels:
  package=out/'baseline/candidx' if label=='baseline' else root/'dist/candidx'
  target=out/'compile-timing.wasm'
  command=['/srv/shared/code/motoko_experiments/motoko_sha/bin/moc','--plugin',str(package),'--plugin',str(root/'dist/sha256'),str(out/'main/main.mo'),'-o',str(target)]
  before=resource.getrusage(resource.RUSAGE_CHILDREN);start=time.monotonic()
  subprocess.run(command,check=True)
  elapsed=time.monotonic()-start;after=resource.getrusage(resource.RUSAGE_CHILDREN)
  rows.append({'trial':trial,'label':label,'wall_seconds':elapsed,'user_cpu_seconds':after.ru_utime-before.ru_utime,'system_cpu_seconds':after.ru_stime-before.ru_stime,'wasm_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'command':command})
(out/'compilation.json').write_text(json.dumps({'note':'Three alternating fresh moc processes; host timing only, concurrent other component work; not IC instruction costs','measurements':rows},indent=2)+'\n')
