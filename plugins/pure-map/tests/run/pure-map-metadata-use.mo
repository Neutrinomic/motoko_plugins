//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "mo:fast/pure/Map";

func compare(a : Nat, b : Nat) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};

// Forged trees need assertValid before general use. Hot lookup and same-shape
// replacement do not consume height/count metadata or silently validate it.
let forged : Map.Map<Nat, Nat> = ?(0, 0, 7, 9, null, null);
assert Map.get(forged, compare, 7) == ?9;
assert Map.getNat(forged, 7) == ?9;
assert Map.containsKey(forged, compare, 7);
assert not Map.containsKey(forged, compare, 8);
assert Map.remove(forged, compare, 8) == forged;
let copied = Map.add(forged, compare, 7, 10);
assert copied == ?(0, 0, 7, 10, null, null);
var calls = 0;
let altered = Map.alter(forged, compare, 7, func (old : ?Nat) : ?Nat {
  calls += 1;
  assert old == ?9;
  ?11
});
assert calls == 1;
assert altered == ?(0, 0, 7, 11, null, null);

// Selection consumes the root count before descending. The reference evaluator
// must apply this same gate, even when an application forges a smaller count.
let child : Map.Map<Nat, Nat> = ?(1, 1, 8, 80, null, null);
let undersized : Map.Map<Nat, Nat> = ?(2, 1, 7, 70, null, child);
assert Map.get(undersized, compare, 8) == ?80;
assert Map.select(undersized, 0) == ?(7, 70);
assert Map.select(undersized, 1) == null;
assert Map.select(undersized, 340282366920938463463374607431768211456) == null;

// The metadata policy must not introduce hidden allocations in scalar lookup.
let before = Prim.rts_total_allocation();
var index = 0;
while (index < 1000) {
  assert Map.get(forged, compare, 7) == ?9;
  assert Map.getNat(forged, 7) == ?9;
  index += 1;
};
assert Prim.rts_total_allocation() == before;
