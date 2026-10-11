//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Map "mo:fast/Map";

actor {
  type Cell = {var count : Nat};
  type Payload = {revision : Nat; bytes : Blob; cell : Cell};
  let tree = Map.empty<Nat, Payload>();
  let alias = tree;
  let sharedCell : Cell = {var count = 0};
  var copy = Map.empty<Nat, Payload>();
  var retained : ?Payload = null;
  var bytes : Blob = "";
  var generation = 0;

  func compare(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func valueAt(map : Map.Map<Nat, Payload>, key : Nat) : Payload {
    switch (Map.get(map, compare, key)) {
      case (?value) value;
      case null Prim.trap("missing upgraded map entry");
    }
  };
  func verify() {
    assert Map.size(tree) == 1024 and Map.size(alias) == 1024 and Map.size(copy) == 1024;
    Map.assertValid(tree, compare);
    Map.assertValid(copy, compare);
    let current = valueAt(alias, 128);
    let original = valueAt(copy, 128);
    assert current.revision == generation and original.revision == 0;
    assert current.cell.count == generation and original.cell.count == generation;
    assert sharedCell.count == generation;
    for (value in [current, original, valueAt(tree, 1023)].values()) {
      assert value.bytes.size() == 1024 * 1024;
      assert value.bytes[0] == 29 and value.bytes[1024 * 1024 - 1] == 29;
    };
    switch retained {
      case (?value) {
        assert generation > 0;
        assert value.revision + 1 == generation;
        assert value.cell.count == generation;
      };
      case null { assert generation == 0 };
    }
  };

  public func prepare() : async () {
    assert Map.isEmpty(tree);
    bytes := Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) { 29 }));
    let value : Payload = {revision = 0; bytes; cell = sharedCell};
    var key = 0;
    while (key < 1024) { Map.add(tree, compare, key, value); key += 1 };
    copy := Map.clone(tree);
    verify();
  };

  public func change() : async () {
    verify();
    generation += 1;
    // This write must reach the original payload and the cloned tree's payload:
    // stable aliases are preserved, even though their map nodes are independent.
    valueAt(copy, 128).cell.count += 1;
    let next : Payload = {revision = generation; bytes; cell = sharedCell};
    retained := Map.swap(alias, compare, 128, next);
    assert valueAt(tree, 128).revision == generation;
    assert Map.delete(tree, compare, 0);
    switch (Map.get(alias, compare, 0)) {
      case null {};
      case _ Prim.trap("deletion was not visible through retained alias");
    };
    assert valueAt(copy, 0).revision == 0;
    Map.add(alias, compare, 0, next);
    assert valueAt(tree, 0).revision == generation;
    verify();
  };

  public func collectAndCheck() : async () {
    let before = Prim.rts_reclaimed();
    var i = 0;
    while (i < 8) { ignore Prim.Array_init<Nat>(1024 * 1024, i); i += 1 };
    i := 0;
    while (i < 4) { await async {}; verify(); i += 1 };
    assert Prim.rts_reclaimed() > before + 16 * 1024 * 1024;
    Prim.debugPrint("mutable-map upgrade preserved aliases, cloned nodes and shared payloads");
  };
};

//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL upgrade ""
//CALL ingress change "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
//CALL upgrade ""
//CALL ingress change "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
