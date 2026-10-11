//MOC-FLAG --plugin ../../../../../dist/mutable-map
//MOC-FLAG --package core $MOTOKO_CORE -A M0236
import Prim "mo:⛔";
import Map "../../../../../plugins/mutable-map/motoko/Map";
import Core "mo:core/Map";

func cmp(a : Nat, b : Nat) : Map.Order { if (a < b) #less else if (a == b) #equal else #greater };
let map = Map.empty<Nat, ?Nat>();
let oracle = Core.empty<Nat, ?Nat>();
let side = Map.empty<Nat, Nat>();
var expected : [(Nat, ?Nat)] = [];
var comparisons = 0;
func observing(a : Nat, b : Nat) : Map.Order {
  comparisons += 1;
  Map.assertValid(map, cmp);
  assert Map.toArray(map) == expected;
  assert Map.size(map) == expected.size();
  if (expected.size() > 0) {
    let key = expected[expected.size() / 2].0;
    assert Map.get(map, cmp, key) == Core.get(oracle, cmp, key);
  };
  Map.addNat(side, 0, comparisons);
  cmp(a, b)
};
func verify() {
  Map.assertValid(map, cmp);
  assert Map.toArray(map) == Core.toArray(oracle);
  expected := Core.toArray(oracle);
};
var i = 0;
while (i < 128) {
  let key = i * 97 % 128;
  assert Map.insert(map, observing, key, ?key) == Core.insert(oracle, cmp, key, ?key);
  verify();
  i += 1;
};
// Extend to height >= 3. The subsequent removals also collapse the root.
while (i < 640) { Map.add(map, cmp, i, ?i); Core.add(oracle, cmp, i, ?i); i += 1 };
verify();
i := 0;
while (i < 640) {
  let key = i * 509 % 640;
  assert Map.take(map, observing, key) == Core.take(oracle, cmp, key);
  verify();
  assert not Map.delete(map, observing, key);
  verify();
  i += 1;
};
assert Map.isEmpty(map);
assert Map.getNat(side, 0) == ?comparisons;
assert comparisons > 2000;
Prim.debugPrint("audit: callback-visible tree and size remained valid across split/borrow/merge/root collapse");
