#!/usr/bin/env python3
"""Compare typed JSON/CBOR plugins with pinned Mops codecs, end to end."""
import argparse
import json
from pathlib import Path


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--codec', choices=('json', 'cbor'), required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
codec = args.codec


def literal(text):
    return json.dumps(text, ensure_ascii=False)


def blob_literal(value):
    return '"' + ''.join(f'\\{byte:02x}' for byte in value) + '"'


row = {'active': True, 'id': '18446744073709551615', 'name': 'Ada ☃ "hello"', 'tag': 'tag'}
rows = [{'active': i % 2 == 0, 'id': str(i * 17), 'name': 'record ☃', 'tag': 'tag'}
        for i in range(1024)]
bulk = ('0123456789abcdef' * 4096 if codec == 'json'
        else bytes((i * 17 + 11) % 256 for i in range(65536)))
workloads = [('record', 'Row', 'row', row), ('records-1024', '[Row]', 'rows', rows),
             ('text-64k' if codec == 'json' else 'blob-64k',
              'Text' if codec == 'json' else 'Blob', 'bulk', bulk)]
implementations = [('serde', 'serde', '3.5.0'), ('serde_core', 'serde-core', '0.2.1'),
                   ('native', codec, '1.4.0' if codec == 'json' else '4.1.0'),
                   ('plugin', f'plugin/{codec}', 'ABI 1')]
keys = '["active", "id", "name", "tag"]'

if codec == 'json':
    io_type, module = 'Text', 'JSON'
    wire = lambda value: literal(json.dumps(value, ensure_ascii=False, separators=(',', ':')))
    result_blob = 'Prim.encodeUtf8(encoded)'
    native_encode = {'row': 'Native.stringify(rowToValue(row), null)',
                     'rows': 'Native.stringify(#array(Prim.Array_tabulate<Native.Json>(rows.size(), func(i) { rowToValue(rows[i]) })), null)',
                     'bulk': 'Native.stringify(#string(bulk), null)'}
    native_decode = {'row': 'rowFromValue(require(Native.parse(input)))',
                     'rows': 'rowsFromValue(require(Native.parse(input)))',
                     'bulk': 'textFromValue(require(Native.parse(input)))'}
    native_helpers = '''
  func rowToValue(v : Row) : Native.Json {
    #object_([("active", #bool(v.active)), ("id", #string(v.id)),
              ("name", #string(v.name)), ("tag", #string(v.tag))])
  };
  func textFromValue(v : Native.Json) : Text {
    switch v { case (#string text) text; case _ Prim.trap("expected Text") }
  };
  func rowFromValue(v : Native.Json) : Row {
    let fields = switch v { case (#object_ fields) fields; case _ Prim.trap("expected object") };
    var active : ?Bool = null; var id : ?Text = null;
    var name : ?Text = null; var tag : ?Text = null;
    for ((key, value) in fields.values()) {
      switch key {
        case "active" { assert active == null; active := ?(switch value { case (#bool v) v; case _ Prim.trap("expected Bool") }) };
        case "id" { assert id == null; id := ?textFromValue(value) };
        case "name" { assert name == null; name := ?textFromValue(value) };
        case "tag" { assert tag == null; tag := ?textFromValue(value) };
        case _ {};
      }
    };
    {active = requireOpt(active); id = requireOpt(id); name = requireOpt(name); tag = requireOpt(tag)}
  };
  func rowsFromValue(v : Native.Json) : [Row] {
    let values = switch v { case (#array a) a; case _ Prim.trap("expected array") };
    Prim.Array_tabulate<Row>(values.size(), func(i) { rowFromValue(values[i]) })
  };
'''
else:
    import cbor2
    io_type, module = 'Blob', 'CBOR'
    wire = lambda value: blob_literal(cbor2.dumps(value, canonical=True))
    result_blob = 'encoded'
    native_encode = {'row': 'Prim.arrayToBlob(require(Native.toBytes(rowToValue(row))))',
                     'rows': 'Prim.arrayToBlob(require(Native.toBytes(#majorType4(Prim.Array_tabulate<Native.Value>(rows.size(), func(i) { rowToValue(rows[i]) })))))',
                     'bulk': 'Prim.arrayToBlob(require(Native.toBytes(#majorType2(Prim.blobToArray(bulk)))))'}
    native_decode = {'row': 'rowFromValue(require(Native.fromBytes(input.values())))',
                     'rows': 'rowsFromValue(require(Native.fromBytes(input.values())))',
                     'bulk': 'blobFromValue(require(Native.fromBytes(input.values())))'}
    native_helpers = '''
  func rowToValue(v : Row) : Native.Value {
    #majorType5([(#majorType3("active"), #majorType7(#bool(v.active))),
                 (#majorType3("id"), #majorType3(v.id)),
                 (#majorType3("name"), #majorType3(v.name)),
                 (#majorType3("tag"), #majorType3(v.tag))])
  };
  func textFromValue(v : Native.Value) : Text {
    switch v { case (#majorType3 text) text; case _ Prim.trap("expected Text") }
  };
  func blobFromValue(v : Native.Value) : Blob {
    switch v { case (#majorType2 a) Prim.arrayToBlob(a); case _ Prim.trap("expected Blob") }
  };
  func rowFromValue(v : Native.Value) : Row {
    let fields = switch v { case (#majorType5 fields) fields; case _ Prim.trap("expected map") };
    var active : ?Bool = null; var id : ?Text = null;
    var name : ?Text = null; var tag : ?Text = null;
    for ((keyValue, value) in fields.values()) {
      switch (textFromValue(keyValue)) {
        case "active" { assert active == null; active := ?(switch value { case (#majorType7(#bool v)) v; case _ Prim.trap("expected Bool") }) };
        case "id" { assert id == null; id := ?textFromValue(value) };
        case "name" { assert name == null; name := ?textFromValue(value) };
        case "tag" { assert tag == null; tag := ?textFromValue(value) };
        case _ {};
      }
    };
    {active = requireOpt(active); id = requireOpt(id); name = requireOpt(name); tag = requireOpt(tag)}
  };
  func rowsFromValue(v : Native.Value) : [Row] {
    let values = switch v { case (#majorType4 a) a; case _ Prim.trap("expected array") };
    Prim.Array_tabulate<Row>(values.size(), func(i) { rowFromValue(values[i]) })
  };
'''

cases, methods, configure, validate, outputs = [], [], [], [], []
for name, typ, variable, value in workloads:
    outputs.append(f'transient var decoded_{variable} : ?{typ} = null;')
    for direction in ('encode', 'decode'):
        index = len(cases)
        phases = []
        entry = {'name': f'{codec}-{name}-{direction}', 'index': index,
                 'family': codec, 'phases': phases}
        if direction == 'encode':
            entry[f'expected_{codec}'] = {'$bytes': value.hex()} if isinstance(value, bytes) else value
            check, output_size = result_blob, f'({result_blob}).size()'
        else:
            check, output_size = f'{{ assert decoded_{variable} == ?{variable}; "ok" }}', '2'
            if typ == 'Text':
                # A parser may return a deeply nested rope. Flatten for the
                # independent check, outside timing, to avoid recursive Text
                # equality overflowing the RTS stack on that representation.
                check = f'{{ assert Prim.encodeUtf8(requireOpt(decoded_{variable})) == Prim.encodeUtf8({variable}); "ok" }}'
        cases.append(entry)
        configure.append(f'case {index} input := {wire(value)};')
        validate.append(f'case {index} {check};')
        for label, _, _ in implementations:
            method = f'bench_{index}_{label}'
            phases.append({'label': label, 'method': method,
                           'kind': codec if direction == 'encode' else 'checked_decode',
                           'require_no_gc': label == 'plugin'})
            if label in ('serde', 'serde_core'):
                lib = 'Serde' if label == 'serde' else 'SerdeCore'
                if direction == 'encode':
                    fn = 'toText' if codec == 'json' else 'encode'
                    expression = f'require({lib}.{fn}(to_candid({variable}), {keys}, null))'
                else:
                    fn = 'fromText' if codec == 'json' else 'decode'
                    expression = f'requireOpt<{typ}>(from_candid(require({lib}.{fn}(input, null))))'
            elif label == 'native':
                expression = native_encode[variable] if direction == 'encode' else native_decode[variable]
            else:
                expression = (f'require(Prim.to_{codec}({variable}))' if direction == 'encode'
                              else f'require(Prim.from_{codec}<{typ}>(input))')
            operation = (f'encoded := {expression};' if direction == 'encode'
                         else f'decoded_{variable} := ?{expression};')
            methods.append(f'''public func {method}() : async Measurement {{
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    {operation}
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{ instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
       reclaimed = reclaimedAfter - reclaimedBefore; outputSize = {output_size} }}
  }};''')

source = f'''// Generated by benchmarks/generate-codec-comparison.py --codec {codec}.
import Prim "mo:⛔";
import Nat "mo:core/Nat";
import Serde "mo:serde/{module}";
import SerdeCore "mo:serde-core/{module}";
import Native "mo:{codec}";
actor {{
  type Row = {{active : Bool; id : Text; name : Text; tag : Text}};
  type Measurement = {{instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat}};
  func require<T, E>(r : {{#ok : T; #err : E}}) : T {{
    switch r {{ case (#ok v) v; case (#err _) Prim.trap("codec error") }}
  }};
  func requireOpt<T>(v : ?T) : T {{
    switch v {{ case (?v) v; case null Prim.trap("typed conversion failed") }}
  }};
  {native_helpers}
  transient let row : Row = {{active = true; id = {literal(row['id'])}; name = {literal(row['name'])}; tag = "tag"}};
  transient var rows : [Row] = [];
  transient var bulk : {'Text' if codec == 'json' else 'Blob'} = "";
  transient var input : {io_type} = "";
  transient var encoded : {io_type} = "";
  transient var selected : Nat = 0;
  {chr(10).join(outputs)}
  public func configure(index : Nat) : async () {{
    selected := index;
    rows := Prim.Array_tabulate<Row>(1024, func(i) {{
      {{ active = i % 2 == 0; id = Nat.toText(i * 17); name = "record ☃"; tag = "tag" }}
    }});
    bulk := {literal(bulk) if codec == 'json' else 'Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(65536, func(i) { Prim.natToNat8((i * 17 + 11) % 256) }))'};
    switch index {{ {chr(10).join(configure)} case _ Prim.trap("unknown benchmark") }}
  }};
  public func clear() : async () {{
    encoded := ""; decoded_row := null; decoded_rows := null; decoded_bulk := null;
  }};
  public query func bytesResult() : async Blob {{
    switch selected {{ {chr(10).join(validate)} case _ Prim.trap("unknown benchmark") }}
  }};
  {chr(10).join(methods)}
}}
'''
(args.out / 'main.mo').write_text(source)
(args.out / 'cases.json').write_text(json.dumps({
    'cases': cases,
    'implementations': {label: {'package': package, 'version': version}
                        for label, package, version in implementations},
    'methodology': 'Same actor and compiler for all implementations; fresh canister per workload/trial. Independently generated wire input and typed inputs prepared outside measurement. Four forced GC increments before each phase. Timed interval includes typed-to-tree/tree-to-typed adapters, to_candid/from_candid when required by serde, successful Result unwrapping, output Blob conversion, and retained output assignment. Native synchronous GC is included; plugin phases require none. Validation, JSON UTF8 reply conversion, and message-end GC are excluded. Records contain Bool and Text fields to use matching wire semantics across libraries.',
    'correctness': 'JSON encoder output is parsed by host JSON.parse; CBOR output by independent Python cbor2. Both are compared semantically to Python-generated data (not byte equality). Decoder input comes from Python json/cbor2, never the encoder being tested. A separate actor query compares the complete retained typed result to an independently constructed Motoko value; its two-byte ok reply is not decoded object size.',
}, indent=2, ensure_ascii=False) + '\n')
print(args.out / 'main.mo')
