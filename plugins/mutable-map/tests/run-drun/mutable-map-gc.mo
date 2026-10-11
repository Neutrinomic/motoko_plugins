//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Map "mo:fast/Map";

actor {
  type Cell = {var count : Nat};
  type Payload = {revision : Nat; bytes : Blob; cell : Cell; read : () -> Nat};
  transient let tree = Map.empty<Nat, Payload>();
  transient let alias = tree;
  transient var copy = Map.empty<Nat, Payload>();
  transient let side = Map.singleton<Nat, Nat>(9, 0);
  transient let sharedCell : Cell = {var count = 0};
  transient var bytes : Blob = "";
  transient let removed : [var ?Payload] = Prim.Array_init<?Payload>(6, null);
  transient var live : [var [var Nat]] = [var];
  transient var generation = 0;
  transient var comparisons = 0;
  transient var reclaimedBefore = 0;
  transient var sawPendingCycle = false;
  transient var sawCompletedCycle = false;

  func compare(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func payload(revision : Nat) : Payload {
    {revision; bytes; cell = sharedCell; read = func() : Nat { sharedCell.count }}
  };
  func allocatingCompare(a : Nat, b : Nat) : Map.Order {
    comparisons += 1;
    // Nested reads on this map, writes to another map, and allocation are
    // permitted while native update frames retain managed nodes and values.
    switch (Map.getNat(alias, 511)) {
      case (?value) { assert value.cell.count == generation };
      case null Prim.trap("missing entry during comparator reentry");
    };
    Map.addNat(side, 9, comparisons);
    ignore Prim.Array_init<Nat>(2048, comparisons);
    compare(a, b)
  };
  func verifyPayload(value : Payload, revision : Nat) {
    assert value.revision == revision;
    assert value.bytes.size() == 1024 * 1024;
    assert value.bytes[0] == 17 and value.bytes[1024 * 1024 - 1] == 17;
    assert value.cell.count == generation and value.read() == generation;
  };
  func verify() {
    assert Map.size(tree) == 512 and Map.size(alias) == 512 and Map.size(copy) == 512;
    Map.assertValid(tree, compare);
    Map.assertValid(copy, compare);
    for (key in [0, 15, 127, 128, 511].values()) {
      switch (Map.get(alias, compare, key), Map.get(copy, compare, key)) {
        case (?current, ?original) {
          verifyPayload(current, if (key < 32 or key == 128) generation else 0);
          verifyPayload(original, 0);
        };
        case _ Prim.trap("missing retained map payload");
      }
    };
    var i = 0;
    while (i < generation) {
      switch (removed[i]) {
        case (?value) verifyPayload(value, i);
        case null Prim.trap("missing retained replacement result");
      };
      i += 1;
    };
  };

  public func prepare() : async () {
    bytes := Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) { 17 }));
    let value = payload(0);
    var key = 0;
    while (key < 512) { Map.add(tree, compare, key, value); key += 1 };
    copy := Map.clone(tree);

    let small = Map.empty<Nat, Blob>();
    let large = Map.empty<Nat, Blob>();
    key := 0;
    while (key < 512) {
      Map.addNat(small, key, ("tiny" : Blob));
      Map.addNat(large, key, bytes);
      key += 1;
    };
    let beforeSmall : Int = Prim.rts_total_allocation();
    Map.addNat(small, 128, ("tiny" : Blob));
    let smallAllocation = Prim.rts_total_allocation() - beforeSmall;
    let beforeLarge : Int = Prim.rts_total_allocation();
    Map.addNat(large, 128, bytes);
    let largeAllocation = Prim.rts_total_allocation() - beforeLarge;
    assert smallAllocation == largeAllocation;
    assert largeAllocation < 4096;
    assert Map.getNat(small, 128) == ?("tiny" : Blob);
    assert Map.getNat(large, 128) == ?bytes;

    // More than 96 MiB of live objects exceeds the incremental GC work budget.
    // Interleaved dead blocks force fragmentation and evacuation, while the
    // native point updates below run before this collection has completed.
    live := Prim.Array_tabulateVar<[var Nat]>(192, func(i) {
      ignore Prim.Array_init<Nat>(64 * 1024, 0);
      Prim.Array_init<Nat>(64 * 1024, i)
    });
    assert Prim.rts_heap_size() > 192 * 1024 * 1024;
    reclaimedBefore := Prim.rts_reclaimed();
    verify();
  };

  public func mutate() : async () {
    assert generation < 6;
    sawPendingCycle := sawPendingCycle or
      (Prim.rts_heap_size() > 96 * 1024 * 1024 and Prim.rts_max_live_size() < 96 * 1024 * 1024);
    sawCompletedCycle := sawCompletedCycle or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
    let previous = generation;
    generation += 1;
    sharedCell.count := generation;
    let value = payload(generation);
    removed[previous] := Map.swap(alias, allocatingCompare, 128, value);
    var key = 0;
    while (key < 32) { Map.add(tree, allocatingCompare, key, value); key += 1 };
    key := 512;
    while (key < 576) { Map.add(alias, allocatingCompare, key, value); key += 1 };
    while (key > 512) {
      key -= 1;
      switch (Map.take(tree, allocatingCompare, key)) {
        case (?removedValue) verifyPayload(removedValue, generation);
        case null Prim.trap("missing newly inserted entry");
      }
    };
    assert comparisons > 0 and Map.getNat(side, 9) == ?comparisons;
    assert live[0][65535] == 0 and live[191][65535] == 191;
    verify();
  };

  public func finish() : async () {
    // No mutation follows cursor creation: this checks retained cursor state
    // across GC without relying on invalidated-iterator behavior.
    let cursor = Map.entries(tree);
    var i = 0;
    while (i < 12) {
      ignore Prim.Array_init<Nat>(131072, i);
      await async {};
      verify();
      i += 1;
    };
    assert sawPendingCycle;
    assert sawCompletedCycle or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
    assert Prim.rts_reclaimed() > reclaimedBefore + 32 * 1024 * 1024;
    var expected = 0;
    for ((key, value) in cursor) {
      assert key == expected;
      verifyPayload(value, if (key < 32 or key == 128) generation else 0);
      expected += 1;
    };
    assert expected == 512;
    Prim.debugPrint("mutable-map aliases, shared payloads and callbacks survived incremental GC");
    Prim.debugPrint("mutable-map point allocation is independent of payload size");
  };
};

//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress mutate "DIDL\x00\x00"
//CALL ingress finish "DIDL\x00\x00"
