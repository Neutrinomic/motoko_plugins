//MOC-FLAG --plugin ../../../dist/mutable-map --plugin ../../../dist/pure-map --plugin ../../../dist/mutable-set --plugin ../../../dist/pure-set
//MOC-FLAG --package fast ../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG -A M0236
import Map "mo:fast/Map";
import PureMap "mo:fast/pure/Map";
import Set "mo:fast/Set";
import PureSet "mo:fast/pure/Set";
import Nat64 "mo:core/Nat64";
import Int "mo:core/Int";

func get<K, V>(map : Map.Map<K, V>, compare : (K, K) -> Map.Order, key : K) : ?V {
  Map.get(map, compare, key)
};

let high : Nat64 = 9_223_372_036_854_775_808;
let maximum : Nat64 = 18_446_744_073_709_551_615;
let keys : [Nat64] = [0, high, maximum];
let compare = Nat64.compare;
let alias = { compare };
let map = Map.empty<Nat64, Nat>();
let set = Set.empty<Nat64>();
var pureMap = PureMap.empty<Nat64, Nat>();
var pureSet = PureSet.empty<Nat64>();
for (key in keys.values()) {
  Map.add(map, compare, key, 42);
  Set.add(set, alias.compare, key);
  pureMap := PureMap.add(pureMap, compare, key, 42);
  pureSet := PureSet.add(pureSet, compare, key);
};
assert get(map, alias.compare, high) == ?42;
assert Set.contains(set, compare, maximum);
assert PureMap.get(pureMap, compare, high) == ?42;
assert PureSet.contains(pureSet, compare, maximum);

// The dispatcher must preserve native two- and three-result operations.
assert PureMap.rank(pureMap, compare, high) == 1;
assert PureSet.rank(pureSet, compare, high) == 1;
let (left, found, right) = PureMap.splitLookup<Nat64, Nat>(pureMap, compare, high);
assert PureMap.size(left) == 1 and found == ?(high, 42) and PureMap.size(right) == 1;
let (setLeft, setFound, setRight) = PureSet.splitLookup<Nat64>(pureSet, compare, high);
assert PureSet.size(setLeft) == 1 and setFound == ?high and PureSet.size(setRight) == 1;

var changes = 0;
let changed = PureMap.alter<Nat64, Nat>(pureMap, compare, 0, func(old) {
  changes += 1;
  assert old == ?42;
  ?43
});
assert changes == 1 and PureMap.get(changed, compare, (0 : Nat64)) == ?43;
assert PureMap.get(pureMap, compare, (0 : Nat64)) == ?42;

// Scalar comparison follows the comparator definition, even for a subtype.
let naturals = Set.empty<Nat>();
Set.add(naturals, Int.compare, 0);
Set.add(naturals, Int.compare, 18_446_744_073_709_551_616);
assert Set.contains(naturals, Int.compare, 0);
assert Set.contains(naturals, Int.compare, 18_446_744_073_709_551_616);

func reverse(a : Nat64, b : Nat64) : Map.Order { Nat64.compare(b, a) };
let reversed = Map.empty<Nat64, Nat>();
for (key in keys.values()) Map.add(reversed, reverse, key, 42);
assert Map.toArray(reversed) == [(maximum, 42), (high, 42), (0, 42)];

// A scalar signature and canonical final expression do not erase effects.
var calls = 0;
func counted(a : Nat64, b : Nat64) : Map.Order {
  calls += 1;
  if (a < b) #less else if (a == b) #equal else #greater
};
let singleton = Map.singleton<Nat64, Nat>(high, 42);
assert get(singleton, counted, high) == ?42 and calls == 1;
assert get(Map.empty<Nat64, Nat>(), counted, high) == null and calls == 1;
