//MOC-FLAG --plugin ../../../../dist/pure-map
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "../../motoko/Map";
import Oracle "../lib/SortedOracle";

type Tree = Map.Map<Nat, Nat>;
type Entries = [(Nat, Nat)];
func cmp(a : Nat, b : Nat) : Map.Order { if (a < b) #less else if (a == b) #equal else #greater };
func collect(iter : Map.Iter<(Nat, Nat)>, expected : Entries, reverse : Bool) {
  var i = 0;
  while (i < expected.size()) {
    assert iter.next() == ?expected[if (reverse) expected.size() - i - 1 else i];
    i += 1;
  };
  assert iter.next() == null;
  assert iter.next() == null;
};
func check(tree : Tree, expected : Entries) {
  Map.assertValid(tree, cmp);
  assert Map.size(tree) == expected.size();
  assert Map.toArray(tree) == expected;
  collect(Map.entries(tree), expected, false);
  collect(Map.reverseEntries(tree), expected, true);
};
func filtered(input : Entries, predicate : (Nat, Nat) -> Bool) : Entries {
  let buffer : [var ?(Nat, Nat)] = Prim.Array_init<?(Nat, Nat)>(input.size(), null);
  var count = 0;
  for ((key, value) in input.values()) {
    if (predicate(key, value)) { buffer[count] := ?(key, value); count += 1 }
  };
  Prim.Array_tabulate<(Nat, Nat)>(count, func(i) {
    switch (buffer[i]) { case (?entry) entry; case null Prim.trap("oracle") }
  })
};
func prefix(input : Entries, start : Nat, end : Nat) : Entries {
  Prim.Array_tabulate<(Nat, Nat)>(end - start, func(i) { input[start + i] })
};

var n = 0;
while (n < 35) {
  let input = Prim.Array_tabulate<(Nat, Nat)>(n, func(i) { (i * 2, i + 100) });
  let tree = Map.fromSortedDistinctArray(input, cmp);
  check(tree, input);
  var index = 0;
  while (index <= n + 1) {
    let split = if (index > n) n else index;
    let (left, right) = Map.splitAt(tree, index);
    check(left, prefix(input, 0, split));
    check(right, prefix(input, split, n));
    check(Map.concatDisjoint(left, cmp, right), input);
    assert Map.select(tree, index) == (if (index < n) ?input[index] else null);
    index += 1;
  };
  var key = 0;
  while (key <= n * 2 + 1) {
    let (rank, found) = Oracle.locate(input, cmp, key);
    assert Map.rank(tree, cmp, key) == rank;
    assert Map.indexOf(tree, cmp, key) == (if (found) ?rank else null);
    let (left, entry, right) = Map.splitLookup(tree, cmp, key);
    check(left, prefix(input, 0, rank));
    assert entry == (if (found) ?input[rank] else null);
    check(right, prefix(input, rank + (if (found) 1 else 0), n));
    assert Map.lower(tree, cmp, key) == (if (rank == 0) null else ?input[rank - 1]);
    assert Map.floor(tree, cmp, key) == (if (found) ?input[rank] else if (rank == 0) null else ?input[rank - 1]);
    assert Map.ceiling(tree, cmp, key) == (if (rank < n) ?input[rank] else null);
    let higher = rank + (if (found) 1 else 0);
    assert Map.higher(tree, cmp, key) == (if (higher < n) ?input[higher] else null);
    key += 1;
  };
  let (withoutMin, smallest) = Map.popMin(tree);
  let (withoutMax, largest) = Map.popMax(tree);
  if (n == 0) {
    assert smallest == null and largest == null;
    check(withoutMin, []); check(withoutMax, []);
  } else {
    assert smallest == ?input[0] and largest == ?input[n - 1];
    check(withoutMin, prefix(input, 1, n));
    check(withoutMax, prefix(input, 0, n - 1));
  };
  // Multiple equal keys in unsorted input: the final key/value wins.
  let scrambled = Prim.Array_tabulate<(Nat, Nat)>(n * 3, func(i) { ((i * 17) % (n + 1), i) });
  var oracle : Entries = [];
  for ((k, v) in scrambled.values()) oracle := Oracle.swap(oracle, cmp, k, v).0;
  check(Map.fromArray(scrambled, cmp), oracle);
  check(Map.fromIter(scrambled.values(), cmp), oracle);
  n += 1;
};

let allEntries = Prim.Array_tabulate<(Nat, Nat)>(40, func(i) { (i, i * 3) });
let all = Map.fromArray(allEntries, cmp);
var compareCalls = 0;
func counted(a : Nat, b : Nat) : Map.Order { compareCalls += 1; cmp(a, b) };
for (from in [#unbounded, #inclusive(0), #exclusive(0), #inclusive(7), #exclusive(7), #inclusive(100)].values()) {
  for (to in [#unbounded, #inclusive(0), #exclusive(0), #inclusive(23), #exclusive(23), #exclusive(100)].values()) {
    let expected = filtered(allEntries, func(key, _) {
      let lower = switch from { case (#unbounded) true; case (#inclusive k) key >= k; case (#exclusive k) key > k };
      let upper = switch to { case (#unbounded) true; case (#inclusive k) key <= k; case (#exclusive k) key < k };
      lower and upper
    });
    let view = Map.rangeSnapshot(all, counted, from, to, false);
    let beforeReplay = compareCalls;
    collect(Map.replay(view), expected, false);
    collect(Map.replay(view), expected, false);
    assert compareCalls == beforeReplay;
    collect(Map.entriesInRange(all, cmp, from, to), expected, false);
    collect(Map.reverseEntriesInRange(all, cmp, from, to), expected, true);
    check(Map.rangeMap(all, cmp, from, to), expected);
    assert Map.countInRange(all, cmp, from, to) == expected.size();
    let remaining = filtered(allEntries, func(key, _) { Oracle.get(expected, cmp, key) == null });
    check(Map.removeRange(all, cmp, from, to), remaining);
  }
};

// Ordered transformations and exact callback counts, including all/no matches.
var nextKey = 0;
let transformed = Map.map(all, func(key : Nat, value : Nat) : Nat {
  assert key == nextKey; nextKey += 1; value + 7
});
assert nextKey == 40;
check(transformed, Prim.Array_tabulate<(Nat, Nat)>(40, func(i) { (i, i * 3 + 7) }));
nextKey := 0;
let even = Map.filter(all, func(key : Nat, _ : Nat) : Bool {
  assert key == nextKey; nextKey += 1; key % 2 == 0
});
check(even, filtered(allEntries, func(key, _) { key % 2 == 0 }));
assert nextKey == 40;
check(Map.filter(all, func(_, _) { true }), allEntries);
check(Map.filter(all, func(_, _) { false }), []);
let (yes, no) = Map.partition(all, func(key : Nat, _ : Nat) : Bool { key % 3 == 0 });
check(yes, filtered(allEntries, func(key, _) { key % 3 == 0 }));
check(no, filtered(allEntries, func(key, _) { key % 3 != 0 }));
check(Map.partition(all, func(_, _) { true }).0, allEntries);
check(Map.partition(all, func(_, _) { false }).1, allEntries);
assert Map.foldLeft(all, 0, func(acc : Nat, key : Nat, _ : Nat) : Nat { assert key == acc; acc + 1 }) == 40;
assert Map.foldRight(all, 40, func(key : Nat, _ : Nat, acc : Nat) : Nat { assert key + 1 == acc; key }) == 0;
nextKey := 0;
assert Map.find(all, func(key : Nat, _ : Nat) : Bool { assert key == nextKey; nextKey += 1; key == 7 }) == ?(7, 21);
assert nextKey == 8;
nextKey := 0;
assert Map.any(all, func(key : Nat, _ : Nat) : Bool { nextKey += 1; key == 5 });
assert nextKey == 6;
nextKey := 0;
assert not Map.all(all, func(key : Nat, _ : Nat) : Bool { nextKey += 1; key < 9 });
assert nextKey == 10;

// Exercise both smaller-tree branches of union/intersection, and retained inputs.
for ((leftCount, rightCount) in [(3, 25), (25, 3), (17, 17), (0, 8), (8, 0)].values()) {
  let aa = Prim.Array_tabulate<(Nat, Nat)>(leftCount, func(i) { (i * 2, i + 100) });
  let bb = Prim.Array_tabulate<(Nat, Nat)>(rightCount, func(i) { (i * 3, i + 200) });
  let a = Map.fromArray(aa, cmp);
  let b = Map.fromArray(bb, cmp);
  var unionExpected = aa;
  for ((key, value) in bb.values()) unionExpected := Oracle.swap(unionExpected, cmp, key, value).0;
  check(Map.union(a, cmp, b), unionExpected);
  let common = filtered(aa, func(key, _) { Oracle.get(bb, cmp, key) != null });
  let onlyA = filtered(aa, func(key, _) { Oracle.get(bb, cmp, key) == null });
  check(Map.intersection(a, cmp, b), common);
  check(Map.difference(a, cmp, b), onlyA);
  var symExpected = onlyA;
  for ((key, value) in bb.values()) {
    if (Oracle.get(aa, cmp, key) == null) symExpected := Oracle.swap(symExpected, cmp, key, value).0;
  };
  check(Map.symmetricDifference(a, cmp, b), symExpected);
  var combinedExpected = aa;
  for ((key, value) in bb.values()) {
    let combined = switch (Oracle.get(aa, cmp, key)) { case null value; case (?old) old * 1000 + value };
    combinedExpected := Oracle.swap(combinedExpected, cmp, key, combined).0;
  };
  var callbackIndex = 0;
  let combined = Map.unionWith(a, cmp, b, func(key : Nat, old : Nat, value : Nat) : Nat {
    assert key == common[callbackIndex].0;
    assert old == common[callbackIndex].1;
    callbackIndex += 1;
    old * 1000 + value
  });
  assert callbackIndex == common.size();
  check(combined, combinedExpected);
  callbackIndex := 0;
  let intersection = Map.intersectionWith(a, cmp, b, func(key : Nat, old : Nat, value : Nat) : Nat {
    assert key == common[callbackIndex].0;
    callbackIndex += 1;
    old * 1000 + value
  });
  assert callbackIndex == common.size();
  check(intersection, filtered(combinedExpected, func(key, _) { Oracle.get(common, cmp, key) != null }));
  check(a, aa); check(b, bb);
};

type Key = {order : Nat; name : Text};
func keyCmp(a : Key, b : Key) : Map.Order { cmp(a.order, b.order) };
for ((leftCount, rightCount) in [(3, 9), (9, 3)].values()) {
  let a = Map.fromArray(Prim.Array_tabulate<(Key, Nat)>(leftCount, func(i) { ({order=i;name="a"}, i) }), keyCmp);
  let b = Map.fromArray(Prim.Array_tabulate<(Key, Nat)>(rightCount, func(i) { ({order=i;name="b"}, i+100) }), keyCmp);
  let union = Map.unionWith(a, keyCmp, b, func(key : Key, av : Nat, bv : Nat) : Nat {
    assert key.name == "b"; av + bv
  });
  for ((key, _) in Map.entries(union)) {
    assert key.name == (if (key.order < rightCount) "b" else "a");
  };
  let intersection = Map.intersectionWith(a, keyCmp, b, func(key : Key, av : Nat, bv : Nat) : Nat {
    assert key.name == "a"; av + bv
  });
  for ((key, _) in Map.entries(intersection)) assert key.name == "a";
};

// freeze publishes immutable tree nodes, not the builder's mutable buffer.
let builder = Map.thaw<Nat, Nat>();
Map.thawAppend(builder, cmp, 1, 10);
Map.thawAppend(builder, cmp, 2, 20);
let frozen = Map.freeze(builder);
Map.thawAppend(builder, cmp, 2, 21);
Map.thawAppend(builder, cmp, 3, 30);
let later = Map.freeze(builder);
check(frozen, [(1, 10), (2, 20)]);
check(later, [(1, 10), (2, 21), (3, 30)]);

// Generic options must distinguish absence from a present null payload.
let nulls = Map.add(Map.empty<Nat, Null>(), cmp, 0, null);
assert Map.get(nulls, cmp, 0) == ?null;
assert Map.get(nulls, cmp, 1) == null;
let (replacedNull, previousNull) = Map.replace(nulls, cmp, 0, null);
assert previousNull == ?null;
assert Map.get(replacedNull, cmp, 0) == ?null;
let (absentNull, noPreviousNull) = Map.replace(nulls, cmp, 1, null);
assert noPreviousNull == null;
assert Map.size(absentNull) == 1;
let opaque : Any = ?null;
let opaqueMap = Map.add(Map.empty<Nat, Any>(), cmp, 1, opaque);
let (opaqueNext, opaqueOld) = Map.replace(opaqueMap, cmp, 1, (7 : Any));
switch opaqueOld { case null assert false; case (?_) {} };
switch (Map.get(opaqueNext, cmp, 1)) { case null assert false; case (?_) {} };
let (_, opaqueMissing) = Map.replace(opaqueMap, cmp, 99, (null : Any));
switch opaqueMissing { case null {}; case (?_) assert false };
let (withoutNull, removedNull) = Map.take(nulls, cmp, 0);
assert Map.isEmpty(withoutNull) and removedNull == ?null;
var calls = 0;
let altered = Map.alter(nulls, cmp, 0, func(old : ?Null) : ?Null {
  calls += 1; assert old == ?null; ?null
});
assert calls == 1;
assert Map.get(altered, cmp, 0) == ?null;
ignore Map.alter(nulls, cmp, 1, func(old : ?Null) : ?Null { calls += 1; assert old == null; null });
assert calls == 2;
