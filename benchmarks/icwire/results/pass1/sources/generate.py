#!/usr/bin/env python3
"""Generate matched typed codec workloads; construction/checks are not timed."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--baseline-only', action='store_true')
a = p.parse_args()
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
        method = f'{name}_{op}'
        methods.append(measure(method, f'mode := {op_index}; {statement}', size))
        phases.append({'label': op, 'method': method, 'kind': kind, 'require_no_gc': False})
    for title, expression in specs:
        index = len(cases)
        configure.append(f'''      case {index} {{ family := {family_index}; {name} := {expression};
        nativeBytes := to_candid({name}); canonicalBytes := candidOk(CandidX.encode({name}));
        {'' if a.baseline_only else f'wireBytes := wireOk<Blob>(ICWire.encode({name}));'} }};''')
        cases.append({'name': title, 'index': index, 'family': name, 'phases': phases})
    icwire_check = '' if a.baseline_only else f'''else if (mode == 4) {{
          assert wireOk<{typ}>(ICWire.decode<{typ}>(output)) == {name}; output
        }} '''
    check.append(f'''      case {family_index} {{
        if (mode < 2) {{ assert optionalOk<{typ}>(from_candid(output)) == {name}; output }}
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
(a.out / 'main.mo').write_text(source)
(a.out / 'cases.json').write_text(json.dumps({
    'suite': 'icwire', 'variant_width': 0, 'variant_payload': 'none',
    'methodology': 'Fresh canister per workload/trial/phase. Configure constructs immutable fixtures and each format input outside timing; four forced GC increments follow. Encode/decode are separate synchronous updates, including success unwrapping and retaining the result. Counter/assignment overhead is included. Synchronous GC is included and reported; end-of-message GC is excluded. Byte counts belong to encode phases; decode replies are a 2-byte correctness marker.',
    'correctness': 'The unmeasured bytesResult query compares every complete decoded value with its independent deterministic fixture; encode phases also decode and compare before returning bytes. CandidX bytes additionally match host canonicalization of ordinary Candid. Schemas mirror Takt Events/child admission and Reactor Batch from their v1 contracts; Rechain is a representative action batch, not an integration benchmark.',
    'cases': cases}, indent=2) + '\n')
print(a.out / 'main.mo')
