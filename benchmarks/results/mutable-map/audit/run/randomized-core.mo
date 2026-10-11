//MOC-FLAG --plugin ../../../../../dist/mutable-map
//MOC-FLAG --package core $MOTOKO_CORE -A M0236
import Prim "mo:⛔";
import Map "../../../../../plugins/mutable-map/motoko/Map";
import Core "mo:core/Map";

for (seed in ([0x001234ab, 0xfacdde12, 0x78392615] : [Nat32]).values()) {
  var rng = seed;
  func random(limit : Nat) : Nat {
    rng := rng ^ (rng << 13); rng := rng ^ (rng >> 17); rng := rng ^ (rng << 5);
    Prim.nat32ToNat(rng) % limit
  };
  let reverse = random(2) == 0;
  func cmp(a : ?Int, b : ?Int) : Map.Order {
    let result = switch (a, b) {
      case (null, null) #equal; case (null, _) #less; case (_, null) #greater;
      case (?a, ?b) { if (a < b) #less else if (a == b) #equal else #greater }
    };
    if (not reverse) result else switch result { case (#less) #greater; case (#greater) #less; case (#equal) #equal }
  };
  let actual = Map.empty<?Int, ??Nat>();
  let expected = Core.empty<?Int, ??Nat>();
  var step = 0;
  while (step < 2400) {
    let key : ?Int = if (random(97) == 0) null else ?(random(400) - (200 : Int));
    let value : ??Nat = switch (random(3)) { case 0 null; case 1 ?null; case _ ??random(999999) };
    switch (random(10)) {
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
    if (step % 37 == 0) {
      Map.assertValid(actual, cmp);
      assert Map.size(actual) == Core.size(expected);
      assert Map.toArray(actual) == Core.toArray(expected);
      let forward = Core.entriesFrom(expected, cmp, key);
      for (entry in Map.entriesFrom(actual, cmp, key)) assert forward.next() == ?entry;
      assert forward.next() == null;
      let backward = Core.reverseEntriesFrom(expected, cmp, key);
      for (entry in Map.reverseEntriesFrom(actual, cmp, key)) assert backward.next() == ?entry;
      assert backward.next() == null;
    };
    step += 1;
  };
  Map.assertValid(actual, cmp);
  assert Map.toArray(actual) == Core.toArray(expected);
};
Prim.debugPrint("audit: 7200 seeded operations and inclusive seeks matched core mutable Map");
