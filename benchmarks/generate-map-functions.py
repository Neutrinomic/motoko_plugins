#!/usr/bin/env python3
"""Generate public map API comparisons; construction and populated-map rows differ."""
import argparse
import json
import math
from pathlib import Path


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--sizes', default='1000,10000,100000')
args = parser.parse_args()
sizes = [int(value) for value in args.sizes.split(',')]
if any(size < 32 or size > 100_000 for size in sizes):
    parser.error('sizes must be in 32..100000')
args.out.mkdir(parents=True, exist_ok=True)

# name, public function, Core function/composition, adapter explanation.
workloads = [
    ('get-hit', 'get', 'get', ''),
    ('get-miss', 'get', 'get', ''),
    ('getEntry-hit', 'getEntry', 'get + optional pair',
     'Core.get mapped to the requested key; equivalent for exact Nat64 ordering.'),
    ('containsKey-mixed', 'containsKey', 'containsKey', ''),
    ('add-insert', 'add', 'add', ''),
    ('add-overwrite', 'add', 'add', ''),
    ('swap-hit', 'swap', 'swap', 'Both return the old optional value; this is put-with-old-value semantics.'),
    ('insert-mixed', 'insert', 'insert', ''),
    ('replace-hit', 'replace', 'replace', ''),
    ('replace-miss', 'replace', 'replace', ''),
    ('take-hit', 'take', 'take', ''),
    ('delete-mixed', 'delete', 'delete', ''),
    ('alter-mixed', 'alter', 'get + callback + add/remove',
     'Core has no alter: call callback once after get, then add/remove; unchanged absence keeps the original root.'),
    ('update-mixed', 'update', 'get + callback + add/remove',
     'Same adapter as alter, returning the original optional value.'),
    ('fromIter-sorted', 'fromIter', 'fromIter', ''),
    ('fromIter-shuffled', 'fromIter', 'fromIter', ''),
    ('fromArray-shuffled', 'fromArray', 'fromIter(array.values())',
     'Core has no fromArray; array iterator creation is included in its adapter.'),
    ('entries-create', 'entries', 'entries', ''),
    ('entries-consume', 'entries', 'entries', ''),
    ('reverseEntries-create', 'reverseEntries', 'reverseEntries', ''),
    ('reverseEntries-consume', 'reverseEntries', 'reverseEntries', ''),
    ('entriesFrom-seek16', 'entriesFrom', 'entries + Iter.dropWhile',
     'Core has no seek: ordered iterator scans the prefix, then both consume 16 entries.'),
    ('entriesInRange-seek16', 'entriesInRange', 'entries + Iter.dropWhile + Iter.takeWhile',
     'Core has no bounded seek: scan to lower bound and stop at upper bound; both consume 16 entries.'),
    ('find-first', 'find', 'Iter.find(entries)', 'Ordered scan adapter; predicate matches all keys at or above the threshold.'),
    ('find-middle', 'find', 'Iter.find(entries)', 'Ordered scan adapter; predicate matches all keys at or above the threshold.'),
    ('find-last', 'find', 'Iter.find(entries)', 'Ordered scan adapter; predicate matches all keys at or above the threshold.'),
    ('find-missing', 'find', 'Iter.find(entries)', 'Ordered scan adapter; threshold lies above every key.'),
    ('foldLeft', 'foldLeft', 'foldLeft', ''),
    ('foldRight', 'foldRight', 'foldRight', ''),
    ('map', 'map', 'map', ''),
    ('filterMap', 'filterMap', 'filterMap', ''),
    ('rank', 'rank', 'ordered entries count', 'Core lacks subtree counts; scan ordered entries until the probe key.'),
    ('select', 'select', 'entries + index scan', 'Core lacks rank selection; consume the ordered iterator to the requested index.'),
    ('splitLookup', 'splitLookup', 'entries + add into two maps',
     'Core has no split: one ordered pass reconstructs left/right maps with public add; plugin shares untouched branches.'),
    ('snapshot-create', 'snapshot', 'retain persistent map root',
     'Full-map snapshot only: Core root capture is already persistent; plugin snapshot additionally stores rank/range metadata.'),
    ('replay-create', 'replay', 'entries(retained root)',
     'Full snapshots are prepared before timing; Core replays a retained root with entries.'),
    ('replay-consume', 'replay', 'entries(retained root)',
     'Full snapshots are prepared before timing; both create an iterator and consume it completely.'),
]
names = [item[0] for item in workloads]
points = set(names[:14])
updates = points - {'get-hit', 'get-miss', 'getEntry-hit', 'containsKey-mixed'}
creations = {'entries-create', 'reverseEntries-create', 'snapshot-create', 'replay-create'}
seeks = {'entriesFrom-seek16', 'entriesInRange-seek16'}
full_consumption = {'entries-consume', 'reverseEntries-consume', 'replay-consume'}
builders = {'fromIter-sorted', 'fromIter-shuffled', 'fromArray-shuffled'}
static_functions = {'get-hit': 'getNat64', 'get-miss': 'getNat64',
                    'add-insert': 'addNat64', 'add-overwrite': 'addNat64',
                    'replace-hit': 'replaceNat64', 'replace-miss': 'replaceNat64'}


def repetitions(name, size):
    if name in points:
        return 32
    if name in creations or name in seeks:
        return 4 if size == 100_000 else 8
    if name in ('rank', 'select'):
        return 8
    if name == 'splitLookup':
        return 3 if size == 100_000 else 4
    return 1


cases, configure = [], []
for size in sizes:
    stride = 4051
    while math.gcd(stride, size) != 1:
        stride -= 2
    for name, public, core, adapter in workloads:
        index = len(cases)
        count = repetitions(name, size)
        cases.append({
            'index': index, 'name': f'map-functions-{name}-{size}',
            'family': 'pure-map-functions', 'map_size': size, 'operation': name,
            'public_function': public, 'core_function': core, 'adapter_note': adapter,
            'static_public_function': static_functions.get(name, ''),
            'operations_per_phase': count,
            'workload_kind': 'construction' if name in builders else 'populated-map',
            'unit': ('create cursor and consume 16 entries' if name in seeks else
                     'create cursor and consume full map' if name in full_consumption else
                     'create retained cursor/snapshot' if name in creations else
                     'one public function call'),
            'phases': [{'label': label, 'method': f'bench_{label}_{names.index(name)}',
                        'kind': 'checked_decode', 'require_no_gc': False}
                       for label in (('core', 'plugin_custom', 'plugin_static') if name in static_functions
                                     else ('core', 'plugin_custom'))],
        })
        configure.append(f'case {index} {{ count := {size}; operation := "{name}"; iterations := {count}; stride := {stride} }};')


def body(name, module):
    plugin = module == 'Map'
    input_map = 'pluginInput' if plugin else 'coreInput'
    output_map = 'pluginOutput' if plugin else 'coreOutput'
    history = 'pluginHistory' if plugin else 'coreHistory'
    snapshot = 'preparedSnapshot' if plugin else 'coreInput'
    if name in points:
        key = ('misses[i]' if name in {'get-miss', 'add-insert', 'replace-miss'} else
               'probes[i]' if name.endswith('-mixed') else 'hits[i]')
        call = lambda function, tail='': f'{module}.{function}(tree, compare, {key}{tail})'
        if name in ('get-hit', 'get-miss'):
            action = f'oldValues[i] := {call("get")}'
        elif name == 'getEntry-hit':
            action = f'foundEntries[i] := {call("getEntry")}' if plugin else f'foundEntries[i] := coreGetEntry(tree, {key})'
        elif name == 'containsKey-mixed':
            action = f'flags[i] := {call("containsKey")}'
        elif name in ('add-insert', 'add-overwrite'):
            action = f'tree := {call("add", ", 1000000 + i")}'
        elif name in ('swap-hit', 'replace-hit', 'replace-miss'):
            function = name.split('-')[0]
            action = f'let (next, old) = {call(function, ", 1000000 + i")}; tree := next; oldValues[i] := old'
        elif name == 'insert-mixed':
            action = f'let (next, added) = {call("insert", ", 1000000 + i")}; tree := next; flags[i] := added'
        elif name == 'take-hit':
            action = f'let (next, old) = {call("take")}; tree := next; oldValues[i] := old'
        elif name == 'delete-mixed':
            action = f'let (next, removed) = {call("delete")}; tree := next; flags[i] := removed'
        elif name == 'alter-mixed':
            action = f'tree := {call("alter", ", alterValue")}' if plugin else f'tree := coreUpdate(tree, {key}, alterValue).0'
        else:
            action = (f'let (next, old) = {call("update", ", alterValue")}' if plugin else
                      f'let (next, old) = coreUpdate(tree, {key}, alterValue)') + '; tree := next; oldValues[i] := old'
        capture = f'if (i == 0) {history}[0] := ?tree; if (i == iterations / 2) {history}[1] := ?tree; if (i + 1 == iterations) {history}[2] := ?tree;' if name in updates else ''
        return f'''{'var' if name in updates else 'let'} tree = {input_map}; var i = 0;
    while (i < iterations) {{ {action}; {capture} i += 1 }};
    {output_map} := tree;'''
    if name in builders:
        expression = (f'{module}.fromIter(buildCursor, compare)' if name.startswith('fromIter') else
                      'Map.fromArray(shuffledInput, compare)' if plugin else 'Core.fromIter(shuffledInput.values(), compare)')
        return f'{output_map} := {expression};'
    if name in creations:
        if name == 'snapshot-create':
            return ('var i = 0; while (i < iterations) { snapshotOutputs[i] := ?Map.snapshot(pluginInput); i += 1 };' if plugin else
                    'var i = 0; while (i < iterations) { coreSnapshots[i] := ?coreInput; i += 1 };')
        expression = (f'{module}.entries({input_map})' if name == 'entries-create' else
                      f'{module}.reverseEntries({input_map})' if name == 'reverseEntries-create' else
                      f'Map.replay({snapshot})' if plugin else f'Core.entries({snapshot})')
        return f'var i = 0; while (i < iterations) {{ cursors[i] := ?{expression}; i += 1 }};'
    if name in full_consumption:
        expression = (f'{module}.entries({input_map})' if name == 'entries-consume' else
                      f'{module}.reverseEntries({input_map})' if name == 'reverseEntries-consume' else
                      f'Map.replay({snapshot})' if plugin else f'Core.entries({snapshot})')
        return f'let cursor = {expression}; let (hash, length) = consume(cursor, count); hashes[0] := hash; lengths[0] := length; cursors[0] := ?cursor;'
    if name in seeks:
        if plugin:
            expression = ('Map.entriesFrom(pluginInput, compare, lowerKeys[i])' if name == 'entriesFrom-seek16' else
                          'Map.entriesInRange(pluginInput, compare, lowerBounds[i], upperBounds[i])')
        else:
            expression = 'coreSeek(coreInput, lowerKeys[i], ' + ('null' if name == 'entriesFrom-seek16' else '?upperKeys[i]') + ')'
        return f'''var i = 0; while (i < iterations) {{
      let cursor = {expression}; let (hash, length) = consume(cursor, 16);
      hashes[i] := hash; lengths[i] := length; cursors[i] := ?cursor; i += 1
    }};'''
    if name.startswith('find-'):
        expression = ('Map.find(pluginInput, findPredicate)' if plugin else
                      'Iter.find(Core.entries(coreInput), func(entry : Entry) : Bool { findPredicate(entry.0, entry.1) })')
        return f'foundEntries[0] := {expression};'
    if name in ('foldLeft', 'foldRight'):
        return f'hashes[0] := {module}.{name}({input_map}, hashSeed, {"foldLeftStep" if name == "foldLeft" else "foldRightStep"});'
    if name == 'map':
        return f'{output_map} := {module}.map({input_map}, transform);'
    if name == 'filterMap':
        return f'{output_map} := ' + ('Map.filterMap(pluginInput, transformSome);' if plugin else 'Core.filterMap(coreInput, compare, transformSome);')
    if name == 'rank':
        expression = 'Map.rank(pluginInput, compare, rankKeys[i])' if plugin else 'coreRank(coreInput, rankKeys[i])'
        return f'var i = 0; while (i < iterations) {{ numbers[i] := {expression}; i += 1 }};'
    if name == 'select':
        expression = 'Map.select(pluginInput, ranks[i])' if plugin else 'coreSelect(coreInput, ranks[i])'
        return f'var i = 0; while (i < iterations) {{ foundEntries[i] := {expression}; i += 1 }};'
    if name == 'splitLookup':
        expression = 'Map.splitLookup(pluginInput, compare, rankKeys[i])' if plugin else 'coreSplit(coreInput, rankKeys[i])'
        prefix = 'plugin' if plugin else 'core'
        return f'''var i = 0; while (i < iterations) {{
      let (left, old, right) = {expression};
      {prefix}Left[i] := ?left; {prefix}Right[i] := ?right; foundEntries[i] := old; i += 1
    }};'''
    raise ValueError(name)


methods = []
for index, (name, _, _, _) in enumerate(workloads):
    variants = [('core', 'Core'), ('plugin_custom', 'Map')]
    if name in static_functions:
        variants.append(('plugin_static', 'Map'))
    for label, module in variants:
        code = body(name, module)
        if label == 'plugin_static':
            for function in ('get', 'add', 'replace'):
                code = code.replace(f'Map.{function}(tree, compare, ', f'Map.{function}Nat64(tree, ')
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

source = '''// Generated by benchmarks/generate-map-functions.py.
import Prim "mo:⛔";
import Core "mo:core/pure/Map";
import Iter "mo:core/Iter";
import Map "mo:fast/pure/Map";
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
  transient var active : Nat = 0;
  transient var callbacks : Nat = 0;
  transient var threshold : Nat = 0;
  transient var thresholdKey : Nat64 = keyBase;
  transient var ordinals : [Nat] = [];
  transient var hits : [Nat64] = [];
  transient var misses : [Nat64] = [];
  transient var probes : [Nat64] = [];
  transient var positions : [Nat] = [];
  transient var ranks : [Nat] = [];
  transient var rankKeys : [Nat64] = [];
  transient var lowerKeys : [Nat64] = [];
  transient var upperKeys : [Nat64] = [];
  transient var lowerBounds : [Map.Bound<Nat64>] = [];
  transient var upperBounds : [Map.Bound<Nat64>] = [];
  transient var sortedInput : [Entry] = [];
  transient var shuffledInput : [Entry] = [];
  transient var coreInput : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginInput : Map.Map<Nat64, Nat> = Map.empty();
  transient var coreOutput : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginOutput : Map.Map<Nat64, Nat> = Map.empty();
  transient var coreHistory : [var ?Core.Map<Nat64, Nat>] = [var];
  transient var pluginHistory : [var ?Map.Map<Nat64, Nat>] = [var];
  transient var coreLeft : [var ?Core.Map<Nat64, Nat>] = [var];
  transient var coreRight : [var ?Core.Map<Nat64, Nat>] = [var];
  transient var pluginLeft : [var ?Map.Map<Nat64, Nat>] = [var];
  transient var pluginRight : [var ?Map.Map<Nat64, Nat>] = [var];
  transient var coreSnapshots : [var ?Core.Map<Nat64, Nat>] = [var];
  transient var snapshotOutputs : [var ?Map.EntrySnapshot<Nat64, Nat>] = [var];
  transient var preparedSnapshot : Map.EntrySnapshot<Nat64, Nat> = Map.snapshot(Map.empty());
  transient var oldValues : [var ?Nat] = [var];
  transient var foundEntries : [var ?Entry] = [var];
  transient var flags : [var Bool] = [var];
  transient var numbers : [var Nat] = [var];
  transient var hashes : [var Nat64] = [var];
  transient var lengths : [var Nat] = [var];
  transient var cursors : [var ?Cursor] = [var];
  transient var buildCursor : Cursor = object { public func next() : ?Entry { null } };
  func compare(a : Nat64, b : Nat64) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func key(index : Nat) : Nat64 { keyBase + Prim.natToNat64(index * 2) };
  // Bounded wrapping arithmetic avoids a growing arbitrary-precision accumulator.
  // Include both key and value, retaining order; count is checked independently.
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
    while (i < end) { let ordinal = if (reverse) (end - 1 - (i - start) : Nat) else i;
      hash := mix(hash, key(ordinal), ordinal); i += 1 };
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
  func coreUpdate(tree : Core.Map<Nat64, Nat>, k : Nat64, update : ?Nat -> ?Nat) : (Core.Map<Nat64, Nat>, ?Nat) {
    let old = Core.get(tree, compare, k);
    let next = switch (update(old)) {
      case (?value) Core.add(tree, compare, k, value);
      case null { switch old { case null tree; case _ Core.remove(tree, compare, k) } }
    };
    (next, old)
  };
  func coreSeek(tree : Core.Map<Nat64, Nat>, lower : Nat64, end : ?Nat64) : Cursor {
    let source = Iter.dropWhile(Core.entries(tree), func(entry : Entry) : Bool { entry.0 < lower });
    switch end {
      case null source;
      case (?upper) { Iter.takeWhile(source, func(entry : Entry) : Bool { entry.0 < upper }) }
    }
  };
  func coreRank(tree : Core.Map<Nat64, Nat>, probe : Nat64) : Nat {
    var result = 0;
    label scan for ((k, _) in Core.entries(tree)) { if (k >= probe) break scan; result += 1 };
    result
  };
  func coreSelect(tree : Core.Map<Nat64, Nat>, index : Nat) : ?Entry {
    let cursor = Core.entries(tree); var i = 0;
    while (i < index) { switch (cursor.next()) { case null return null; case _ {} }; i += 1 };
    cursor.next()
  };
  func coreSplit(tree : Core.Map<Nat64, Nat>, probe : Nat64) : (Core.Map<Nat64, Nat>, ?Entry, Core.Map<Nat64, Nat>) {
    var left = Core.empty<Nat64, Nat>(); var right = Core.empty<Nat64, Nat>(); var old : ?Entry = null;
    for ((k, v) in Core.entries(tree)) {
      if (k < probe) left := Core.add(left, compare, k, v)
      else if (k > probe) right := Core.add(right, compare, k, v)
      else old := ?(k, v)
    };
    (left, old, right)
  };
  func alterValue(old : ?Nat) : ?Nat {
    callbacks += 1; ?(switch old { case null 42; case (?value) value + 1 })
  };
  func findPredicate(k : Nat64, _value : Nat) : Bool { callbacks += 1; k >= thresholdKey };
  func foldLeftStep(hash : Nat64, k : Nat64, v : Nat) : Nat64 { callbacks += 1; mix(hash, k, v) };
  func foldRightStep(k : Nat64, v : Nat, hash : Nat64) : Nat64 { callbacks += 1; mix(hash, k, v) };
  func transform(_k : Nat64, v : Nat) : Nat { callbacks += 1; v + 1 };
  func transformSome(_k : Nat64, v : Nat) : ?Nat { callbacks += 1; if (v % 2 == 0) ?(v + 1) else null };

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
    ranks := Prim.Array_tabulate<Nat>(iterations, func(i) { if (iterations == 1) count / 2 else i * (count - 1) / (iterations - 1) });
    rankKeys := Prim.Array_tabulate<Nat64>(iterations, func(i) { key(ranks[i]) });
    lowerKeys := Prim.Array_tabulate<Nat64>(iterations, func(i) { key(positions[i]) });
    upperKeys := Prim.Array_tabulate<Nat64>(iterations, func(i) { key(positions[i] + 16) });
    lowerBounds := Prim.Array_tabulate<Map.Bound<Nat64>>(iterations, func(i) { #inclusive(lowerKeys[i]) });
    upperBounds := Prim.Array_tabulate<Map.Bound<Nat64>>(iterations, func(i) { #exclusive(upperKeys[i]) });
    threshold := switch operation { case "find-first" 0; case "find-middle" (count / 2); case "find-last" (count - 1); case _ count };
    thresholdKey := key(threshold);
    sortedInput := Prim.Array_tabulate<Entry>(count, func(i) { (key(i), i) });
    shuffledInput := Prim.Array_tabulate<Entry>(count, func(i) { let ordinal = i * stride % count; (key(ordinal), ordinal) });
    coreInput := Core.empty(); pluginInput := Map.empty();
    for ((k, v) in shuffledInput.values()) {
      coreInput := Core.add(coreInput, compare, k, v);
      pluginInput := Map.add(pluginInput, compare, k, v)
    };
    assert Core.size(coreInput) == count and Map.size(pluginInput) == count;
    checkSequence(Core.entries(coreInput), 0, count, false);
    checkSequence(Map.entries(pluginInput), 0, count, false);
    Map.assertValid(pluginInput, compare)
  };
  public func clear() : async () {
    callbacks := 0;
    coreOutput := coreInput; pluginOutput := pluginInput;
    coreHistory := Prim.Array_init<?Core.Map<Nat64, Nat>>(3, null);
    pluginHistory := Prim.Array_init<?Map.Map<Nat64, Nat>>(3, null);
    coreLeft := Prim.Array_init<?Core.Map<Nat64, Nat>>(iterations, null);
    coreRight := Prim.Array_init<?Core.Map<Nat64, Nat>>(iterations, null);
    pluginLeft := Prim.Array_init<?Map.Map<Nat64, Nat>>(iterations, null);
    pluginRight := Prim.Array_init<?Map.Map<Nat64, Nat>>(iterations, null);
    coreSnapshots := Prim.Array_init<?Core.Map<Nat64, Nat>>(iterations, null);
    snapshotOutputs := Prim.Array_init<?Map.EntrySnapshot<Nat64, Nat>>(iterations, null);
    oldValues := Prim.Array_init<?Nat>(iterations, null);
    foundEntries := Prim.Array_init<?Entry>(iterations, null);
    flags := Prim.Array_init<Bool>(iterations, false);
    numbers := Prim.Array_init<Nat>(iterations, 0);
    hashes := Prim.Array_init<Nat64>(iterations, hashSeed);
    lengths := Prim.Array_init<Nat>(iterations, 0);
    cursors := Prim.Array_init<?Cursor>(iterations, null);
    preparedSnapshot := Map.snapshot(pluginInput);
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
      };
      slot += 1
    };
    assert cursor.next() == null; assert cursor.next() == null; size
  };
  func checkHistory(index : Nat, expected : [var ?Nat]) {
    if (active == 0) {
      switch (coreHistory[index]) {
        case (?tree) assert checkValues(Core.entries(tree), expected) == Core.size(tree);
        case null assert false
      }
    } else {
      switch (pluginHistory[index]) {
        case (?tree) assert checkValues(Map.entries(tree), expected) == Map.size(tree);
        case null assert false
      }
    }
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
        case "replace-miss" { assert oldValues[i] == null };
        case "take-hit" { assert oldValues[i] == expected[hit]; expected[hit] := null };
        case "delete-mixed" { assert flags[i] == (expected[mixed] != null); expected[mixed] := null };
        case ("alter-mixed" or "update-mixed") {
          if (operation == "update-mixed") assert oldValues[i] == expected[mixed];
          expected[mixed] := ?(switch (expected[mixed]) { case null 42; case (?v) v + 1 })
        };
        case _ assert false
      };
      if (i == 0) checkHistory(0, expected);
      if (i == iterations / 2) checkHistory(1, expected);
      if (i + 1 == iterations) checkHistory(2, expected);
      i += 1
    };
    if (operation == "alter-mixed" or operation == "update-mixed") assert callbacks == iterations else assert callbacks == 0;
    if (active == 0) assert checkValues(Core.entries(coreOutput), expected) == Core.size(coreOutput)
    else { assert checkValues(Map.entries(pluginOutput), expected) == Map.size(pluginOutput); Map.assertValid(pluginOutput, compare) }
  };
  public query func bytesResult() : async Blob {
    // Fresh iterators validate complete original contents after every operation.
    assert Core.size(coreInput) == count and Map.size(pluginInput) == count;
    checkSequence(Core.entries(coreInput), 0, count, false);
    checkSequence(Map.entries(pluginInput), 0, count, false);
    switch operation {
      case ("get-hit" or "get-miss" or "getEntry-hit" or "containsKey-mixed") {
        var i = 0; while (i < iterations) {
          switch operation {
            case "get-hit" { assert oldValues[i] == ?ordinals[i] };
            case "get-miss" { assert oldValues[i] == null };
            case "getEntry-hit" { assert foundEntries[i] == ?(hits[i], ordinals[i]) };
            case _ { assert flags[i] == (i % 2 == 0) }
          }; i += 1
        }; assert callbacks == 0
      };
      case ("add-insert" or "add-overwrite" or "swap-hit" or "insert-mixed" or "replace-hit" or "replace-miss" or "take-hit" or "delete-mixed" or "alter-mixed" or "update-mixed") validateUpdate();
      case ("fromIter-sorted" or "fromIter-shuffled" or "fromArray-shuffled") {
        if (active == 0) { assert Core.size(coreOutput) == count; checkSequence(Core.entries(coreOutput), 0, count, false) }
        else { assert Map.size(pluginOutput) == count; checkSequence(Map.entries(pluginOutput), 0, count, false); Map.assertValid(pluginOutput, compare) };
        if (operation != "fromArray-shuffled") { assert buildCursor.next() == null; assert buildCursor.next() == null }
      };
      case ("entries-create" or "reverseEntries-create" or "replay-create") {
        var i = 0; while (i < iterations) { checkSequence(cursorAt(i), 0, count, operation == "reverseEntries-create"); i += 1 }
      };
      case ("entries-consume" or "reverseEntries-consume" or "replay-consume") {
        assert lengths[0] == count;
        assert hashes[0] == expectedHash(0, count, operation == "reverseEntries-consume");
        assert cursorAt(0).next() == null; assert cursorAt(0).next() == null
      };
      case ("entriesFrom-seek16" or "entriesInRange-seek16") {
        var i = 0; while (i < iterations) {
          assert lengths[i] == 16 and hashes[i] == expectedHash(positions[i], positions[i] + 16, false);
          checkSequence(cursorAt(i), positions[i] + 16, if (operation == "entriesFrom-seek16") count else positions[i] + 16, false);
          i += 1
        }
      };
      case ("find-first" or "find-middle" or "find-last" or "find-missing") {
        assert foundEntries[0] == (if (threshold == count) null else ?(key(threshold), threshold));
        assert callbacks == (if (threshold == count) count else threshold + 1)
      };
      case ("foldLeft" or "foldRight") {
        assert callbacks == count; assert hashes[0] == expectedHash(0, count, operation == "foldRight")
      };
      case ("map" or "filterMap") {
        assert callbacks == count;
        let cursor = if (active == 0) Core.entries(coreOutput) else Map.entries(pluginOutput);
        var n = 0; var i = 0; while (i < count) {
          if (operation == "map" or i % 2 == 0) { assert cursor.next() == ?(key(i), i + 1); n += 1 }; i += 1
        };
        assert cursor.next() == null; assert cursor.next() == null;
        if (active == 0) assert Core.size(coreOutput) == n else { assert Map.size(pluginOutput) == n; Map.assertValid(pluginOutput, compare) }
      };
      case ("rank" or "select") {
        var i = 0; while (i < iterations) {
          if (operation == "rank") assert numbers[i] == ranks[i] else assert foundEntries[i] == ?(key(ranks[i]), ranks[i]); i += 1
        }
      };
      case "splitLookup" {
        var i = 0; while (i < iterations) {
          assert foundEntries[i] == ?(key(ranks[i]), ranks[i]);
          if (active == 0) {
            switch (coreLeft[i], coreRight[i]) {
              case (?left, ?right) {
                assert Core.size(left) == ranks[i] and Core.size(right) == (count - ranks[i] - 1 : Nat);
                checkSequence(Core.entries(left), 0, ranks[i], false); checkSequence(Core.entries(right), ranks[i] + 1, count, false)
              }; case _ assert false
            }
          } else {
            switch (pluginLeft[i], pluginRight[i]) {
              case (?left, ?right) {
                assert Map.size(left) == ranks[i] and Map.size(right) == (count - ranks[i] - 1 : Nat);
                checkSequence(Map.entries(left), 0, ranks[i], false); checkSequence(Map.entries(right), ranks[i] + 1, count, false);
                Map.assertValid(left, compare); Map.assertValid(right, compare)
              }; case _ assert false
            }
          }; i += 1
        }
      };
      case "snapshot-create" {
        var i = 0; while (i < iterations) {
          if (active == 0) {
            switch (coreSnapshots[i]) { case (?root) checkSequence(Core.entries(root), 0, count, false); case null assert false }
          } else {
            switch (snapshotOutputs[i]) {
              case (?view) { checkSequence(Map.replay(view), 0, count, false); checkSequence(Map.replay(view), 0, count, false) };
              case null assert false
            }
          }; i += 1
        }
      };
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
        'core': {'package': 'core', 'version': '2.5.0', 'module': 'pure/Map'},
        'plugin_custom': {'package': 'plugin/pure-map', 'version': 'ABI 1', 'comparison': 'Motoko callback'},
        'plugin_static': {'package': 'plugin/pure-map', 'version': 'ABI 1', 'comparison': 'native Nat64 ordering'},
    },
    'methodology': 'Public function costs on exactly 1000/10000/100000 records by default. Same compiler, actor, boxed Nat64 keys, Nat values, lawful exact-key comparator, and shuffled distinct insertion order. Fresh canister per case/trial; map population, input arrays, output slots, prepared full snapshots and input builder iterators are outside timing. Construction rows separately measure fromIter/fromArray; other rows operate on populated maps. Points perform 32 calls with distinct spread keys; evolving updates retain first/middle/final roots. Contains/insert/delete/alter/update alternate hits and interleaved misses. Iterator creation retains4 cursors at 100k or 8 otherwise, consumed and exhausted only during validation. Iterator consumption measures creation plus full traversal and bounded order-sensitive hash/count, not output array copying. Seek rows create 4/8 cursors at positions spanning the complete rank range and consume 16 entries each. Find rows use the public Map.find with an ordered threshold predicate matching multiple entries where possible, first/middle/last/absent thresholds separately. Rank/select use 8 spread positions; split uses 3/4. Full scans/transforms/builders run once. Raw instruction/allocation/reclamation numbers include common loop, counter, retained-result assignment and checksum work; synchronous reclamation is reported, end-of-message GC excluded. Allocations are cumulative heap bytes, not retained live memory or RSS. Divide batch totals by operations_per_phase for costs per stated workload, not per iterator next. Core missing APIs use only the explicit public compositions documented per case; no complete map conversion or invented plugin API. Full snapshots compare Core root capture/replay via entries with plugin snapshot/replay metadata. Distinct builder inputs avoid Core 2.5 duplicate-size constructor defect.',
    'correctness': 'Checked-result query runs outside timing. It validates complete original maps after every phase, every old-value/Bool result, complete first/middle/final retained update versions and final outputs against an independent ordinal-slot oracle, sizes and plugin AVL invariants. Created cursors and snapshots are consumed in exact expected order and checked for repeatable exhaustion; consumed cursors retain their remaining suffix for exact validation. Timed traversal/folds use a bounded order-sensitive Nat64 checksum plus independent entry/callback count; expected checksum is generated from ordinal bindings outside timing. Split outputs are checked completely. Builder input cursors must be exhausted. Predicate search verifies the earliest matching key and exact predicate-call count. The query returns ok only after checks pass.',
}, indent=2) + '\n')
print(args.out / 'main.mo')
