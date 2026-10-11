#!/usr/bin/env python3
"""JSON arbitrary-precision integer encoding and decoding workloads."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
out = parser.parse_args().out
out.mkdir(parents=True, exist_ok=True)

values = [
    ('zero', 'Nat', '0', 0),
    ('small', 'Nat', '123456789', 123456789),
    ('boundary', 'Nat', '1000000000', 1000000000),
    ('u64', 'Nat', str(2**64 - 1), 2**64 - 1),
    ('negative', 'Int', str(-2**127), -2**127),
    ('digits-128', 'Nat', '9' * 128, int('9' * 128)),
    ('digits-4096', 'Nat', '9' * 4096, int('9' * 4096)),
]
integers = [(1 if i % 2 else -1) * (10**127 + i) for i in range(128)]
values.append(('array-128', '[Int]', '[' + ','.join(map(str, integers)) + ']', integers))


def wire(value):
    return [str(x) for x in value] if isinstance(value, list) else str(value)


cases, declarations, configure, methods, validate, clear = [], [], [], [], [], []
for j, (name, typ, expression, value) in enumerate(values):
    declarations += [f'transient let value{j} : {typ} = {expression};',
                     f'transient var decoded{j} : ?{typ} = null;']
    clear.append(f'decoded{j} := null;')
    text = json.dumps(wire(value), separators=(',', ':'))
    for direction in ('encode', 'decode'):
        i = len(cases)
        case = {
            'name': f'json-numbers-{name}-{direction}', 'index': i, 'family': 'json',
            'phases': [{'label': direction, 'method': f'bench_{i}',
                        'kind': 'json' if direction == 'encode' else 'checked_decode',
                        'require_no_gc': True}],
        }
        if direction == 'encode':
            case['expected_json'] = wire(value)
            operation = f'encoded := require(Prim.to_json(value{j}));'
            size = 'Prim.encodeUtf8(encoded).size()'
            check = 'Prim.encodeUtf8(encoded);'
        else:
            operation = f'decoded{j} := ?require(Prim.from_json<{typ}>(input));'
            size = '2'
            check = f'{{assert decoded{j} == ?value{j}; "ok"}};'
        cases.append(case)
        configure.append(f'case {i} input := {json.dumps(text)};')
        validate.append(f'case {i} {check}')
        methods.append(f'''public func bench_{i}() : async Measurement {{
  let a = Prim.rts_total_allocation(); let r = Prim.rts_reclaimed(); let s = Prim.performanceCounter(0);
  {operation}
  let e = Prim.performanceCounter(0); let aa = Prim.rts_total_allocation(); let rr = Prim.rts_reclaimed();
  {{instructions=e-s; allocated=aa-a; reclaimed=rr-r; outputSize={size}}}
  }};''')

source = '''import Prim "mo:⛔";
actor {
 type Error={kind:Text; message:Text; path:Text; offset:Nat64};
 type Measurement={instructions:Nat64;allocated:Nat;reclaimed:Nat;outputSize:Nat};
 func require<T>(x:{#ok:T;#err:Error}):T {switch x {case (#ok v) v;case (#err e) Prim.trap(e.message)}};
 transient var input:Text=""; transient var encoded:Text=""; transient var selected:Nat=0;
''' + '\n'.join(declarations) + '''
 public func configure(index:Nat):async(){selected:=index; switch index {''' + '\n'.join(configure) + '''case _ Prim.trap("unknown")}};
 public func clear():async(){encoded:="";''' + ''.join(clear) + '''};
 public query func bytesResult():async Blob {switch selected {''' + '\n'.join(validate) + '''case _ Prim.trap("unknown")}};
''' + '\n'.join(methods) + '\n}\n'
(out / 'main.mo').write_text(source)
(out / 'cases.json').write_text(json.dumps({
    'cases': cases,
    'methodology': 'Same measurement protocol as focused JSON suite. Constants/input parsing/validation outside measurement.',
    'correctness': 'Python-generated decimal strings are compared as JSON values; typed decoding checked against independently compiled Motoko integers.',
}, indent=2) + '\n')
