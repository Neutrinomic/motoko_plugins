//MOC-FLAG --plugin ../../../../dist/mutable-map
//MOC-FLAG --package core $MOTOKO_CORE -A M0236
import Prim "mo:⛔";
import Map "../../motoko/Map";
import Core "mo:core/Map";
import Interop "../../motoko/Core";
func cmp(a : Nat, b : Nat) : Map.Order { if (a < b) #less else if (a == b) #equal else #greater };
let actual = Map.empty<Nat, ?Nat>();
let expected = Core.empty<Nat, ?Nat>();
var rng : Nat32 = 0x739825fa;
func random(limit : Nat) : Nat {
  rng := rng *% 1664525 +% 1013904223;
  Prim.nat32ToNat(rng) % limit
};
func check() {
  Map.assertValid(actual, cmp);
  assert Map.size(actual) == Core.size(expected);
  assert Map.toArray(actual) == Core.toArray(expected);
  assert Map.minEntry(actual) == Core.minEntry(expected);
  assert Map.maxEntry(actual) == Core.maxEntry(expected);
};
// Begin beyond one split level, then repeatedly mix all update paths, including
// absent removal and nullable values. The independent core tree is the oracle.
var i = 0;
while (i < 1100) { Map.add(actual, cmp, i, ?i); Core.add(expected, cmp, i, ?i); i += 1 };
check();
i := 0;
while (i < 12000) {
  let key = random(1700);
  let value : ?Nat = if (random(7) == 0) null else ?random(100000);
  switch (random(11)) {
    case 0 { assert Map.insert(actual, cmp, key, value) == Core.insert(expected, cmp, key, value) };
    case 1 { assert Map.swap(actual, cmp, key, value) == Core.swap(expected, cmp, key, value) };
    case 2 { assert Map.replace(actual, cmp, key, value) == Core.replace(expected, cmp, key, value) };
    case 3 { assert Map.take(actual, cmp, key) == Core.take(expected, cmp, key) };
    case 4 { assert Map.delete(actual, cmp, key) == Core.delete(expected, cmp, key) };
    case 5 { Map.remove(actual, cmp, key); Core.remove(expected, cmp, key) };
    case 6 { assert Map.get(actual, cmp, key) == Core.get(expected, cmp, key) };
    case 7 { assert Map.containsKey(actual, cmp, key) == Core.containsKey(expected, cmp, key) };
    case _ { Map.add(actual, cmp, key, value); Core.add(expected, cmp, key, value) };
  };
  if (i % 31 == 0) check();
  i += 1;
};
check();
let converted = Interop.fromPure<Nat, ?Nat>(Interop.toPure<Nat, ?Nat>(actual, cmp), cmp);
assert Map.toArray(converted) == Map.toArray(actual);
Map.clear(converted);
check();
// Removing alternately at either extreme exercises merges/root collapse.
while (Map.size(actual) > 0) {
  let key = switch (if (Map.size(actual) % 2 == 0) Map.minEntry(actual) else Map.maxEntry(actual)) {
    case (?(key, _)) key;
    case null { assert false; 0 };
  };
  assert Map.take(actual, cmp, key) == Core.take(expected, cmp, key);
  check();
};
