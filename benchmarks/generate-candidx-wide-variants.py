#!/usr/bin/env python3
"""Exercise sparse primitive arrays with a wide declared variant type."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--width', type=int, default=4096)
args = parser.parse_args()
assert args.width >= 1024
subprocess.run([sys.executable, str(Path(__file__).with_name('generate.py')),
                '--out', str(args.out), '--variant-width', str(args.width),
                '--repeated-variants'], check=True)
source_path = args.out / 'main.mo'
source = source_path.read_text()
manifest = json.loads((args.out / 'cases.json').read_text())
cases = [case for case in manifest['cases'] if 'repeated-variants' in case['name']]
last = args.width - 1
inputs = [(0, str(last), 'empty'), (1, str(last), 'singleton-high'),
          (2, str(last), 'pair-same-high'),
          (2, f'if (i == 0) 0 else {last}', 'pair-far'),
          (65, f'i * {last} / 64', 'sparse-65')]
# A narrow equivalent reference avoids making ordinary Candid's serializer
# scale with thousands of unused cases. Both arrays have identical values;
# canonicalization independently discards the reference's unused cases.
selected = sorted({i * last // 64 for i in range(65)})
reference = '  type ReferenceChoice = { ' + '; '.join(
    f'#t{i:04d} : Nat' for i in selected) + ' };\n'
reference += '  transient var referenceVariants : [ReferenceChoice] = [];\n'
reference += '  func referenceChoice(i : Nat) : ReferenceChoice { switch i { '
reference += ' '.join(f'case {i} #t{i:04d}(i);' for i in selected)
reference += ' case _ Prim.trap("reference index out of range") } };\n'
source = source.replace('  transient var variants : [Choice] = [];',
                        reference + '  transient var variants : [Choice] = [];')
for case, (count, choice, name) in zip(cases, inputs, strict=True):
    setup = (f'variants := Prim.Array_tabulate<Choice>({count}, '
             f'func(i) {{ choice({choice}); }}); '
             f'referenceVariants := Prim.Array_tabulate<ReferenceChoice>({count}, '
             f'func(i) {{ referenceChoice({choice}); }});')
    source, replaced = re.subn(r'(case ' + str(case['index']) +
                              r' \{ )variants := [^;]+;',
                              lambda match: match[1] + setup, source)
    assert replaced == 1
    case['name'] = f'candid-wide-{args.width}-{name}'
source = source.replace('output := to_candid(variants);',
                        'output := to_candid(referenceVariants);')
source_path.write_text(source)
(args.out / 'cases.json').write_text(json.dumps(manifest, indent=2) + '\n')
