//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src
//MOC-FLAG --package core $MOTOKO_CORE --sanity-checks -A M0236
import Prim "mo:prim";
import Map "mo:fast/Map";
import Core "mo:core/Map";

// Records and a descending primary order keep this on the dynamic comparator
// path. Core's separately implemented tree supplies the independent oracle.
type Key = { rank : Nat; lane : Nat };
var comparisons = 0;
func compare(a : Key, b : Key) : Map.Order {
  comparisons += 1;
  if (a.rank > b.rank) #less else if (a.rank < b.rank) #greater
  else if (a.lane < b.lane) #less else if (a.lane > b.lane) #greater
  else #equal
};
func key(value : Nat) : Key { { rank = value / 7; lane = value % 7 } };
let actual = Map.empty<Key, ?Nat>();
let expected = Core.empty<Key, ?Nat>();
var checks = 0;
func check() {
  let before = comparisons;
  assert Map.minEntry(actual) == Core.minEntry(expected);
  assert Map.maxEntry(actual) == Core.maxEntry(expected);
  assert comparisons == before;
  assert Map.size(actual) == Core.size(expected);
  checks += 1;
};
func fullCheck() {
  check();
  Map.assertValid(actual, compare);
  assert Map.toArray(actual) == Core.toArray(expected);
};
var randomState : Nat32 = 0x1a59ce73;
func random(limit : Nat) : Nat {
  randomState := randomState *% 1664525 +% 1013904223;
  Prim.nat32ToNat(randomState) % limit
};

check();
var i = 0;
while (i < 1024) {
  let selected = key(i * 997 % 1024);
  let value = if (i % 11 == 0) null else ?i;
  Map.add(actual, compare, selected, value);
  Core.add(expected, compare, selected, value);
  check();
  i += 1;
};
fullCheck();

// Every update is immediately followed by both extrema checks. Pruning removes
// short prefixes/suffixes without constructing a traversal or sorting keys.
i := 0;
while (i < 8000) {
  let selected = key(random(1400));
  let value : ?Nat = if (random(5) == 0) null else ?random(1000000);
  switch (random(10)) {
    case 0 {
      assert Map.insert(actual, compare, selected, value) ==
        Core.insert(expected, compare, selected, value);
    };
    case 1 {
      assert Map.swap(actual, compare, selected, value) ==
        Core.swap(expected, compare, selected, value);
    };
    case 2 {
      assert Map.replace(actual, compare, selected, value) ==
        Core.replace(expected, compare, selected, value);
    };
    case 3 {
      assert Map.take(actual, compare, selected) ==
        Core.take(expected, compare, selected);
    };
    case 4 {
      assert Map.delete(actual, compare, selected) ==
        Core.delete(expected, compare, selected);
    };
    case 5 {
      Map.remove(actual, compare, selected);
      Core.remove(expected, compare, selected);
    };
    case 6 {
      var remaining = 1 + random(8);
      while (remaining > 0 and Core.size(expected) > 0) {
        let extreme = if (i % 2 == 0) Core.minEntry(expected)
          else Core.maxEntry(expected);
        switch extreme {
          case (?(selected, _)) {
            assert Map.take(actual, compare, selected) ==
              Core.take(expected, compare, selected);
          };
          case null assert false;
        };
        check();
        remaining := Prim.abs((remaining : Int) - 1);
      };
    };
    case _ {
      Map.add(actual, compare, selected, value);
      Core.add(expected, compare, selected, value);
    };
  };
  check();
  if (i % 127 == 0) fullCheck();
  i += 1;
};
fullCheck();

// Alternating extrema removal crosses merges and root shrink down to empty.
while (Core.size(expected) > 0) {
  let extreme = if (Core.size(expected) % 2 == 0) Core.minEntry(expected)
    else Core.maxEntry(expected);
  switch extreme {
    case (?(selected, _)) {
      assert Map.take(actual, compare, selected) ==
        Core.take(expected, compare, selected);
    };
    case null assert false;
  };
  check();
};
fullCheck();
assert Map.minEntry(actual) == null and Map.maxEntry(actual) == null;
assert checks > 9000;

// Extrema preserve the exact mutable keys and nullable payloads, including
// closure captures. Copying either mutable object would break these aliases.
type RefKey = { order : Nat; var tag : Nat };
type Payload = { var count : Nat; invoke : () -> Nat };
func refCompare(a : RefKey, b : RefKey) : Map.Order {
  if (a.order > b.order) #less else if (a.order < b.order) #greater else #equal
};
let refs = Map.empty<RefKey, ?Payload>();
let first : RefKey = { order = 99; var tag = 0 };
let last : RefKey = { order = 1; var tag = 0 };
var captured = 0;
let payload : Payload = { var count = 0;
  invoke = func() : Nat { captured += 1; captured } };
Map.add(refs, refCompare, first, null);
Map.add(refs, refCompare, last, ?payload);
switch (Map.minEntry(refs)) {
  case (?(stored, null)) { stored.tag := 42 };
  case _ assert false;
};
assert first.tag == 42;
switch (Map.maxEntry(refs)) {
  case (?(stored, ?value)) {
    stored.tag := 77;
    value.count += 1;
    assert value.invoke() == 1;
  };
  case _ assert false;
};
assert last.tag == 77 and payload.count == 1 and payload.invoke() == 2;
Map.add(refs, refCompare, first, ?payload);
switch (Map.minEntry(refs), Map.maxEntry(refs)) {
  case (?(_, ?minimum), ?(_, ?maximum)) {
    minimum.count += 1;
    assert maximum.count == 2 and payload.count == 2;
  };
  case _ assert false;
};
Prim.debugPrint("mutable-map extrema passed 8000 mixed Core-oracle operations and identity checks");
