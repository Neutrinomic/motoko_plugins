//MOC-FLAG --plugin ../../../dist/mutable-map --package fast ../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG -A M0236
import Map "mo:fast/Map";

func compare(a : Nat64, b : Nat64) : Map.Order {
  assert a != b;
  if (a < b) #less else if (a == b) #equal else #greater
};
let map = Map.singleton<Nat64, Nat>(0, 42);
ignore Map.get(map, compare, (0 : Nat64));
