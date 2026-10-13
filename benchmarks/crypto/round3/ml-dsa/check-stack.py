#!/usr/bin/env python3
"""Conservative stack-frame sum along every direct runtime call path."""
import hashlib,json,re,subprocess,sys
from pathlib import Path
runtime=Path(sys.argv[1])
text=subprocess.check_output(['wasm2wat','--enable-memory64',str(runtime)],text=True)
starts=list(re.finditer(r'^  \(func (\$[^ ]+)',text,re.M))
assert len(re.findall(r'global.get \$__stack_pointer', text)) == len(re.findall(r'global.get \$__stack_pointer\s+i64.const (\d+)\s+i64.sub', text)), 'Unrecognized stack-pointer use requires separate analysis'
functions={}
for i,start in enumerate(starts):
    source=text[start.end():starts[i+1].start() if i+1<len(starts) else len(text)]
    frames=[int(n) for n in re.findall(r'global.get \$__stack_pointer\s+i64.const (\d+)\s+i64.sub',source)]
    assert len(frames) <= 1, 'Multiple stack adjustments require separate analysis'
    functions[start.group(1)]={'frame':max(frames,default=0),'calls':re.findall(r'\bcall (\$[^\s()]+)',source)}
assert not re.search(r'\bcall_indirect\b',text), 'Indirect call requires separate stack analysis'
memo={}
def bound(name,seen=()):
    if name in memo:return memo[name]
    assert name not in seen, 'Recursion requires separate stack analysis'
    f=functions[name]
    callees=[bound(c,(*seen,name)) for c in f['calls'] if c in functions]
    subtotal,path=max(callees,default=(0,[]),key=lambda row:row[0])
    value=(f['frame']+subtotal,[name,*path])
    memo[name]=value
    return value
exports={}
for name in ['mldsa_public_key','mldsa_sign','mldsa_sign_randomized','mldsa_verify']:
    value,path=bound('$'+name)
    exports[name]={'conservative_stack_bytes':value,'path':path}
print(json.dumps({'runtime_sha256':hashlib.sha256(runtime.read_bytes()).hexdigest(),'method':'Sum each function maximum static __stack_pointer subtraction over acyclic direct call graph; no indirect calls. This bounds the plugin runtime frames only, not the Motoko caller.','exports':exports},indent=2))
