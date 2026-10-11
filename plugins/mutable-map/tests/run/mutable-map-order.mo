//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src
//MOC-FLAG --package core $MOTOKO_CORE -A M0236
import Prim "mo:⛔";
import Map "mo:fast/Map";
import Core "mo:core/Map";
type Key = {order : Nat; var tag : Nat};
func descending(a : Key, b : Key) : Map.Order {
  if (a.order > b.order) #less else if (a.order == b.order) #equal else #greater
};
let actual = Map.empty<Key, Nat>();
let expected = Core.empty<Key, Nat>();
var i = 0;
while (i < 600) {
  let key : Key = {order = i * 89 % 193; var tag = i};
  assert Map.insert(actual, descending, key, i) == Core.insert(expected, descending, key, i);
  i += 1;
};
Map.assertValid(actual, descending);
let a = Map.toArray(actual);
let b = Core.toArray(expected);
assert a.size() == b.size();
i := 0;
while (i < a.size()) {
  assert a[i].0.order == b[i].0.order and a[i].0.tag == b[i].0.tag and a[i].1 == b[i].1;
  a[i].0.tag += 1;
  assert a[i].0.tag == b[i].0.tag;
  i += 1;
};
for (seek in [0, 1, 30, 31, 32, 100, 192, 193, 1000].values()) {
  let key : Key = {order = seek; var tag = 0};
  let forward = Map.entriesFrom(actual, descending, key);
  let forwardOracle = Core.entriesFrom(expected, descending, key);
  let reverse = Map.reverseEntriesFrom(actual, descending, key);
  let reverseOracle = Core.reverseEntriesFrom(expected, descending, key);
  for ((ours, theirs) in [(forward, forwardOracle), (reverse, reverseOracle)].values()) {
    label compare loop {
      switch (ours.next(), theirs.next()) {
        case (null, null) { break compare };
        case (?(ak, av), ?(bk, bv)) { assert ak.order == bk.order and av == bv };
        case _ { assert false };
      }
    }
  }
};
i := 0;
while (i < 193) {
  let key : Key = {order = i * 89 % 193; var tag = 10000 + i};
  assert Map.replace(actual, descending, key, i) == Core.replace(expected, descending, key, i);
  let stored = switch (Map.getEntry(actual, descending, key)) { case (?pair) pair.0; case null Prim.trap("missing equal key") };
  stored.tag += 1;
  assert key.tag == 10001 + i;
  assert Map.take(actual, descending, key) == Core.take(expected, descending, key);
  Map.assertValid(actual, descending);
  i += 1;
};
assert Map.isEmpty(actual) and Core.isEmpty(expected);

// Nullable keys and values keep absence distinct from a stored null binding.
func optionOrder(a : ?Nat, b : ?Nat) : Map.Order {
  switch (a, b) {
    case (null, null) #equal;
    case (null, _) #less;
    case (_, null) #greater;
    case (?a, ?b) { if (a < b) #less else if (a == b) #equal else #greater };
  }
};
let nullable = Map.empty<?Nat, ?Nat>();
i := 0;
while (i < 100) { Map.add(nullable, optionOrder, ?i, ?i); i += 1 };
Map.add(nullable, optionOrder, null, null);
assert Map.get(nullable, optionOrder, null) == ?null;
assert Map.entries(nullable).next() == ?(null, null);
assert Map.replace(nullable, optionOrder, null, ?42) == ?null;
assert Map.take(nullable, optionOrder, null) == ??42;
assert Map.get(nullable, optionOrder, null) == null;
Map.assertValid(nullable, optionOrder);
