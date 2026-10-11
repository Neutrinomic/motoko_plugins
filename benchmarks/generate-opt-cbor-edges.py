#!/usr/bin/env python3
"""Independent CBOR edge inputs for the fixed-compiler optimization round."""
import argparse
import json
from pathlib import Path

import cbor2

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--errors-only', action='store_true')
args = parser.parse_args()
args.out.mkdir(parents=True, exist_ok=True)


def blob(data):
    return '"' + ''.join(f'\\{byte:02x}' for byte in data) + '"'


def normalized(value):
    if isinstance(value, bytes):
        return {'$bytes': value.hex()}
    if isinstance(value, list):
        return [normalized(v) for v in value]
    if isinstance(value, dict):
        return {k: normalized(v) for k, v in value.items()}
    return value


wide = {f'field{i:02}': i for i in range(16)}
workloads = [
    ('empty-record', '{}', '{}', {}),
    ('scalars', '(Nat64, Int64, Nat, Int, Char, Float, Float32, Principal)',
     '(18446744073709551615, -9223372036854775808, 18446744073709551616, '
     '-18446744073709551617, \'😀\', 1.1, 1.5, Prim.principalOfBlob("\\04"))',
     [2**64-1, -2**63, 2**64, -2**64-1, '😀', 1.1, 1.5, b'\x04']),
    ('bools-4096', '[Bool]',
     'Prim.Array_tabulate<Bool>(4096, func(i) { i % 2 == 0 })',
     [i % 2 == 0 for i in range(4096)]),
    ('options-256', '[??Nat8]',
     'Prim.Array_tabulate<??Nat8>(256, func(i) { if (i % 3 == 0) null else if (i % 3 == 1) ?null else ??Prim.natToNat8(i) })',
     [None if i % 3 == 0 else {'some': None if i % 3 == 1 else i} for i in range(256)]),
    ('unicode-256', '[Text]',
     'Prim.Array_tabulate<Text>(256, func(_) { "~ / é 😀" })', ['~ / é 😀']*256),
    ('wide-record', '{' + '; '.join(f'{k} : Nat8' for k in wide) + '}',
     '{' + '; '.join(f'{k} = {v}' for k, v in wide.items()) + '}', wide),
    ('variant', '{#ready; #value : (?Null, Blob)}',
     '#value(?null, "\\00\\ff")', {'value': [{'some': None}, b'\x00\xff']}),
]
decls, configure, clear, methods, validate, cases = [], [], [], [], [], []
for n, (name, typ, value, expected) in enumerate([] if args.errors_only else workloads):
    decls += [f'transient var value{n} : ?({typ}) = null;',
              f'transient var result{n} : ?({typ}) = null;']
    clear.append(f'result{n} := null;')
    wire = blob(cbor2.dumps(expected, canonical=True))
    for direction in ('encode', 'decode'):
        index = len(cases)
        configure.append(f'case {index} {{ value{n} := ?({value} : {typ}); input := {wire} }};')
        method = f'bench_{index}_plugin'
        cases.append({'name': f'cbor-{name}-{direction}', 'index': index,
                      'family': 'cbor', 'expected_cbor': normalized(expected),
                      'phases': [{'label': 'plugin', 'method': method,
                                  'kind': 'cbor' if direction == 'encode' else 'checked_decode',
                                  'require_no_gc': True}]})
        if direction == 'encode':
            operation = f'encoded := require(Prim.to_cbor(requireOpt(value{n})));'
            check = f'{{ assert encoded == {wire}; encoded }}'
            size = 'encoded.size()'
        else:
            operation = f'result{n} := ?require(Prim.from_cbor<{typ}>(input));'
            check = f'{{ assert result{n} == value{n}; "ok" }}'
            size = '2'
        validate.append(f'case {index} {check};')
        methods.append(f'''public func {method}() : async Measurement {{
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    {operation}
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{ instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
       reclaimed = reclaimedAfter - reclaimedBefore; outputSize = {size} }}
  }};''')

if args.errors_only:
    decls.extend(['type Error = {kind : Text; message : Text; path : Text; offset : Nat64};',
                  'transient var error : ?Error = null;',
                  'transient var expectedPath : Text = "";'])
    clear.append('error := null;')
    errors = [
        ('long-key-error', '{}', b'\xa1' + cbor2.dumps('x'*262144) + b'\x61\xff',
         '"/" # repeatedText("x", 262144)'),
        ('escaped-key-error', '{}', b'\xa1' + cbor2.dumps('~/é'*4096) + b'\x61\xff',
         '"/" # repeatedText("~0~1é", 4096)'),
        ('nested-index-error', '{a : [Text]}', b'\xa1\x61a\x8c' + b'\x60'*11 + b'\x61\xff',
         '"/a/11"'),
    ]
    for index, (name, typ, wire, path) in enumerate(errors):
        try:
            cbor2.loads(wire)
        except cbor2.CBORDecodeError:
            pass
        else:
            raise AssertionError('Independent decoder accepted malformed input')
        configure.append(f'case {index} {{ input := {blob(wire)}; expectedPath := {path} }};')
        method = f'bench_{index}_plugin'
        cases.append({'name': f'cbor-{name}', 'index': index, 'family': 'cbor',
                      'phases': [{'label': 'plugin', 'method': method,
                                  'kind': 'checked_decode', 'require_no_gc': True}]})
        validate.append(f'''case {index} {{
          let e = requireOpt(error);
          assert e.kind == "utf8" and e.message == "Invalid UTF-8 in CBOR text";
          assert e.path == expectedPath and e.offset == {len(wire)};
          "ok"
        }};''')
        methods.append(f'''public func {method}() : async Measurement {{
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    error := switch (Prim.from_cbor<{typ}>(input)) {{
      case (#err e) ?e; case (#ok _) Prim.trap("expected malformed input error")
    }};
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{ instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
       reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 2 }}
  }};''')
    decls.append('''func repeatedText(pattern : Blob, count : Nat) : Text {
      let bytes = Prim.blobToArray(pattern);
      requireOpt(Prim.decodeUtf8(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(
        count * bytes.size(), func(i) { bytes[i % bytes.size()] }))))
    };''')

(args.out / 'main.mo').write_text(f'''// Generated by benchmarks/generate-opt-cbor-edges.py.
import Prim "mo:⛔";
actor {{
  type Measurement = {{instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat}};
  func {'_require' if args.errors_only else 'require'}<T, E>(r : {{#ok : T; #err : E}}) : T {{
    switch r {{ case (#ok v) v; case (#err _) Prim.trap("CBOR error") }}
  }};
  func requireOpt<T>(r : ?T) : T {{
    switch r {{ case (?v) v; case null Prim.trap("missing result") }}
  }};
  transient var selected = 0;
  transient var input : Blob = "";
  transient var encoded : Blob = "";
  {chr(10).join(decls)}
  public func configure(index : Nat) : async () {{
    selected := index;
    switch index {{ {chr(10).join(configure)} case _ Prim.trap("unknown case") }}
  }};
  public func clear() : async () {{ encoded := ""; {' '.join(clear)} }};
  public query func bytesResult() : async Blob {{
    switch selected {{ {chr(10).join(validate)} case _ Prim.trap("unknown case") }}
  }};
  {chr(10).join(methods)}
}}
''')
(args.out / 'cases.json').write_text(json.dumps({
    'cases': cases,
    'methodology': ('Three fresh-canister trials; same actor for baseline/final. Inputs, expected paths and validation are outside timing. Failed typed decoding, diagnostic construction, Result unwrapping and retained error assignment are timed; no plugin GC allowed.' if args.errors_only else 'Three fresh-canister trials; same actor for baseline/final. Setup and checks outside timing. All output bytes must equal independently generated cbor2 canonical bytes. Host cbor2 also decodes each encoded result. Decoders consume cbor2 bytes and compare complete typed values outside timing. Successful Result unwrapping and retained assignment are timed; no plugin GC allowed.'),
    'correctness': ('Malformed inputs are constructed independently and rejected by cbor2 at generation. Each actor query checks the complete typed error kind, message, path, and offset outside measurement.' if args.errors_only else 'Encoder bytes must equal independently generated cbor2 canonical bytes in the actor query and decode to the expected value with host cbor2. Decoder inputs are generated independently by cbor2; the actor query compares the complete retained typed value against independently constructed Motoko data. The two-byte ok reply is not decoded value size.'),
}, ensure_ascii=False, indent=2) + '\n')
