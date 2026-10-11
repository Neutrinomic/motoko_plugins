#!/usr/bin/env python3
"""Generate pure-map/Core comparisons with setup and full checks outside timing."""
import argparse
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--sizes', default='16,256,4096,65536')
parser.add_argument('--operations', default='get-hit,get-miss,insert,overwrite,replace-miss,remove-hit,remove-miss,retained-overwrite')
parser.add_argument('--iterations', type=int, default=64)
args = parser.parse_args()
sizes = [int(value) for value in args.sizes.split(',')]
operations = args.operations.split(',')
allowed = ['get-hit', 'get-miss', 'insert', 'overwrite', 'replace-miss', 'remove-hit', 'remove-miss', 'retained-overwrite',
           'bulk-sorted', 'scan', 'range', 'filter-all', 'filter-half', 'union-small', 'intersection-small', 'difference-small']
if any(value < 1 or value > 1_048_576 for value in sizes):
    parser.error('sizes must be in 1..1048576')
if not 1 <= args.iterations <= 4096:
    parser.error('iterations must be in 1..4096')
if any(value not in allowed for value in operations):
    parser.error('invalid operation')
args.out.mkdir(parents=True, exist_ok=True)
cases = []
configure = []
for count in sizes:
    for operation in operations:
        index = len(cases)
        repetitions = (1 if allowed.index(operation) >= 8 else
                       min(args.iterations, 8) if operation == 'retained-overwrite' else args.iterations)
        stride = 4051
        while math.gcd(stride, count) != 1:
            stride -= 2
        cases.append({
            'index': index, 'name': f'map-{operation}-{count}', 'family': 'pure-map',
            'map_size': count, 'operation': operation, 'operations_per_phase': repetitions,
            'phases': [
                {'label': label, 'method': f'bench_{label}', 'kind': 'checked_decode',
                 'require_no_gc': False}
                for label in (('core', 'plugin_custom') if allowed.index(operation) >= 8
                              else ('core', 'plugin_custom', 'plugin_static'))
            ],
        })
        configure.append(f'case {index} {{ count := {count}; operation := {allowed.index(operation)}; iterations := {repetitions}; stride := {stride} }};')


def measure(label, module, input_name, output_name, history_name):
    if label == 'core':
        bulk_operations = '''
        case 8 { tree := Core.fromIter(sortedInput.values(), compare) };
        case 9 { for ((_, value) in Core.entries(tree)) sum += value };
        case 10 {
          label scan for ((key, value) in Core.entries(tree)) {
            if (key >= rangeEnd) break scan;
            if (key >= rangeStart) sum += value;
          }
        };
        case 11 { tree := Core.filter(coreInput, compare, func(_ : Nat64, _ : Nat) : Bool { true }) };
        case 12 { tree := Core.filter(coreInput, compare, func(_ : Nat64, value : Nat) : Bool { value % 2 == 0 }) };
        case 13 {
          tree := Core.foldLeft(coreRight, coreInput, func(acc : Core.Map<Nat64, Nat>, key : Nat64, value : Nat) : Core.Map<Nat64, Nat> {
            Core.add(acc, compare, key, value)
          })
        };
        case 14 {
          // Iterate the small input, avoiding an O(n) scan of the larger map.
          tree := Core.foldLeft(coreRight, Core.empty<Nat64, Nat>(), func(acc : Core.Map<Nat64, Nat>, key : Nat64, _ : Nat) : Core.Map<Nat64, Nat> {
            switch (Core.get(coreInput, compare, key)) { case null acc; case (?value) Core.add(acc, compare, key, value) }
          })
        };
        case 15 {
          tree := Core.foldLeft(coreRight, coreInput, func(acc : Core.Map<Nat64, Nat>, key : Nat64, _ : Nat) : Core.Map<Nat64, Nat> {
            // Avoid the known absent-remove allocation cost in a composition.
            if (Core.containsKey(acc, compare, key)) Core.remove(acc, compare, key) else acc
          })
        };
'''
    else:
        bulk_operations = '''
        case 8 { tree := Map.fromSortedDistinctArray(sortedInput, compare) };
        case 9 { for ((_, value) in Map.entries(tree)) sum += value };
        case 10 { for ((_, value) in Map.entriesInRange(tree, compare, #inclusive rangeStart, #exclusive rangeEnd)) sum += value };
        case 11 { tree := Map.filter(pluginInput, func(_ : Nat64, _ : Nat) : Bool { true }) };
        case 12 { tree := Map.filter(pluginInput, func(_ : Nat64, value : Nat) : Bool { value % 2 == 0 }) };
        case 13 { tree := Map.union(pluginInput, compare, pluginRight) };
        case 14 { tree := Map.intersection(pluginInput, compare, pluginRight) };
        case 15 { tree := Map.difference(pluginInput, compare, pluginRight) };
'''
    method = f'''
  public func bench_{label}() : async Measurement {{
    active := {0 if label == 'core' else 1};
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    var i = 0;
    var tree = {input_name};
    var sum = 0;
    while (i < iterations) {{
      switch operation {{
        case 0 {{ switch ({module}.get(tree, compare, hits[i])) {{ case (?value) sum += value; case null Prim.trap("missing hit") }} }};
        case 1 {{ assert {module}.get(tree, compare, misses[i]) == null }};
        case 2 {{ tree := {module}.add({input_name}, compare, misses[i], i) }};
        case 3 {{ tree := {module}.add(tree, compare, hits[i], count + i) }};
        case 4 {{ let (next, old) = {module}.replace(tree, compare, misses[i], i); assert old == null; tree := next }};
        case 5 {{ tree := {module}.remove({input_name}, compare, hits[i]) }};
        case 6 {{ tree := {module}.remove(tree, compare, misses[i]) }};
        case 7 {{ tree := {module}.add(tree, compare, hits[i], count + i); {history_name}[i] := ?tree }};
        {bulk_operations}
        case _ Prim.trap("unknown operation");
      }};
      i += 1;
    }};
    {output_name} := tree;
    checksum := sum;
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {{ instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
       reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 2 }}
  }};
'''
    if label == 'plugin_static':
        for name in ('get', 'add', 'remove', 'replace'):
            for tree in ('tree', input_name):
                method = method.replace(f'Map.{name}({tree}, compare, ',
                                        f'Map.{name}Nat64({tree}, ')
    return method


source = '''// Generated by benchmarks/generate-map-comparison.py.
import Prim "mo:⛔";
import Core "mo:core/pure/Map";
import Map "mo:pure-map/Map";
actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  type Entry = (Nat64, Nat);
  type Iter = {next : () -> ?Entry};
  transient var count : Nat = 0;
  transient var operation : Nat = 0;
  transient var active : Nat = 0;
  transient var iterations : Nat = 0;
  transient var stride : Nat = 0;
  transient let keyBase : Nat64 = 9223372036854775808;
  transient var hitIndices : [Nat] = [];
  transient var hits : [Nat64] = [];
  transient var misses : [Nat64] = [];
  transient var expectedChecksum : Nat = 0;
  transient var sortedInput : [Entry] = [];
  transient var rightCount : Nat = 0;
  transient var coreRight : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginRight : Map.Map<Nat64, Nat> = Map.empty();
  transient var rangeStart : Nat64 = keyBase;
  transient var rangeEnd : Nat64 = keyBase;
  transient var coreInput : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginInput : Map.Map<Nat64, Nat> = Map.empty();
  transient var coreOutput : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginOutput : Map.Map<Nat64, Nat> = Map.empty();
  transient var coreHistory : [var ?Core.Map<Nat64, Nat>] = [var];
  transient var pluginHistory : [var ?Map.Map<Nat64, Nat>] = [var];
  transient var checksum : Nat = 0;

  func compare(a : Nat64, b : Nat64) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func key(index : Nat) : Nat64 { keyBase + Prim.natToNat64(index * 2) };

  // The independently known base bindings are keyBase+2*i -> i. Never trust
  // either map as the other's sole oracle, including their size metadata.
  func checkEntries(iter : Iter, changed : Bool, version : Nat) {
    let expectedValues = Prim.Array_tabulateVar<Nat>(count, func(i : Nat) : Nat { i });
    if (changed and (operation == 3 or operation == 7)) {
      var j = 0;
      while (j <= version) { expectedValues[hitIndices[j]] := count + j; j += 1 }
    };
    var i = 0;
    while (i < count) {
      let inRight = i % 16 == 0 and i / 8 < rightCount;
      let keep = not changed or
        (if (operation == 5) i != hitIndices[iterations - 1]
         else if (operation == 12) i % 2 == 0
         else if (operation == 14) inRight
         else if (operation == 15) not inRight
         else true);
      if (changed and operation == 13 and inRight) expectedValues[i] := count + i / 8;
      if (keep) {
        assert iter.next() == ?(key(i), expectedValues[i]);
      };
      if (changed and operation == 2 and i == hitIndices[iterations - 1]) {
        assert iter.next() == ?(misses[iterations - 1], (iterations - 1 : Nat));
      };
      if (changed and operation == 13 and i % 8 == 0 and i / 8 < rightCount and (i / 8) % 2 == 1) {
        assert iter.next() == ?(key(i) + 1, count + i / 8);
      };
      i += 1;
    };
    assert iter.next() == null;
  };
  func expectedSize() : Nat {
    if (operation == 2) count + 1 else if (operation == 5) count - 1
    else if (operation == 12) (count + 1) / 2
    else if (operation == 13) count + rightCount / 2
    else if (operation == 14) (rightCount + 1) / 2
    else if (operation == 15) count - (rightCount + 1) / 2
    else count
  };
  func invariant(tree : Map.Map<Nat64, Nat>, lower : ?Nat64, upper : ?Nat64, depth : Nat) : (Nat32, Nat) {
    assert depth <= 128;
    switch tree {
      case null (0, 0);
      case (?(height, size, k, _, left, right)) {
        switch lower { case (?bound) assert bound < k; case null {} };
        switch upper { case (?bound) assert k < bound; case null {} };
        let (lh, ls) = invariant(left, lower, ?k, depth + 1);
        let (rh, rs) = invariant(right, ?k, upper, depth + 1);
        assert height == 1 + (if (lh > rh) lh else rh);
        assert lh <= rh + 1 and rh <= lh + 1;
        assert size == ls + rs + 1;
        (height, size)
      }
    }
  };
  public func configure(index : Nat) : async () {
    switch index {
CONFIGURE
      case _ Prim.trap("unknown workload");
    };
    // Spread hits across the map, avoiding a privileged fixed root key.
    // This is the same prebuilt sequence for every implementation.
    hitIndices := Prim.Array_tabulate<Nat>(iterations, func(i : Nat) : Nat {
      ((i * 4051) % iterations) * count / iterations
    });
    hits := Prim.Array_tabulate<Nat64>(iterations, func(i : Nat) : Nat64 { key(hitIndices[i]) });
    misses := Prim.Array_tabulate<Nat64>(iterations, func(i : Nat) : Nat64 { hits[i] + 1 });
    expectedChecksum := 0;
    for (index in hitIndices.values()) expectedChecksum += index;
    rangeStart := key(count / 2);
    let end = if (count / 2 + 16 < count) count / 2 + 16 else count;
    rangeEnd := key(end);
    if (operation == 9) expectedChecksum := count * (count - 1) / 2;
    if (operation == 10) {
      expectedChecksum := 0;
      var i = count / 2;
      while (i < end) { expectedChecksum += i; i += 1 }
    };
    sortedInput := Prim.Array_tabulate<Entry>(count, func(i) { (key(i), i) });
    coreInput := Core.empty(); pluginInput := Map.empty();
    // A permutation gives each tree identical distinct insertion inputs.
    // Its stride is coprime with the selected size.
    var i = 0;
    while (i < count) {
      let ordinal = (i * stride) % count;
      coreInput := Core.add(coreInput, compare, key(ordinal), ordinal);
      pluginInput := Map.add(pluginInput, compare, key(ordinal), ordinal);
      i += 1;
    };
    assert Core.size(coreInput) == count;
    assert Map.size(pluginInput) == count;
    checkEntries(Core.entries(coreInput), false, 0);
    checkEntries(Map.entries(pluginInput), false, 0);
    ignore invariant(pluginInput, null, null, 0);
    rightCount := if (count < 16) 1 else count / 16;
    coreRight := Core.empty(); pluginRight := Map.empty();
    i := 0;
    while (i < rightCount) {
      let rightKey = key(i * 8) + Prim.natToNat64(i % 2);
      coreRight := Core.add(coreRight, compare, rightKey, count + i);
      pluginRight := Map.add(pluginRight, compare, rightKey, count + i);
      i += 1;
    };
  };
  public func clear() : async () {
    coreOutput := Core.empty(); pluginOutput := Map.empty(); checksum := 0;
    coreHistory := Prim.Array_init<?Core.Map<Nat64, Nat>>(iterations, null);
    pluginHistory := Prim.Array_init<?Map.Map<Nat64, Nat>>(iterations, null);
  };
  public query func bytesResult() : async Blob {
    assert checksum == (if (operation == 0 or operation == 9 or operation == 10) expectedChecksum else 0);
    // Every phase rechecks both original versions to catch input mutation.
    checkEntries(Core.entries(coreInput), false, 0);
    checkEntries(Map.entries(pluginInput), false, 0);
    if (active == 0) {
      assert Core.size(coreOutput) == expectedSize();
      checkEntries(Core.entries(coreOutput), true, iterations - 1);
      if (operation == 7) {
        var i = 0;
        while (i < iterations) {
          switch (coreHistory[i]) { case (?tree) checkEntries(Core.entries(tree), true, i); case null assert false };
          i += 1;
        }
      }
    } else {
      assert Map.size(pluginOutput) == expectedSize();
      checkEntries(Map.entries(pluginOutput), true, iterations - 1);
      ignore invariant(pluginOutput, null, null, 0);
      if (operation == 7) {
        var i = 0;
        while (i < iterations) {
          switch (pluginHistory[i]) {
            case (?tree) { checkEntries(Map.entries(tree), true, i); ignore invariant(tree, null, null, 0) };
            case null assert false;
          };
          i += 1;
        }
      }
    };
    "ok"
  };
METHODS
}
'''.replace('CONFIGURE', '\n'.join(configure)).replace('METHODS',
    measure('core', 'Core', 'coreInput', 'coreOutput', 'coreHistory') +
    measure('plugin_custom', 'Map', 'pluginInput', 'pluginOutput', 'pluginHistory') +
    measure('plugin_static', 'Map', 'pluginInput', 'pluginOutput', 'pluginHistory'))
(args.out / 'main.mo').write_text(source)
(args.out / 'cases.json').write_text(json.dumps({
    'cases': cases,
    'implementations': {'core': {'package': 'core', 'version': '2.5.0', 'module': 'pure/Map'},
                        'plugin_custom': {'package': 'plugin/pure-map', 'version': 'ABI 1', 'comparison': 'Motoko callback'},
                        'plugin_static': {'package': 'plugin/pure-map', 'version': 'ABI 1', 'comparison': 'native Nat64 order'}},
    'methodology': 'Same compiler, actor, boxed Nat64 keys, Nat values, key comparator and insertion order. Fresh canister per workload/trial; prepare maps, identical deterministic hit keys spread across the complete range, interleaved absent keys, iterator validation and history slots before timing. Each phase executes the stated number of synchronous operations, retains its last root and (for retained-overwrite) every root. Counter/loop/result-assignment and any synchronous GC costs are included. End-of-message GC is excluded. Inputs and retained results are checked after timing. Insert/remove-hit repeatedly operate on the original map to measure successful operations; overwrite, replace-miss, remove-miss and retained-overwrite operate on the preceding result. Raw measurements are batch totals; divide by operations_per_phase for per-operation values. Retained histories cap eight versions; bulk phases perform one operation. Bulk inputs are sorted distinct, avoiding the pinned Core duplicate-constructor defect. Range returns at most 16 entries around the midpoint. Core lacks seek/set APIs: range scans its ordered iterator until the upper bound; union folds smaller-map additions; intersection iterates the smaller map and performs point lookups/additions; difference skips absent keys before removal. Set inputs have size ratio 16:1 with half overlapping keys. Core filter and fromIter are the public library implementations.',
    'correctness': 'The checked_decode runner kind is used as a generic checked-result protocol. Actor query checks complete ordered key/value contents against independently known ordinal bindings, exact size, both unmodified original maps, every retained historical version, and independently recomputed plugin AVL heights/counts/order. It returns ok only after all checks pass. Validation is outside the timed interval.',
}, indent=2) + '\n')
print(args.out / 'main.mo')
