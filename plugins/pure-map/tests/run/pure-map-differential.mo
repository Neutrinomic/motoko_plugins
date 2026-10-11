//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "mo:fast/pure/Map";
import Oracle "../lib/SortedOracle";

type Value = ?Nat;
type Entries = Oracle.Entries<Nat, Value>;
type Tree = Map.Map<Nat, Value>;
func cmp(a : Nat, b : Nat) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};

// Read node fields directly so the oracle does not trust plugin validation.
func invariant(tree : Tree, lower : ?Nat, upper : ?Nat, depth : Nat) : (Nat32, Nat) {
  assert depth <= 128;
  switch tree {
    case null (0, 0);
    case (?(height, count, key, _, left, right)) {
      switch lower { case (?k) assert k < key; case null {} };
      switch upper { case (?k) assert key < k; case null {} };
      let (lh, lc) = invariant(left, lower, ?key, depth + 1);
      let (rh, rc) = invariant(right, ?key, upper, depth + 1);
      assert height == 1 + (if (lh > rh) lh else rh);
      assert lh <= rh + 1 and rh <= lh + 1;
      assert count == lc + rc + 1;
      (height, count)
    }
  }
};

func check(tree : Tree, expected : Entries) {
  let (_, count) = invariant(tree, null, null, 0);
  assert count == expected.size();
  assert Map.size(tree) == expected.size();
  let forward = Map.entries(tree);
  for (entry in expected.values()) {
    assert forward.next() == ?entry;
    assert Map.get(tree, cmp, entry.0) == ?entry.1;
  };
  assert forward.next() == null;
  assert forward.next() == null;
  let backward = Map.reverseEntries(tree);
  var index = expected.size();
  while (index > 0) {
    index -= 1;
    assert backward.next() == ?expected[index];
  };
  assert backward.next() == null;
  assert Map.get(tree, cmp, 1_000_000) == null;
};

// All four insertion rotations, followed by deletion rebalancing.
for (order in [[3, 2, 1], [1, 2, 3], [3, 1, 2], [1, 3, 2]].values()) {
  var tree : Tree = Map.empty();
  var expected : Entries = [];
  for (key in order.values()) {
    tree := Map.add(tree, cmp, key, ?key);
    expected := Oracle.swap(expected, cmp, key, ?key).0;
    check(tree, expected);
  };
  for (key in order.values()) {
    tree := Map.remove(tree, cmp, key);
    expected := Oracle.take(expected, cmp, key).0;
    check(tree, expected);
  }
};

type History = (Tree, Entries);
let histories : [var ?History] = Prim.Array_init<?History>(32, null);
var tree : Tree = Map.empty();
var expected : Entries = [];
var seed : Nat = 1729;
func random(limit : Nat) : Nat {
  seed := (seed * 48271) % 2147483647;
  seed % limit
};
var step = 0;
while (step < 1200) {
  // Branch from old versions, not just a latest-version-only mutation chain.
  if (step % 31 == 0) {
    switch (histories[random(histories.size())]) {
      case (?(oldTree, oldExpected)) { tree := oldTree; expected := oldExpected };
      case null {};
    }
  };
  let key = random(131);
  let value : Value = if (step % 7 == 0) null else ?random(10000);
  let before = tree;
  let expectedBefore = expected;
  switch (random(7)) {
    case 0 {
      let (next, old) = Map.swap(tree, cmp, key, value);
      let (oracleNext, oracleOld) = Oracle.swap(expected, cmp, key, value);
      assert old == oracleOld;
      tree := next; expected := oracleNext;
    };
    case 1 {
      let (next, old) = Map.replace(tree, cmp, key, value);
      let (oracleNext, oracleOld) = Oracle.replace(expected, cmp, key, value);
      assert old == oracleOld;
      tree := next; expected := oracleNext;
    };
    case 2 {
      let (next, old) = Map.take(tree, cmp, key);
      let (oracleNext, oracleOld) = Oracle.take(expected, cmp, key);
      assert old == oracleOld;
      tree := next; expected := oracleNext;
    };
    case 3 {
      let (next, added) = Map.insert(tree, cmp, key, value);
      let (oracleNext, oracleOld) = Oracle.swap(expected, cmp, key, value);
      assert added == (oracleOld == null);
      tree := next; expected := oracleNext;
    };
    case 4 {
      let (next, deleted) = Map.delete(tree, cmp, key);
      let (oracleNext, oracleOld) = Oracle.take(expected, cmp, key);
      assert deleted == (oracleOld != null);
      tree := next; expected := oracleNext;
    };
    case 5 {
      tree := Map.add(tree, cmp, key, value);
      expected := Oracle.swap(expected, cmp, key, value).0;
    };
    case _ {
      assert Map.get(tree, cmp, key) == Oracle.get(expected, cmp, key);
      tree := Map.remove(tree, cmp, 1_000_000);
    };
  };
  check(before, expectedBefore);
  check(tree, expected);
  if (step % 9 == 0) histories[(step / 9) % histories.size()] := ?(tree, expected);
  if (step % 41 == 0) {
    for (history in histories.values()) {
      switch history { case (?(oldTree, oldExpected)) check(oldTree, oldExpected); case null {} }
    }
  };
  step += 1;
};
for (history in histories.values()) {
  switch history { case (?(oldTree, oldExpected)) check(oldTree, oldExpected); case null {} }
};

// Equality of keys is comparator equality, not Motoko structural equality.
type Key = {order : Nat; spelling : Text};
func keyCmp(a : Key, b : Key) : Map.Order { cmp(a.order, b.order) };
let oldKey : Key = {order = 5; spelling = "old"};
let newKey : Key = {order = 5; spelling = "new"};
let first = Map.add(Map.empty<Key, ??Nat>(), keyCmp, oldKey, ?null);
let (second, oldValue) = Map.swap(first, keyCmp, newKey, ??42);
assert oldValue == ??null;
assert Map.entries(first).next() == ?(oldKey, ?null);
assert Map.entries(second).next() == ?(newKey, ??42);
assert Map.size(second) == 1;
let (replaced, replacedOld) = Map.replace(first, keyCmp, newKey, (null : ??Nat));
assert replacedOld == ??null;
assert Map.entries(replaced).next() == ?(newKey, (null : ??Nat));
assert Map.entries(first).next() == ?(oldKey, ?null);

// One comparator call per visited node, including updates. Comparators can
// reenter the plugin and retain ordinary generic managed payloads.
var calls = 0;
func countingCmp(a : Nat, b : Nat) : Map.Order {
  calls += 1;
  assert Map.get(first, keyCmp, oldKey) == ??null;
  cmp(a, b)
};
var probe = 0;
while (probe < 140) {
  calls := 0;
  ignore Map.get(tree, countingCmp, probe);
  let expectedCalls = calls;
  calls := 0;
  ignore Map.swap(tree, countingCmp, probe, null);
  assert calls == expectedCalls;
  calls := 0;
  ignore Map.take(tree, countingCmp, probe);
  assert calls == expectedCalls;
  calls := 0;
  ignore Map.replace(tree, countingCmp, probe, null);
  assert calls == expectedCalls;
  probe += 1;
};

// Values remain opaque references, including non-shared types.
let payload = {var count = 7; call = func(n : Nat) : Nat { n + 3 }};
let functions = Map.add(Map.empty<Nat, {var count : Nat; call : Nat -> Nat}>(), cmp, 1, payload);
let newerFunctions = Map.add(functions, cmp, 2, payload);
payload.count := 11;
switch (Map.get(functions, cmp, 1), Map.get(newerFunctions, cmp, 2)) {
  case (?a, ?b) { assert a.count == 11; assert b.call(4) == 7 };
  case _ assert false;
};
