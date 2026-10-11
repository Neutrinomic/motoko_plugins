//MOC-FLAG --plugin ../../../../dist/mutable-map
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "../../motoko/Map";
func cmp(a : Nat, b : Nat) : Map.Order { if (a < b) #less else if (a == b) #equal else #greater };
func collect<T>(iter : Map.Iter<T>) : [T] {
  var out : [T] = [];
  for (value in iter) { let old = out; out := Prim.Array_tabulate<T>(out.size() + 1, func(i) { if (i < old.size()) old[i] else value }) };
  out
};
let tree = Map.empty<Nat, Nat>();
assert Map.isEmpty(tree);
assert Map.get(tree, cmp, 0) == null;
assert Map.minEntry(tree) == null;
assert Map.maxEntry(tree) == null;
assert Map.entries(tree).next() == null;
var i = 0;
while (i < 2048) {
  let key = i * 997 % 2048;
  assert Map.insert(tree, cmp, key, key * 10);
  Map.assertValid(tree, cmp);
  i += 1;
};
assert Map.size(tree) == 2048;
assert not Map.insert(tree, cmp, 10, 101);
assert Map.swap(tree, cmp, 10, 102) == ?101;
assert Map.replace(tree, cmp, 10, 100) == ?102;
assert Map.replace(tree, cmp, 5000, 0) == null;
assert Map.getEntry(tree, cmp, 10) == ?(10, 100);
assert Map.containsKey(tree, cmp, 2047);
assert not Map.containsKey(tree, cmp, 2048);
assert Map.minEntry(tree) == ?(0, 0);
assert Map.maxEntry(tree) == ?(2047, 20470);
i := 0;
for ((key, value) in Map.entries(tree)) { assert key == i and value == key * 10; i += 1 };
assert i == 2048;
i := 2048;
for ((key, value) in Map.reverseEntries(tree)) { i -= 1; assert key == i and value == key * 10 };
assert i == 0;
for (seek in [0, 1, 15, 16, 30, 31, 32, 1000, 2047, 2048, 99999].values()) {
  i := seek;
  for ((key, _) in Map.entriesFrom(tree, cmp, seek)) { assert key == i; i += 1 };
  assert i == (if (seek >= 2048) seek else 2048);
  i := (if (seek >= 2048) 2048 else seek + 1);
  for ((key, _) in Map.reverseEntriesFrom(tree, cmp, seek)) { i -= 1; assert key == i };
  assert i == 0;
};
let copied = Map.clone(tree);
Map.add(copied, cmp, 9999, 9999);
Map.remove(copied, cmp, 0);
assert Map.get(tree, cmp, 9999) == null;
assert Map.get(tree, cmp, 0) == ?0;
assert Map.size(copied) == Map.size(tree);
Map.assertValid(copied, cmp);
let mapped = Map.map<Nat, Nat, Nat>(tree, func(key : Nat, value : Nat) : Nat { assert value == key * 10; key + 1 });
Map.assertValid(mapped, cmp);
assert Map.get(mapped, cmp, 1024) == ?1025;
assert Map.foldLeft(tree, 0, func(sum : Nat, key : Nat, value : Nat) : Nat { assert value == key * 10; sum + key }) == 2047 * 1024;
var ordered = 2048;
assert Map.foldRight<Nat, Nat, Nat>(tree, 0, func(key : Nat, value : Nat, acc : Nat) : Nat { ordered -= 1; assert key == ordered and value == key * 10; acc + 1 }) == 2048;
assert ordered == 0;
var calls = 0;
assert Map.find(tree, func(key : Nat, _ : Nat) : Bool { calls += 1; key == 1000 }) == ?(1000, 10000);
assert calls == 1001;
assert Map.find(tree, func(_ : Nat, _ : Nat) : Bool { false }) == null;
assert Map.all(tree, func(key : Nat, value : Nat) : Bool { value == key * 10 });
assert Map.any(tree, func(key : Nat, _ : Nat) : Bool { key == 2047 });
let filtered = Map.filter(tree, cmp, func(key : Nat, _ : Nat) : Bool { key % 3 == 0 });
let filterMapped = Map.filterMap<Nat, Nat, Nat>(tree, cmp, func(key : Nat, value : Nat) : ?Nat { if (key % 3 == 0) ?value else null });
Map.assertValid(filtered, cmp);
Map.assertValid(filterMapped, cmp);
assert Map.equal(filtered, filterMapped, cmp, func(a : Nat, b : Nat) : Bool { a == b });
assert Map.compare(filtered, filterMapped, cmp, cmp) == #equal;
assert Map.toArray(Map.fromArray<Nat, Nat>(Map.toArray(filtered), cmp)) == Map.toArray(filtered);
assert Map.toArray(Map.fromVarArray<Nat, Nat>(Map.toVarArray(filtered), cmp)) == Map.toArray(filtered);
assert collect(Map.keys(Map.singleton<Nat, Nat>(7, 8))) == [7];
assert collect(Map.values(Map.singleton<Nat, Nat>(7, 8))) == [8];
assert Map.toText(Map.singleton("a", "b"), func(t : Text) : Text { t }, func(t : Text) : Text { t }) == "Map{(a, b)}";
i := 0;
while (i < 2048) {
  let key = i * 751 % 2048;
  if (i % 3 == 0) assert Map.take(tree, cmp, key) == ?(key * 10)
  else if (i % 3 == 1) assert Map.delete(tree, cmp, key)
  else Map.remove(tree, cmp, key);
  assert not Map.delete(tree, cmp, key);
  assert Map.take(tree, cmp, key) == null;
  assert Map.size(tree) == (2047 - i : Nat);
  Map.assertValid(tree, cmp);
  i += 1;
};
assert Map.isEmpty(tree);
assert Map.toArray(tree) == [];
Map.add(tree, cmp, 1, 2);
let alias = tree;
Map.clear(alias);
assert Map.isEmpty(tree);
Map.assertValid(tree, cmp);
