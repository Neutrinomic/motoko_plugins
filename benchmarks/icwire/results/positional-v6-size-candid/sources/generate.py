#!/usr/bin/env python3
"""Generate matched typed codec workloads; construction/checks are not timed."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--baseline-only', action='store_true')
p.add_argument('--recursive', action='store_true', help='separate recursive-schema suite')
p.add_argument('--scalars', action='store_true', help='separate scalar-boundary suite')
p.add_argument('--combined', action='store_true', help='all application, recursive, and scalar fixtures')
p.add_argument('--zero-capacity', action='store_true', help='separate native Candid zero-width value-limit probe')
p.add_argument('--memory-probe', action='store_true', help='report heap/linear-memory counters outside timing')
p.add_argument('--warm-heap', action='store_true', help='reserve and clear 8 MiB before the runner collects and measures')
p.add_argument('--codec', choices=['all', 'candid', 'candidx', 'icwire'], default='all',
               help='isolate a codec for Wasm-size comparison; all is the timed suite')
a = p.parse_args()
if a.warm_heap:
    a.memory_probe = True
if sum([a.recursive, a.scalars, a.combined, a.zero_capacity]) > 1:
    p.error('choose at most one specialized suite')
a.out.mkdir(parents=True, exist_ok=True)

types = '''
  type Tiny = {sequence : Nat64; ready : Bool; count : Nat; tag : Text};
  type Address = {namespace : Nat; execution : Nat; node : Nat; visit : Nat; version : Nat};
  type Event = {target : Address; chain : Nat8; block : Nat; topic : Blob; payload : Blob};
  type Child = {workflow : Text; version : Nat; input : Blob;
    topic : {chain : Nat8; key : Blob}; target : {canister : Principal; id : Nat}};
  type Account = {owner : Principal; subaccount : ?Blob};
  type Action = {
    #Transfer : {from : Account; to : Account; amount : Nat; fee : ?Nat; memo : ?Blob};
    #Approve : {from : Account; spender : Account; amount : Nat; expiresAt : ?Int};
    #Reserve : {account : Account; amount : Nat; resource : Text};
    #Cancel : Nat;
  };
  type Block = {caller : Principal; timestamp : Int; nonce : ?Nat; actions : [Action]};
  type Origin = {caller : Principal; issuer : Principal; operation : Blob};
  type Payload = {
    #Request : {id : Nat; route : Text; body : Blob; expiresAt : ?Int};
    #Response : {id : Nat; route : Text; outcome : {#Reply : Blob; #Expired}};
    #Notify : {route : Text; body : Blob};
    #Event : {id : Nat; body : Blob};
  };
  type Frame = {sequence : Nat; origin : Origin; requiredReader : Nat; payload : Payload};
  type Batch = {version : Nat; segments : [{priority : {#Control; #Interactive; #Maintenance}; frames : [Frame]}]};
  type Nested = [{id : Nat64; value : ?{#Empty; #Text : Text; #Ints : [Int]}}];
'''

families = [
 ('scalar', 'Nat64', '42', [("scalar-nat64", "42")]),
 ('tiny', 'Tiny', '{sequence = 0; ready = false; count = 0; tag = ""}',
  [("tiny-record", '{sequence = 1234567; ready = true; count = 42; tag = "completed"}')]),
 ('blob', 'Blob', '""', [(f'blob-{n}', f'makeBlob({n})') for n in [0, 32, 1024, 65536]]),
 ('event', 'Event', 'eventValue(0)', [(f'takt-event-{n}', f'eventValue({n})') for n in [0, 32, 1024, 65536]]),
 ('child', 'Child', 'childValue(0)', [(f'takt-child-{n}', f'childValue({n})') for n in [32, 1024]]),
 ('block', 'Block', 'blockValue(0)', [(f'rechain-actions-{n}', f'blockValue({n})') for n in [1, 32, 1024]]),
 ('batch', 'Batch', 'batchValue(0)', [(f'reactor-frames-{n}', f'batchValue({n})') for n in [1, 64, 1024]]),
 ('numbers', '[Nat64]', '[]', [(f'nat64-array-{n}', f'Prim.Array_tabulate<Nat64>({n}, func(i) {{Prim.natToNat64(i * 17 + 3)}})') for n in [0, 1, 4096]]),
 ('nested', 'Nested', '[]', [(f'nested-options-{n}', f'nestedValue({n})') for n in [1, 1024]]),
]

support = '''
  func makeBlob(size : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) {Prim.natToNat8((i * 17 + 11) % 256)}))
  };
  func eventValue(size : Nat) : Event {
    {target = {namespace = 13; execution = 987654; node = 7; visit = 2; version = 1};
     chain = 3; block = 123456789; topic = makeBlob(32); payload = makeBlob(size)}
  };
  func childValue(size : Nat) : Child {
    {workflow = "settle-transfer"; version = 2; input = makeBlob(size);
     topic = {chain = 3; key = makeBlob(32)}; target = {canister = Prim.principalOfBlob("\\00\\01"); id = 987654}}
  };
  func account(i : Nat) : Account {
    {owner = Prim.principalOfBlob("\\00\\01"); subaccount = if (i % 2 == 0) null else ?makeBlob(32)}
  };
  func blockValue(count : Nat) : Block {
    {caller = Prim.principalOfBlob("\\00\\01"); timestamp = 1_700_000_000_123_456_789; nonce = ?42;
     actions = Prim.Array_tabulate<Action>(count, func(i) {
       switch (i % 4) {
         case 0 #Transfer({from = account(i); to = account(i + 1); amount = 100000000 + i; fee = ?10000; memo = ?makeBlob(32)});
         case 1 #Approve({from = account(i); spender = account(i + 1); amount = 1000000; expiresAt = ?1_700_000_100_123_456_789});
         case 2 #Reserve({account = account(i); amount = 123456789; resource = "asset:default"});
         case _ #Cancel(i);
       }
     })}
  };
  func batchValue(count : Nat) : Batch {
    {version = 1; segments = [{priority = #Interactive; frames = Prim.Array_tabulate<Frame>(count, func(i) {
      {sequence = i + 12345; origin = {caller = Prim.principalOfBlob("\\00\\01"); issuer = Prim.principalOfBlob("\\01\\01"); operation = makeBlob(16)};
       requiredReader = 1; payload = switch (i % 4) {
         case 0 #Request({id = i; route = "settle"; body = makeBlob(128); expiresAt = ?1_700_000_100_123_456_789});
         case 1 #Response({id = i; route = "settle"; outcome = #Reply(makeBlob(32))});
         case 2 #Notify({route = "committed"; body = makeBlob(64)});
         case _ #Event({id = i; body = makeBlob(32)});
       }}
    })}]}
  };
  func nestedValue(count : Nat) : Nested {
    Prim.Array_tabulate<{id : Nat64; value : ?{#Empty; #Text : Text; #Ints : [Int]}}>(count, func(i) {
      {id = Prim.natToNat64(i); value = switch (i % 4) {
        case 0 null; case 1 ?#Empty; case 2 ?#Text("hello 🌐");
        case _ ?#Ints([-99999999999999999999999999999999, -65, -1, 0, 64, 18446744073709551616]);
      }}
    })
  };
'''

base_types, base_support, base_families = types, support, families
if a.recursive or a.combined:
    types = '''
  type Chain = ?{value : Nat64; next : Chain};
  type Tree = {#Leaf : Nat64; #Branch : {left : Tree; right : Tree; name : Text}};
'''
    support = '''
  func chainValue(count : Nat) : Chain {
    var result : Chain = null;
    var i = 0;
    while (i < count) {
      result := ?{value = Prim.natToNat64(i); next = result}; i += 1
    };
    result
  };
  func treeValue(depth : Nat) : Tree {
    if (depth == 0) #Leaf(42) else #Branch({
      left = treeValue(depth - 1); right = treeValue(depth - 1); name = "branch"
    })
  };
'''
    families = [
        ('chain', 'Chain', 'null', [(f'recursive-chain-{n}', f'chainValue({n})') for n in [1, 63]]),
        ('tree', 'Tree', '#Leaf(0)', [('recursive-tree-63', 'treeValue(5)')]),
    ]
    if a.combined:
        types = base_types + types
        support = base_support + support
        families = base_families + families

previous_types, previous_support, previous_families = types, support, families
if a.scalars or a.combined:
    types = ''
    support = '''
  func makeBlob(size : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) {Prim.natToNat8((i * 17 + 11) % 256)}))
  };
'''
    families = [
        ('null_value', 'Null', 'null', [('null', 'null')]),
        ('bool_value', 'Bool', 'false', [('bool-false', 'false'), ('bool-true', 'true')]),
        ('nat_value', 'Nat', '0', [(f'nat-{n}', str(n)) for n in [0, 127, 128, 18446744073709551616]]),
        ('int_value', 'Int', '0', [(f'int-{n}', str(n)) for n in [-65, -1, 0, 63, 64, -18446744073709551617]]),
        ('fixed', 'Nat64', '0', [('nat64-max', '18446744073709551615')]),
        ('text_value', 'Text', '""', [('text-empty', '""'), ('text-short', '"hi"'),
          ('text-unicode', '"hello 🌐"'), ('text-4096', '"' + 'x' * 4096 + '"')]),
        ('blob_value', 'Blob', '""', [(f'blob-{n}', f'makeBlob({n})') for n in [0, 32, 65536]]),
    ]
    if a.combined:
        types = previous_types
        support = previous_support
        # Retain every scalar-suite fixture, including duplicate Blob sizes,
        # under explicit names instead of silently removing observations.
        families = previous_families + [
            (name, typ, initial, [('scalar-' + title, expression) for title, expression in specs])
            for name, typ, initial, specs in families
        ]

if a.combined:
    types += '''
  type Words = {u8 : Nat8; u16 : Nat16; u32 : Nat32; u64 : Nat64;
    i8 : Int8; i16 : Int16; i32 : Int32; i64 : Int64;
    f32 : Float32; f64 : Float; char : Char};
'''
    support += '''
  func textRope(count : Nat) : Text {
    var text = "";
    var i = 0;
    while (i < count) {text := text # "x"; i += 1};
    text
  };
'''
    families += [
        ('words', 'Words', '{u8=0;u16=0;u32=0;u64=0;i8=0;i16=0;i32=0;i64=0;f32=0;f64=0;char=\'a\'}',
         [('all-fixed-primitives', '{u8=255;u16=65535;u32=4294967295;u64=18446744073709551615;i8=(-128);i16=(-32768);i32=(-2147483648);i64=(-9223372036854775808);f32=1.5;f64=(-2.25);char=\'😀\'}')]),
        ('principal_value', 'Principal', 'Prim.principalOfBlob("")',
         [('principal-empty', 'Prim.principalOfBlob("")'), ('principal-anonymous', 'Prim.principalOfBlob("\\04")'), ('principal-29', 'Prim.principalOfBlob(makeBlob(29))')]),
        ('rope_value', 'Text', '""', [('text-rope-4096', 'textRope(4096)')]),
    ]
    def array_family(name, typ, expression, sizes=(0, 1, 4096)):
        return (name.replace('-', '_'), '[' + typ + ']', '[]',
                [(f'{name}-{n}', f'Prim.Array_tabulate<{typ}>({n}, func(i) {{{expression}}})') for n in sizes])
    families += [
        array_family('null-array', 'Null', 'ignore i; null', (0, 1, 512, 1024)),
        array_family('unit-array', '()', 'ignore i; ()', (0, 1, 512, 1024)),
        array_family('bool-array', 'Bool', 'i % 2 == 0'),
        array_family('small-nat-array', 'Nat', 'i % 128'),
        array_family('big-nat-array', 'Nat', '340282366920938463463374607431768211456 + i'),
        array_family('mixed-int-array', 'Int', 'switch (i % 6) {case 0 (-340282366920938463463374607431768211457); case 1 (-65); case 2 (-1); case 3 0; case 4 64; case _ 340282366920938463463374607431768211456}'),
        array_family('text-array', 'Text', 'if (i % 2 == 0) "hello" else "🌐"'),
        array_family('float-array', 'Float', 'switch (i % 4) {case 0 (-0.0); case 1 1.5; case 2 (-2.25); case _ 65536.5}'),
        array_family('float32-array', 'Float32', 'switch (i % 4) {case 0 (-0.0); case 1 1.5; case 2 (-2.25); case _ 65536.5}'),
        array_family('char-array', 'Char', "if (i % 2 == 0) 'a' else '😀'"),
    ]
    for name, typ, convert in [('nat8-array', 'Nat8', 'Prim.natToNat8(i % 256)'),
                               ('nat16-array', 'Nat16', 'Prim.natToNat16(i % 65536)'),
                               ('nat32-array', 'Nat32', 'Prim.natToNat32(i)'),
                               ('int8-array', 'Int8', 'Prim.intToInt8((i % 256 : Int) - 128)'),
                               ('int16-array', 'Int16', 'Prim.intToInt16((i % 65536 : Int) - 32768)'),
                               ('int32-array', 'Int32', 'Prim.intToInt32((i : Int) - 2048)'),
                               ('int64-array', 'Int64', 'Prim.intToInt64((i : Int) - 2048)')]:
        families.append(array_family(name, typ, convert))

if a.zero_capacity:
    types, support = '', ''
    families = [
        ('null_array', '[Null]', '[]', [(f'null-array-{n}', f'Prim.Array_tabulate<Null>({n}, func(_) {{null}})')
          for n in [1024, 1034, 1035, 4096, 65536]]),
        ('unit_array', '[()]', '[]', [(f'unit-array-{n}', f'Prim.Array_tabulate<()>({n}, func(_) {{()}})')
          for n in [1024, 1036, 1037, 4096, 65536]]),
    ]

cases, configure, variables, methods, check = [], [], [], [], []
def measure(method, statement, size):
    return f'''
  public func {method}() : async Measurement {{
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    {statement};
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = {size}}}
  }};
'''

cases.append({'name': 'control', 'index': 0, 'family': 'control', 'phases': [
    {'label': 'overhead', 'method': 'control', 'kind': 'control', 'require_no_gc': False}]})
configure.append('      case 0 {family := 99};')
methods.append(measure('control', 'mode := 99; output := ""', '0'))
check.append('      case 99 output;')

for family_index, (name, typ, initial, specs) in enumerate(families):
    variables.extend([f'  transient var {name} : {typ} = {initial};',
                      f'  transient var decoded_{name} : ?{typ} = null;'])
    operations = [
      ('candid_encode', f'output := to_candid({name})', 'ordinary_candid', 'output.size()'),
      ('candidx_encode', f'output := candidOk(CandidX.encode({name}))', 'canonical_candid', 'output.size()'),
      ('candid_decode', f'decoded_{name} := ?optionalOk<{typ}>(from_candid(nativeBytes))', 'checked_decode', '2'),
      ('candidx_decode', f'decoded_{name} := ?optionalOk<{typ}>(from_candid(canonicalBytes))', 'checked_decode', '2'),
    ]
    if not a.baseline_only:
        operations += [
          ('icwire_encode', f'output := wireOk<Blob>(ICWire.encode({name}))', 'control', 'output.size()'),
          ('icwire_decode', f'decoded_{name} := ?wireOk<{typ}>(ICWire.decode<{typ}>(wireBytes))', 'checked_decode', '2'),
        ]
    phases = []
    for op_index, (op, statement, kind, size) in enumerate(operations):
        if a.codec != 'all' and not op.startswith(a.codec + '_'):
            continue
        method = f'{name}_{op}'
        methods.append(measure(method, f'mode := {op_index}; {statement}', size))
        if a.codec == 'candidx' and kind == 'canonical_candid':
            kind = 'control'
        phases.append({'label': op, 'method': method, 'kind': kind, 'require_no_gc': False})
    for title, expression in specs:
        index = len(cases)
        native_setup = f'nativeBytes := to_candid({name});' if a.codec in ['all', 'candid'] else ''
        canonical_setup = f'canonicalBytes := candidOk(CandidX.encode({name}));' if a.codec in ['all', 'candidx'] else ''
        configure.append(f'''      case {index} {{ family := {family_index}; {name} := {expression};
        {native_setup} {canonical_setup}
        {'' if a.baseline_only or a.codec not in ['all', 'icwire'] else f'wireBytes := wireOk<Blob>(ICWire.encode({name}));'} }};''')
        cases.append({'name': title, 'index': index, 'family': name, 'phases': phases})
    native_assert = f'ignore optionalOk<{typ}>(from_candid(output))' if typ == 'Null' else f'assert optionalOk<{typ}>(from_candid(output)) == {name}'
    wire_assert = f'ignore wireOk<{typ}>(ICWire.decode<{typ}>(output))' if typ == 'Null' else f'assert wireOk<{typ}>(ICWire.decode<{typ}>(output)) == {name}'
    icwire_check = '' if a.baseline_only or a.codec not in ['all', 'icwire'] else f'''else if (mode == 4) {{
          {wire_assert}; output
        }} '''
    check.append(f'''      case {family_index} {{
        if (mode < 2) {{ {native_assert}; output }}
        {icwire_check}else {{ assert decoded_{name} == ?{name}; "ok" }}
      }};''')

source = f'''// Generated by benchmarks/icwire/generate.py. Fixture setup/checks are outside timing.
import Prim "mo:⛔";
import CandidX "mo:fast/CandidX";
{'' if a.baseline_only else 'import ICWire "mo:fast/ICWire";'}
actor {{
  type Measurement = {{instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat}};
{types}
  func candidOk(value : {{#ok : Blob; #err : Text}}) : Blob {{
    switch value {{case (#ok bytes) bytes; case (#err error) Prim.trap(error)}}
  }};
  func optionalOk<T>(value : ?T) : T {{
    switch value {{case (?v) v; case null Prim.trap("Candid decode failed")}}
  }};
{'' if a.baseline_only else '''  func wireOk<T>(value : {#ok : T; #err : {kind : Text; offset : Nat64}}) : T {
    switch value {case (#ok v) v; case (#err error) Prim.trap(debug_show error)}
  };'''}
{support}
{chr(10).join(variables)}
  transient var family = 0;
  transient var mode = 0;
  transient var nativeBytes : Blob = "";
  transient var canonicalBytes : Blob = "";
  {'' if a.baseline_only else 'transient var wireBytes : Blob = "";'}
  transient var output : Blob = "";
  public func configure(index : Nat) : async () {{
    switch index {{
{chr(10).join(configure)}
      case _ Prim.trap("unknown benchmark")
    }}
  }};
  public func clear() : async () {{
    output := "";
    {' '.join(f'decoded_{name} := null;' for name, *_ in families)}
  }};
  public query func bytesResult() : async Blob {{
    switch family {{
{chr(10).join(check)}
      case _ Prim.trap("unknown family")
    }}
  }};
{chr(10).join(methods)}
}}
'''
if a.memory_probe:
    source = source.replace('outputSize : Nat};', 'outputSize : Nat; memoryBefore : Nat; memoryAfter : Nat; heapBefore : Nat; heapAfter : Nat};')
    source = source.replace('    let started = Prim.performanceCounter(0);',
                            '    let memoryBefore = Prim.rts_memory_size();\n    let heapBefore = Prim.rts_heap_size();\n    let started = Prim.performanceCounter(0);')
    source = source.replace('    let allocatedAfter = Prim.rts_total_allocation();',
                            '    let memoryAfter = Prim.rts_memory_size();\n    let heapAfter = Prim.rts_heap_size();\n    let allocatedAfter = Prim.rts_total_allocation();')
    source = source.replace('{instructions = ended - started;', '{memoryBefore; memoryAfter; heapBefore; heapAfter; instructions = ended - started;')
if a.warm_heap:
    source = source.replace('      case _ Prim.trap("unknown benchmark")\n    }\n  };', '''      case _ Prim.trap("unknown benchmark")
    };
    var warmText = "x";
    var warmDepth = 0;
    while (warmDepth < 23) {warmText := warmText # warmText; warmDepth += 1};
    output := Prim.encodeUtf8(warmText);
    assert output.size() == 8_388_608;
  };''')
if a.codec != 'all':
    import re
    if a.codec != 'candidx':
        source = source.replace('import CandidX "mo:fast/CandidX";\n', '')
        source = re.sub(r'  func candidOk\(.*?\n  \};\n', '', source, flags=re.S)
        source = source.replace('  transient var canonicalBytes : Blob = "";\n', '')
    if a.codec != 'icwire':
        source = source.replace('import ICWire "mo:fast/ICWire";\n', '')
        source = re.sub(r'  func wireOk<T>\(.*?\n  \};\n', '', source, flags=re.S)
        source = source.replace('  transient var wireBytes : Blob = "";\n', '')
    if a.codec != 'candid':
        source = source.replace('  transient var nativeBytes : Blob = "";\n', '')
    if a.codec == 'icwire':
        # With an ICWire-only actor, no native encoder/decoder should contribute
        # code size. Retained-result equality is still checked in the query.
        source = re.sub(r'if \(mode < 2\) \{ (?:assert|ignore) optionalOk<[^\n]+?; output \}\n        else if \(mode == 4\)',
                        'if (mode == 4)', source)
        source = re.sub(r'  func optionalOk<T>\(.*?\n  \};\n', '', source, flags=re.S)
(a.out / 'main.mo').write_text(source)
(a.out / 'cases.json').write_text(json.dumps({
    'suite': 'icwire-zero-capacity' if a.zero_capacity else 'icwire-combined' if a.combined else 'icwire-recursive' if a.recursive else 'icwire-scalars' if a.scalars else 'icwire', 'variant_width': 0, 'variant_payload': 'none',
    'methodology': 'Fresh canister per workload/trial/phase. Configure constructs immutable fixtures and each format input outside timing; four forced GC increments follow. Encode/decode are separate synchronous updates, including success unwrapping and retaining the result. Counter/assignment overhead is included. Synchronous GC is included and reported; end-of-message GC is excluded. Byte counts belong to encode phases; decode replies are a 2-byte correctness marker.' + (' Linear-memory capacity and occupied-heap counters are sampled immediately outside the timed interval.' if a.memory_probe else '') + (' Warm-capacity lane: configure allocates and retains an 8 MiB Blob, then the normal clear call drops it and four forced GC increments run before the measured update. Allocation/page costs within the interval remain included, with no subtraction.' if a.warm_heap else ''),
    'correctness': 'The unmeasured bytesResult query compares every complete decoded value with its independent deterministic fixture; encode phases also decode and compare before returning bytes. CandidX bytes additionally match host canonicalization of ordinary Candid. Schemas mirror Takt Events/child admission and Reactor Batch from their v1 contracts; Rechain is a representative action batch, not an integration benchmark.',
    'cases': cases}, indent=2) + '\n')
print(a.out / 'main.mo')
