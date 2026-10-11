import Test "mo:test";
import Set "mo:fast/Set";
import Nat "mo:core/Nat";
import Prim "mo:⛔";

// Direct intrinsic calls deliberately instantiate the shared native helpers
// with immediate element types before using them with heap references. The
// public module supplies construction, iteration, and invariant checks.
persistent actor {
  type Key = {id : Nat; generation : Nat; bytes : Blob; cell : {var value : Nat}; read : () -> Nat};
  func compareKey(a : Key, b : Key) : Set.Order { Nat.compare(a.id, b.id) };
  func compareOptional(a : ??Key, b : ??Key) : Set.Order {
    switch (a, b) {
      case (null, null) #equal;
      case (null, _) #less;
      case (_, null) #greater;
      case (?null, ?null) #equal;
      case (?null, _) #less;
      case (_, ?null) #greater;
      case (??x, ??y) compareKey(x, y);
    }
  };

  public func test_shared_helpers_preserve_references_across_incremental_gc() : async Test.Metrics {
    var i = 0;

    let keys = Set.empty<Key>();
    let nullable = Set.empty<??Key>();
    let texts = Set.empty<Text>();
    let side = Set.empty<Nat>();
    let sharedCell = {var value = 0};
    let bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) { 17 }));
    var generation = 0;
    var comparisons = 0;
    func key(id : Nat) : Key {
      {id; generation; bytes; cell = sharedCell; read = func() : Nat { sharedCell.value }}
    };
    func allocatingCompare(a : Key, b : Key) : Set.Order {
      comparisons += 1;
      // Reading this set and mutating another set during a comparator are
      // supported. Allocation stresses native frames retaining managed keys.
      assert Prim.mset_contains<Key>(keys, compareKey, key(2047));
      Prim.mset_add_static<Nat>(side, comparisons);
      ignore Prim.Array_init<Nat>(64, comparisons);
      compareKey(a, b)
    };
    func verifyKey(value : Key, expected : Nat) {
      assert value.id == expected;
      assert value.generation == (if (expected < 128) generation else 0);
      assert value.bytes.size() == 1024 * 1024;
      assert value.bytes[0] == 17 and value.bytes[1024 * 1024 - 1] == 17;
      assert value.cell.value == generation and value.read() == generation;
    };
    func verify() {
      assert Set.size(keys) == 2048 and Set.size(nullable) == 2050;
      assert Set.size(texts) == 2048;
      Set.assertValid(keys, compareKey);
      Set.assertValid(nullable, compareOptional);
      var expected = 0;
      for (value in Set.values(keys)) { verifyKey(value, expected); expected += 1 };
      assert expected == 2048;
      let cursor = Set.values(nullable);
      switch (cursor.next()) { case (?null) {}; case _ assert false };
      switch (cursor.next()) { case (??null) {}; case _ assert false };
      expected := 0;
      for (value in cursor) {
        switch value {
          case (??value) verifyKey(value, expected);
          case _ assert false;
        };
        expected += 1;
      };
      assert expected == 2048;
      for (n in [0, 15, 127, 128, 1023, 2047].values()) {
        assert Prim.mset_contains_static<Text>(texts, Nat.toText(n));
      };
    };
    Prim.mset_add<??Key>(nullable, compareOptional, null);
    Prim.mset_add<??Key>(nullable, compareOptional, ?null);
    i := 0;
    while (i < 2048) {
      let value = key(i);
      Prim.mset_add<Key>(keys, compareKey, value);
      Prim.mset_add<??Key>(nullable, compareOptional, ??value);
      Prim.mset_add_static<Text>(texts, Nat.toText(i));
      i += 1;
    };
    verify();

    // 96 MiB of retained objects exceeds one incremental collection slice.
    // Interleaved dead blocks additionally force evacuation and pointer
    // forwarding. Mutation happens while this cycle is still pending.
    let live = Prim.Array_tabulateVar<[var Nat]>(192, func(n) {
      ignore Prim.Array_init<Nat>(64 * 1024, 0);
      Prim.Array_init<Nat>(64 * 1024, n)
    });
    assert Prim.rts_heap_size() > 192 * 1024 * 1024;
    let reclaimedBefore = Prim.rts_reclaimed();
    var sawPendingCycle = false;
    var sawCompletedCycle = false;
    await async {};
    while (generation < 8) {
      sawPendingCycle := sawPendingCycle or
        (Prim.rts_heap_size() > 96 * 1024 * 1024 and Prim.rts_max_live_size() < 96 * 1024 * 1024);
      sawCompletedCycle := sawCompletedCycle or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
      generation += 1;
      sharedCell.value := generation;
      i := 0;
      while (i < 128) {
        let value = key(i);
        Prim.mset_add<Key>(keys, allocatingCompare, value);
        Prim.mset_add<??Key>(nullable, compareOptional, ??value);
        Prim.mset_add_static<Text>(texts, Nat.toText(i));
        i += 1;
      };
      // Remove and reinsert low keys, exercising sibling borrowing, merging,
      // split helpers, and moved reference slots under both ordering paths.
      i := 0;
      while (i < 96) {
        assert Prim.mset_delete<Key>(keys, allocatingCompare, key(i));
        assert Prim.mset_delete<??Key>(nullable, compareOptional, ??key(i));
        assert Prim.mset_delete_static<Text>(texts, Nat.toText(i));
        i += 1;
      };
      i := 96;
      while (i > 0) {
        i -= 1;
        let value = key(i);
        Prim.mset_add<Key>(keys, allocatingCompare, value);
        Prim.mset_add<??Key>(nullable, compareOptional, ??value);
        Prim.mset_add_static<Text>(texts, Nat.toText(i));
      };
      assert live[0][65535] == 0 and live[191][65535] == 191;
      verify();
      await async {};
    };
    // Retain an iterator over another series of collections. There are no
    // mutations after its creation, respecting the invalidation contract.
    let retainedCursor = Set.values(keys);
    i := 0;
    while (i < 12) {
      ignore Prim.Array_init<Nat>(131072, i);
      await async {};
      assert live[0][65535] == 0 and live[191][65535] == 191;
      verify();
      i += 1;
    };
    assert sawPendingCycle;
    assert sawCompletedCycle or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
    assert Prim.rts_reclaimed() > reclaimedBefore + 32 * 1024 * 1024;
    assert comparisons > 0 and Set.size(side) == comparisons;
    return Test.test(func() {
      var expected = 0;
      for (value in retainedCursor) { verifyKey(value, expected); expected += 1 };
      assert expected == 2048;
      verify();
    })
  };

  // Actor methods are emitted in reverse declaration order. This last method
  // forces scalar specializations to define shared helpers before the GC test.
  public query func test_scalar_specialization_seed() : async Test.Metrics {
    Test.test(func() {
      let bools = Set.empty<Bool>();
      func compareBool(a : Bool, b : Bool) : Set.Order {
        if (a == b) #equal else if (a) #greater else #less
      };
      Prim.mset_add<Bool>(bools, compareBool, false);
      Prim.mset_add<Bool>(bools, compareBool, true);
      assert Prim.mset_delete<Bool>(bools, compareBool, false);
      let small = Set.empty<Nat8>();
      var i = 0;
      while (i < 128) {
        Prim.mset_add_static<Nat8>(small, Prim.natToNat8(i));
        i += 1;
      };
      i := 0;
      while (i < 64) {
        assert Prim.mset_delete_static<Nat8>(small, Prim.natToNat8(i));
        i += 1;
      };
      assert Set.size(bools) == 1 and Set.size(small) == 64;
    })
  };
}
