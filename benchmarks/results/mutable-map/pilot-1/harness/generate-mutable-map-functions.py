#!/usr/bin/env python3
"""Generate checked mutable-map API comparisons against mo:core/Map 2.5.0."""
import argparse
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--sizes', default='1000,10000,100000')
parser.add_argument('--operations', help='Comma-separated subset; default is the complete matrix')
args = parser.parse_args()
sizes = [int(value) for value in args.sizes.split(',')]
if not sizes or len(set(sizes)) != len(sizes) or any(size < 32 or size > 100_000 for size in sizes):
    parser.error('sizes must be unique values in 32..100000')

points = ('get-hit', 'get-miss', 'getEntry-hit', 'containsKey-mixed',
          'add-insert', 'add-overwrite', 'insert-mixed', 'swap-hit',
          'replace-hit', 'replace-miss', 'remove-hit', 'remove-miss',
          'delete-hit', 'delete-miss', 'take-hit', 'take-miss')
updates = set(points[4:])
builders = ('fromIter-sorted', 'fromIter-shuffled', 'fromArray-shuffled', 'fromVarArray-shuffled')
creations = ('entries-create', 'reverseEntries-create')
consumption = ('entries-consume', 'reverseEntries-consume')
seeks = ('entriesFrom-seek16', 'reverseEntriesFrom-seek16')
workloads = list(points + builders + creations + consumption + seeks + (
    'find-first', 'find-middle', 'find-last', 'find-missing',
    'foldLeft', 'foldRight', 'clone', 'clear', 'map', 'filter', 'filterMap',
    'toArray', 'toVarArray', 'forEach', 'all-true', 'any-false',
    'size', 'isEmpty', 'minEntry', 'maxEntry'))
static_functions = {'get-hit': 'getNat64', 'get-miss': 'getNat64',
                    'add-insert': 'addNat64', 'add-overwrite': 'addNat64',
                    'replace-hit': 'replaceNat64', 'replace-miss': 'replaceNat64',
                    'remove-hit': 'removeNat64', 'remove-miss': 'removeNat64'}
if args.operations:
    selected = args.operations.split(',')
    if len(set(selected)) != len(selected) or not set(selected) <= set(workloads):
        parser.error(f'operations must be unique and selected from {workloads}')
    workloads = [name for name in workloads if name in selected]
args.out.mkdir(parents=True, exist_ok=True)


def repetitions(name, size):
    if name in points or name in ('size', 'isEmpty', 'minEntry', 'maxEntry'):
        return 32
    if name in creations or name in seeks:
        return 4 if size == 100_000 else 8
    return 1


cases, configure = [], []
for size in sizes:
    stride = 4051
    while math.gcd(stride, size) != 1:
        stride -= 2
    for method_index, name in enumerate(workloads):
        public = name.split('-')[0]
        core = public
        adapter = ''
        if public == 'getEntry':
            core = 'get + optional pair'
            adapter = 'Core.get mapped to the requested key; exact Nat64 key ordering makes keys equivalent.'
        elif public == 'find':
            core = 'Iter.find(entries)'
            adapter = 'Ordered predicate search; Core has no direct find function.'
        count = repetitions(name, size)
        cases.append({
            'index': len(cases), 'name': f'mutable-map-{name}-{size}',
            'family': 'mutable-map-functions', 'map_size': size, 'operation': name,
            'public_function': public, 'core_function': core, 'adapter_note': adapter,
            'static_public_function': static_functions.get(name, ''),
            'operations_per_phase': count,
            'workload_kind': 'construction' if name in builders else 'populated-map',
            'unit': ('create cursor and consume 16 entries' if name in seeks else
                     'create cursor and consume full map' if name in consumption else
                     'create retained cursor' if name in creations else 'one public function call'),
            'phases': [{'label': label, 'method': f'bench_{label}_{method_index}',
                        'kind': 'checked_decode', 'require_no_gc': False}
                       for label in (('core', 'plugin_custom', 'plugin_static') if name in static_functions
                                     else ('core', 'plugin_custom'))],
        })
        configure.append(f'case {len(cases) - 1} {{ count := {size}; operation := "{name}"; iterations := {count}; stride := {stride}; construction := {str(name in builders).lower()} }};')


def body(name, module):
    plugin = module == 'Map'
    tree = 'pluginInput' if plugin else 'coreInput'
    output = 'pluginOutput' if plugin else 'coreOutput'
    if name in points:
        key = ('misses[i]' if name.endswith('-miss') or name == 'add-insert' else
               'probes[i]' if name.endswith('-mixed') else 'hits[i]')
        public = name.split('-')[0]
        call = f'{module}.{public}(tree, compare, {key}'
        if public in ('add', 'insert', 'swap', 'replace'):
            call += ', 1000000 + i'
        call += ')'
        if public == 'getEntry':
            action = f'foundEntries[i] := {call}' if plugin else f'foundEntries[i] := coreGetEntry(tree, {key})'
        elif public in ('get', 'swap', 'replace', 'take'):
            action = f'oldValues[i] := {call}'
        elif public in ('containsKey', 'insert', 'delete'):
            action = f'flags[i] := {call}'
        else:
            action = call
        return f'let tree = {tree}; var i = 0; while (i < iterations) {{ {action}; i += 1 }};'
    if name in builders:
        if name.startswith('fromIter'):
            expression = f'{module}.fromIter(buildCursor, compare)'
        elif name.startswith('fromVarArray'):
            expression = f'{module}.fromVarArray(varInput, compare)'
        else:
            expression = f'{module}.fromArray(shuffledInput, compare)'
        return f'{output} := {expression};'
    if name in creations:
        function = name.split('-')[0]
        return f'var i = 0; while (i < iterations) {{ cursors[i] := ?{module}.{function}({tree}); i += 1 }};'
    if name in consumption:
        function = name.split('-')[0]
        return f'let cursor = {module}.{function}({tree}); let (hash, length) = consume(cursor, count); hashes[0] := hash; lengths[0] := length; cursors[0] := ?cursor;'
    if name in seeks:
        function = name.split('-')[0]
        return f'''var i = 0; while (i < iterations) {{
      let cursor = {module}.{function}({tree}, compare, seekKeys[i]);
      let (hash, length) = consume(cursor, 16); hashes[i] := hash; lengths[i] := length;
      cursors[i] := ?cursor; i += 1
    }};'''
    if name.startswith('find-'):
        expression = f'Map.find({tree}, findPredicate)' if plugin else f'Iter.find(Core.entries({tree}), func(entry : Entry) : Bool {{ findPredicate(entry.0, entry.1) }})'
        return f'foundEntries[0] := {expression};'
    if name in ('foldLeft', 'foldRight'):
        return f'hashes[0] := {module}.{name}({tree}, hashSeed, {"foldLeftStep" if name == "foldLeft" else "foldRightStep"});'
    if name in ('clone', 'map', 'filter', 'filterMap'):
        tail = {'clone': '', 'map': ', transform', 'filter': ', compare, keep', 'filterMap': ', compare, transformSome'}[name]
        return f'{output} := {module}.{name}({tree}{tail});'
    if name == 'clear':
        return f'{module}.clear({tree});'
    if name == 'toArray':
        return f'arrayOutput := {module}.toArray({tree});'
    if name == 'toVarArray':
        return f'varOutput := {module}.toVarArray({tree});'
    if name == 'forEach':
        return f'{module}.forEach({tree}, visit);'
    if name in ('all-true', 'any-false'):
        return f'flags[0] := {module}.{name.split("-")[0]}({tree}, {"alwaysTrue" if name == "all-true" else "alwaysFalse"});'
    target = 'numbers' if name == 'size' else 'flags' if name == 'isEmpty' else 'foundEntries'
    return f'var i = 0; while (i < iterations) {{ {target}[i] := {module}.{name}({tree}); i += 1 }};'


methods = []
for index, name in enumerate(workloads):
    variants = [('core', 'Core'), ('plugin_custom', 'Map')]
    if name in static_functions:
        variants.append(('plugin_static', 'Map'))
    for label, module in variants:
        code = body(name, module)
        if label == 'plugin_static':
            function = name.split('-')[0]
            code = code.replace(f'Map.{function}(tree, compare, ', f'Map.{static_functions[name]}(tree, ')
        methods.append(f'''
  public func bench_{label}_{index}() : async Measurement {{
    assert operation == "{name}";
    active := {0 if module == 'Core' else 1};
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    {code}
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 2}}
  }};
''')

source = '''// Generated by benchmarks/generate-mutable-map-functions.py.
import Prim "mo:⛔";
import Core "mo:core/Map";
import Iter "mo:core/Iter";
import Map "mo:mutable-map/Map";
actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  type Entry = (Nat64, Nat);
  type Cursor = {next : () -> ?Entry};
  transient let keyBase : Nat64 = 9223372036854775808;
  transient let hashSeed : Nat64 = 2166136261;
  transient var count : Nat = 0;
  transient var iterations : Nat = 0;
  transient var stride : Nat = 0;
  transient var operation : Text = "";
  transient var construction : Bool = false;
  transient var active : Nat = 0;
  transient var callbacks : Nat = 0;
  transient var threshold : Nat = 0;
  transient var thresholdKey : Nat64 = keyBase;
  transient var ordinals : [Nat] = [];
  transient var hits : [Nat64] = [];
  transient var misses : [Nat64] = [];
  transient var probes : [Nat64] = [];
  transient var positions : [Nat] = [];
  transient var seekKeys : [Nat64] = [];
  transient var sortedInput : [Entry] = [];
  transient var shuffledInput : [Entry] = [];
  transient var varInput : [var Entry] = [var];
  transient var coreSeed : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginSeed : Map.Map<Nat64, Nat> = Map.empty();
  transient var coreInput : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginInput : Map.Map<Nat64, Nat> = Map.empty();
  transient var coreOutput : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginOutput : Map.Map<Nat64, Nat> = Map.empty();
  transient var arrayOutput : [Entry] = [];
  transient var varOutput : [var Entry] = [var];
  transient var oldValues : [var ?Nat] = [var];
  transient var foundEntries : [var ?Entry] = [var];
  transient var flags : [var Bool] = [var];
  transient var numbers : [var Nat] = [var];
  transient var hashes : [var Nat64] = [var];
  transient var lengths : [var Nat] = [var];
  transient var cursors : [var ?Cursor] = [var];
  transient var buildCursor : Cursor = object { public func next() : ?Entry { null } };
  func compare(a : Nat64, b : Nat64) : {#less; #equal; #greater} {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func key(index : Nat) : Nat64 { keyBase + Prim.natToNat64(index * 2) };
  func mix(hash : Nat64, k : Nat64, value : Nat) : Nat64 {
    ((hash *% 65599) ^ k ^ (Prim.natToNat64(value) *% 257)) & 4294967295
  };
  func consume(cursor : Cursor, limit : Nat) : (Nat64, Nat) {
    var hash = hashSeed; var n = 0;
    label scan while (n < limit) {
      switch (cursor.next()) {
        case null { break scan };
        case (?(k, v)) { hash := mix(hash, k, v); n += 1 }
      }
    };
    (hash, n)
  };
  func expectedHash(start : Nat, end : Nat, reverse : Bool) : Nat64 {
    var hash = hashSeed; var i = start;
    while (i < end) {
      let ordinal = if (reverse) (end - 1 - (i - start) : Nat) else i;
      hash := mix(hash, key(ordinal), ordinal); i += 1
    };
    hash
  };
  func checkSequence(cursor : Cursor, start : Nat, end : Nat, reverse : Bool) {
    var i = start;
    while (i < end) {
      let ordinal = if (reverse) (end - 1 - (i - start) : Nat) else i;
      assert cursor.next() == ?(key(ordinal), ordinal); i += 1
    };
    assert cursor.next() == null; assert cursor.next() == null
  };
  func coreGetEntry(tree : Core.Map<Nat64, Nat>, k : Nat64) : ?Entry {
    switch (Core.get(tree, compare, k)) { case null null; case (?v) ?(k, v) }
  };
  func findPredicate(k : Nat64, _value : Nat) : Bool { callbacks += 1; k >= thresholdKey };
  func foldLeftStep(hash : Nat64, k : Nat64, v : Nat) : Nat64 { callbacks += 1; mix(hash, k, v) };
  func foldRightStep(k : Nat64, v : Nat, hash : Nat64) : Nat64 { callbacks += 1; mix(hash, k, v) };
  func transform(_k : Nat64, v : Nat) : Nat { callbacks += 1; v + 1 };
  func keep(_k : Nat64, v : Nat) : Bool { callbacks += 1; v % 2 == 0 };
  func transformSome(_k : Nat64, v : Nat) : ?Nat { callbacks += 1; if (v % 2 == 0) ?(v + 1) else null };
  func visit(k : Nat64, v : Nat) { callbacks += 1; hashes[0] := mix(hashes[0], k, v) };
  func alwaysTrue(_k : Nat64, _v : Nat) : Bool { callbacks += 1; true };
  func alwaysFalse(_k : Nat64, _v : Nat) : Bool { callbacks += 1; false };

  public func configure(index : Nat) : async () {
    switch index {
CONFIGURE
      case _ Prim.trap("unknown workload")
    };
    ordinals := Prim.Array_tabulate<Nat>(iterations, func(i) { ((i * 13) % iterations) * count / iterations });
    hits := Prim.Array_tabulate<Nat64>(iterations, func(i) { key(ordinals[i]) });
    misses := Prim.Array_tabulate<Nat64>(iterations, func(i) { hits[i] + 1 });
    probes := Prim.Array_tabulate<Nat64>(iterations, func(i) { if (i % 2 == 0) hits[i] else misses[i] });
    positions := Prim.Array_tabulate<Nat>(iterations, func(i) { if (iterations == 1) count / 2 else i * (count - 16) / (iterations - 1) });
    seekKeys := Prim.Array_tabulate<Nat64>(iterations, func(i) { key(positions[i] + (if (operation == "reverseEntriesFrom-seek16") 15 else 0)) });
    threshold := switch operation { case "find-first" 0; case "find-middle" (count / 2); case "find-last" (count - 1); case _ count };
    thresholdKey := key(threshold);
    sortedInput := Prim.Array_tabulate<Entry>(count, func(i) { (key(i), i) });
    shuffledInput := Prim.Array_tabulate<Entry>(count, func(i) { let ordinal = i * stride % count; (key(ordinal), ordinal) });
    varInput := Prim.Array_tabulateVar<Entry>(count, func(i) { shuffledInput[i] });
    coreSeed := Core.empty(); pluginSeed := Map.empty();
    if (not construction) {
      for ((k, v) in shuffledInput.values()) {
        Core.add(coreSeed, compare, k, v); Map.add(pluginSeed, compare, k, v)
      };
      assert Core.size(coreSeed) == count and Map.size(pluginSeed) == count;
      checkSequence(Core.entries(coreSeed), 0, count, false);
      checkSequence(Map.entries(pluginSeed), 0, count, false);
      Core.assertValid(coreSeed, compare); Map.assertValid(pluginSeed, compare)
    }
  };
  public func clear() : async () {
    callbacks := 0;
    // Clone both seeds before every phase: measured mutations never carry over.
    coreInput := Core.clone(coreSeed); pluginInput := Map.clone(pluginSeed);
    coreOutput := Core.empty(); pluginOutput := Map.empty();
    arrayOutput := []; varOutput := [var];
    oldValues := Prim.Array_init<?Nat>(iterations, null);
    foundEntries := Prim.Array_init<?Entry>(iterations, null);
    flags := Prim.Array_init<Bool>(iterations, false);
    numbers := Prim.Array_init<Nat>(iterations, 0);
    hashes := Prim.Array_init<Nat64>(iterations, hashSeed);
    lengths := Prim.Array_init<Nat>(iterations, 0);
    cursors := Prim.Array_init<?Cursor>(iterations, null);
    buildCursor := (if (operation == "fromIter-sorted") sortedInput else shuffledInput).values()
  };
  func cursorAt(index : Nat) : Cursor {
    switch (cursors[index]) { case (?cursor) cursor; case null Prim.trap("missing retained cursor") }
  };
  func checkValues(cursor : Cursor, expected : [var ?Nat]) : Nat {
    var size = 0; var slot = 0;
    while (slot < expected.size()) {
      switch (expected[slot]) {
        case null {};
        case (?value) { assert cursor.next() == ?(keyBase + Prim.natToNat64(slot), value); size += 1 }
      }; slot += 1
    };
    assert cursor.next() == null; assert cursor.next() == null; size
  };
  func validateUpdate() {
    let expected = Prim.Array_tabulateVar<?Nat>(count * 2, func(i) { if (i % 2 == 0) ?(i / 2) else null });
    var i = 0;
    while (i < iterations) {
      let hit = ordinals[i] * 2;
      let mixed = if (i % 2 == 0) hit else hit + 1;
      switch operation {
        case "add-insert" { expected[hit + 1] := ?(1000000 + i) };
        case ("add-overwrite" or "swap-hit" or "replace-hit") {
          if (operation != "add-overwrite") assert oldValues[i] == expected[hit];
          expected[hit] := ?(1000000 + i)
        };
        case "insert-mixed" { assert flags[i] == (expected[mixed] == null); expected[mixed] := ?(1000000 + i) };
        case ("replace-miss" or "take-miss") { assert oldValues[i] == null };
        case "take-hit" { assert oldValues[i] == expected[hit]; expected[hit] := null };
        case "delete-hit" { assert flags[i]; expected[hit] := null };
        case "delete-miss" { assert not flags[i] };
        case "remove-hit" { expected[hit] := null };
        case "remove-miss" {};
        case _ assert false
      }; i += 1
    };
    assert callbacks == 0;
    if (active == 0) { assert checkValues(Core.entries(coreInput), expected) == Core.size(coreInput); Core.assertValid(coreInput, compare) }
    else { assert checkValues(Map.entries(pluginInput), expected) == Map.size(pluginInput); Map.assertValid(pluginInput, compare) }
  };
  public query func bytesResult() : async Blob {
    // Check complete immutable seed bindings to detect accidental clone aliasing.
    let seedSize = if (construction) 0 else count;
    assert Core.size(coreSeed) == seedSize and Map.size(pluginSeed) == seedSize;
    checkSequence(Core.entries(coreSeed), 0, seedSize, false);
    checkSequence(Map.entries(pluginSeed), 0, seedSize, false);
    switch operation {
      case ("add-insert" or "add-overwrite" or "swap-hit" or "insert-mixed" or "replace-hit" or "replace-miss" or "take-hit" or "take-miss" or "delete-hit" or "delete-miss" or "remove-hit" or "remove-miss" or "clear") {};
      case _ {
        if (active == 0) { assert Core.size(coreInput) == seedSize; checkSequence(Core.entries(coreInput), 0, seedSize, false); Core.assertValid(coreInput, compare) }
        else { assert Map.size(pluginInput) == seedSize; checkSequence(Map.entries(pluginInput), 0, seedSize, false); Map.assertValid(pluginInput, compare) }
      }
    };
    switch operation {
      case ("get-hit" or "get-miss" or "getEntry-hit" or "containsKey-mixed" or "size" or "isEmpty" or "minEntry" or "maxEntry") {
        var i = 0; while (i < iterations) {
          switch operation {
            case "get-hit" { assert oldValues[i] == ?ordinals[i] };
            case "get-miss" { assert oldValues[i] == null };
            case "getEntry-hit" { assert foundEntries[i] == ?(hits[i], ordinals[i]) };
            case "containsKey-mixed" { assert flags[i] == (i % 2 == 0) };
            case "size" { assert numbers[i] == count };
            case "isEmpty" { assert not flags[i] };
            case "minEntry" { assert foundEntries[i] == ?(key(0), 0) };
            case _ { assert foundEntries[i] == ?(key(count - 1), count - 1) }
          }; i += 1
        }; assert callbacks == 0
      };
      case ("add-insert" or "add-overwrite" or "swap-hit" or "insert-mixed" or "replace-hit" or "replace-miss" or "take-hit" or "take-miss" or "delete-hit" or "delete-miss" or "remove-hit" or "remove-miss") validateUpdate();
      case ("fromIter-sorted" or "fromIter-shuffled" or "fromArray-shuffled" or "fromVarArray-shuffled" or "clone") {
        if (active == 0) { assert Core.size(coreOutput) == count; checkSequence(Core.entries(coreOutput), 0, count, false); Core.assertValid(coreOutput, compare) }
        else { assert Map.size(pluginOutput) == count; checkSequence(Map.entries(pluginOutput), 0, count, false); Map.assertValid(pluginOutput, compare) };
        if (operation == "fromIter-sorted" or operation == "fromIter-shuffled") { assert buildCursor.next() == null; assert buildCursor.next() == null };
        if (operation == "clone") {
          if (active == 0) { Core.add(coreOutput, compare, key(0), count); assert Core.get(coreInput, compare, key(0)) == ?0 }
          else { Map.add(pluginOutput, compare, key(0), count); assert Map.get(pluginInput, compare, key(0)) == ?0 }
        }
      };
      case "clear" {
        if (active == 0) { assert Core.size(coreInput) == 0 and Core.isEmpty(coreInput); assert Core.entries(coreInput).next() == null; Core.assertValid(coreInput, compare) }
        else { assert Map.size(pluginInput) == 0 and Map.isEmpty(pluginInput); assert Map.entries(pluginInput).next() == null; Map.assertValid(pluginInput, compare) }
      };
      case ("entries-create" or "reverseEntries-create") {
        var i = 0; while (i < iterations) { checkSequence(cursorAt(i), 0, count, operation == "reverseEntries-create"); i += 1 }
      };
      case ("entries-consume" or "reverseEntries-consume") {
        assert lengths[0] == count; assert hashes[0] == expectedHash(0, count, operation == "reverseEntries-consume");
        assert cursorAt(0).next() == null; assert cursorAt(0).next() == null
      };
      case ("entriesFrom-seek16" or "reverseEntriesFrom-seek16") {
        var i = 0; while (i < iterations) {
          let reverse = operation == "reverseEntriesFrom-seek16";
          assert lengths[i] == 16 and hashes[i] == expectedHash(positions[i], positions[i] + 16, reverse);
          if (reverse) checkSequence(cursorAt(i), 0, positions[i], true)
          else checkSequence(cursorAt(i), positions[i] + 16, count, false);
          i += 1
        }
      };
      case ("find-first" or "find-middle" or "find-last" or "find-missing") {
        assert foundEntries[0] == (if (threshold == count) null else ?(key(threshold), threshold));
        assert callbacks == (if (threshold == count) count else threshold + 1)
      };
      case ("foldLeft" or "foldRight" or "forEach") {
        assert callbacks == count; assert hashes[0] == expectedHash(0, count, operation == "foldRight")
      };
      case ("all-true" or "any-false") { assert callbacks == count; assert flags[0] == (operation == "all-true") };
      case ("map" or "filter" or "filterMap") {
        assert callbacks == count;
        let cursor = if (active == 0) Core.entries(coreOutput) else Map.entries(pluginOutput);
        var n = 0; var i = 0; while (i < count) {
          if (operation == "map" or i % 2 == 0) {
            assert cursor.next() == ?(key(i), if (operation == "filter") i else i + 1); n += 1
          }; i += 1
        };
        assert cursor.next() == null; assert cursor.next() == null;
        if (active == 0) { assert Core.size(coreOutput) == n; Core.assertValid(coreOutput, compare) }
        else { assert Map.size(pluginOutput) == n; Map.assertValid(pluginOutput, compare) }
      };
      case "toArray" { assert arrayOutput == sortedInput };
      case "toVarArray" { assert varOutput.size() == count; var i = 0; while (i < count) { assert varOutput[i] == sortedInput[i]; i += 1 } };
      case _ assert false
    };
    "ok"
  };
METHODS
}
'''.replace('CONFIGURE', '\n'.join(configure)).replace('METHODS', '\n'.join(methods))
(args.out / 'main.mo').write_text(source)
(args.out / 'cases.json').write_text(json.dumps({
    'cases': cases,
    'implementations': {
        'core': {'package': 'core', 'version': '2.5.0', 'module': 'Map'},
        'plugin_custom': {'package': 'plugin/mutable-map', 'version': 'ABI 1', 'comparison': 'Motoko callback'},
        'plugin_static': {'package': 'plugin/mutable-map', 'version': 'ABI 1', 'comparison': 'native Nat64 ordering'},
    },
    'methodology': 'Fresh canister per workload/trial. Same compiler, boxed Nat64 keys above 2^63, Nat values, exact-key comparator and distinct shuffled insertion sequence. Populated-map seeds are built by repeated add outside timing; before each phase both implementations clone their seed outside timing, then four forced GC increments run. Construction cases have empty seeds and time only the public constructor on prepared arrays/iterators. Updates mutate their fresh input map, retaining old-value/Bool results; each phase starts from the same initial bindings. Point operations batch 32 distinct spread keys. Insert/contains alternate hits and interleaved misses; other hit/miss rows are separate. Cursor creation retains 4 cursors at 100k or 8 otherwise; checked consumption is outside timing. Full consumption includes cursor creation and an order-sensitive bounded hash plus count. Seeks create 4/8 cursors spanning the key range and consume 16 entries each. Find thresholds are first/middle/last/absent and validate exact predicate counts. Full scans/transforms/clone/clear/builders run once. Raw counters include common loop, retained-result assignment and checksum work. Allocation is cumulative allocated bytes, not peak/live heap or RSS; synchronous reclaimed bytes are reported and end-of-message GC is excluded. Divide batch totals by operations_per_phase for the stated workload, never per iterator next. Core baseline is mutable mo:core/Map 2.5.0; only find/getEntry use the explicitly listed adapters. Shuffled means a deterministic coprime-stride permutation, not a claim about uniformly random permutations.',
    'correctness': 'The checked-result query runs outside timing and returns ok only after independent ordinal bindings, complete original seed contents, update old-value/Bool results, final map contents/sizes and balanced-tree invariants pass. Seed checks detect clone aliasing after measured mutation. Clone results are mutated outside timing to verify input independence. Iterator outputs are checked in exact order with repeated exhaustion; timed full scans/folds use an independent order-sensitive checksum and count. Find validates earliest matching entry and exact predicate count. Constructors and transforms validate complete entries and invariants. Both phases use the same oracle; failures are retained by the shared runner and rejected by the summary validator.',
}, indent=2) + '\n')
print(args.out / 'main.mo')
