//MOC-FLAG --plugin ../../../../dist/mutable-map
//MOC-FLAG --sanity-checks -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Map "../../motoko/Map";
actor {
  let tree = Map.empty<Nat, Nat>();
  func missing(_ : Nat, _ : Nat) : Bool { false };
  func last(key : Nat, _ : Nat) : Bool { key == 1023 };
  public func check() : async () {
    var i = 0;
    while (i < 1024) { Map.addNat(tree, i, i); i += 1 };
    let beforeMissing : Int = Prim.rts_total_allocation();
    let absent = Map.find(tree, missing);
    let missingAllocation = Prim.rts_total_allocation() - beforeMissing;
    let beforeLast : Int = Prim.rts_total_allocation();
    let found = Map.find(tree, last);
    let lastAllocation = Prim.rts_total_allocation() - beforeLast;
    assert absent == null and found == ?(1023, 1023);
    // Traversing must reuse stored entry tuples rather than rebox every pair.
    assert missingAllocation < 512 and lastAllocation < 512;
    assert Map.minEntry(tree) == ?(0, 0);
    assert Map.maxEntry(tree) == ?(1023, 1023);
    Prim.debugPrint("mutable-map find traverses without per-entry tuple garbage");
  };
};
//CALL ingress check "DIDL\x00\x00"
