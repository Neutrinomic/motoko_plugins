#!/usr/bin/env python3
"""Pin reviewable final Wasm excerpts; structural checks are not a CT proof."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args()
args.out.mkdir(parents=True,exist_ok=True)
text=subprocess.check_output(['wasm2wat','--enable-all',str(args.runtime)],text=True)
functions={}
for fragment in re.split(r'(?=^  \(func )',text,flags=re.M):
    fragment=re.split(r'(?=^  \((?!func ))',fragment,maxsplit=1,flags=re.M)[0]
    if not fragment.strip(): continue
    header=fragment.splitlines()[0]
    for label,needle in [('fixed_select','fixed_base6select'),('fixed_multiply','MulByGenerator16mul_by_generator'),('affine_select','affineNt'),('scalar_square','scalarNt'),('scalar_reduce','WideScalar11reduce_impl'),('wide_multiply','(func $__multi3 '),('public_x_compare','x_matches_scalar_vartime')]:
        if needle not in header: continue
        if label=='affine_select' and 'ConditionallySelectable18conditional_select' not in header: continue
        if label=='scalar_square' and '6square' not in header: continue
        assert label not in functions,('ambiguous function',label)
        functions[label]=fragment
assert {'fixed_select','fixed_multiply','affine_select'}.issubset(functions)
branch_pattern=r'^\s*(?:if|br_if|br_table)\b'
assert not re.search(branch_pattern,functions['fixed_select'],re.M)
assert not re.search(branch_pattern,functions['affine_select'],re.M)
assert len(re.findall(r'^\s+call .*affine.*ConditionallySelectable18conditional_select',functions['fixed_select'],re.M))==8
assert len(re.findall(branch_pattern,functions['fixed_multiply'],re.M))==3
if 'scalar_square' in functions:
    assert not re.search(branch_pattern,functions['scalar_square'],re.M)
    assert not re.search(branch_pattern,functions['scalar_reduce'],re.M)
    assert not re.search(branch_pattern,functions['wide_multiply'],re.M)
    assert len(re.findall(r'^\s+call \$__multi3$',functions['scalar_square'],re.M))==10
report={'runtime_sha256':hashlib.sha256(args.runtime.read_bytes()).hexdigest(),
        'wasm2wat_version':subprocess.check_output(['wasm2wat','--version'],text=True).strip(),
        'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'review_scope':'Final scalar recoding, fixed eight-entry affine selection and public row traversal. Branch-free selection, fixed-offset reads and three public-counter loop exits were reviewed. Scalar square, unchanged reduction and __multi3 have no conditional branches; square uses ten wide multiplication calls. Public ECDSA comparison intentionally has public-data branches. This is not a formal constant-time or host timing certification.',
        'functions':{}}
for name,fragment in functions.items():
    output=args.out/(name+'.wat.gz')
    output.write_bytes(gzip.compress(fragment.encode(),mtime=0))
    report['functions'][name]={'name':fragment.splitlines()[0], 'sha256':hashlib.sha256(fragment.encode()).hexdigest(), 'compressed_sha256':hashlib.sha256(output.read_bytes()).hexdigest(), 'conditional_branches':len(re.findall(branch_pattern,fragment,re.M)), 'calls':len(re.findall(r'^\s+call ',fragment,re.M))}
(args.out/'wasm-review.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({name:item['conditional_branches'] for name,item in report['functions'].items()}))
