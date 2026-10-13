import Test "mo:test";
import Ring "mo:fast/HistoryRing";
import Prim "mo:⛔";

persistent actor {
  public query func test_empty_zero_capacity_and_sequence_continuity() : async Test.Metrics {
    Test.test(func() {
      for (capacity in [0, 1, 63, 64, 65, 100, 129].values()) {
        let ring = Ring.empty<Nat>(capacity);
        assert Ring.capacity(ring) == capacity;
        assert Ring.isEmpty(ring) and Ring.size(ring) == 0;
        assert Ring.firstSequence(ring) == 0 and Ring.nextSequence(ring) == 0;
        assert Ring.peekFront(ring) == null and Ring.peekBack(ring) == null;
        assert Ring.popFront(ring) == null and Ring.drop(ring, 99) == 0;
        assert Ring.get(ring, 0) == null and Ring.page(ring, 0, 99) == [];
        let iterator = Ring.values(ring);
        assert iterator.next() == null and iterator.next() == null;
        assert Ring.append(ring, 90) == 0;
        assert Ring.nextSequence(ring) == 1;
        assert Ring.size(ring) == (if (capacity == 0) 0 else 1);
        Ring.clear(ring);
        assert Ring.firstSequence(ring) == 1;
        assert Ring.append(ring, 91) == 1;
        assert Ring.get(ring, 0) == null;
        if (capacity == 0) assert Ring.get(ring, 1) == null else assert Ring.get(ring, 1) == ?91;
      }
    })
  };

  public query func test_wrap_growth_and_flat_array_oracle() : async Test.Metrics {
    Test.test(func() {
      for (capacity in [1, 3, 31, 63, 64, 65, 100, 127, 128, 129, 257].values()) {
        let ring = Ring.empty<Nat>(capacity);
        var model : [Nat] = [];
        var next = 0;
        var random = capacity + 1;
        var iteration = 0;
        while (iteration < 1000) {
          random := (random * 48271) % 2147483647;
          let op = random % 23;
          if (op == 0) { Ring.clear(ring); model := [] }
          else if (op == 1 or op == 2) {
            let count = random % 70;
            let removed = if (count < model.size()) count else model.size();
            assert Ring.drop(ring, count) == removed;
            let old = model;
            model := Prim.Array_tabulate<Nat>(old.size() - removed, func(i) { old[i + removed] });
          } else if (op == 3) {
            assert Ring.popFront(ring) == (if (model.size() == 0) null else ?model[0]);
            if (model.size() > 0) {
              let old = model;
              model := Prim.Array_tabulate<Nat>(old.size() - 1, func(i) { old[i + 1] });
            }
          } else {
            assert Ring.append(ring, random) == next;
            next += 1;
            let old = model;
            let full = old.size() == capacity;
            let length = if (full) old.size() else old.size() + 1;
            model := Prim.Array_tabulate<Nat>(length, func(i) {
              if (i + 1 == length) random else old[i + (if (full) 1 else 0)]
            });
          };
          assert Ring.size(ring) == model.size();
          assert Ring.firstSequence(ring) == next - model.size();
          assert Ring.nextSequence(ring) == next;
          if (iteration % 13 == 0) assert Ring.toArray(ring) == model;
          iteration += 1;
        };
        assert Ring.toArray(ring) == model;
      }
    })
  };

  public query func test_rotated_tail_survives_partial_drop() : async Test.Metrics {
    Test.test(func() {
      for (capacity in [1, 5, 63, 64, 65, 100, 127, 128, 129].values()) {
        for (bulk in [false, true].values()) {
          let ring = Ring.empty<Nat>(capacity);
          var i = 0;
          while (i <= capacity) { ignore Ring.append(ring, i); i += 1 };
          if (bulk) { assert Ring.drop(ring, capacity - 1) == capacity - 1 }
          else {
            i := 1;
            while (i < capacity) { assert Ring.popFront(ring) == ?i; i += 1 };
          };
          assert Ring.get(ring, capacity) == ?capacity;
          assert Ring.toArray(ring) == [capacity];
          assert Ring.append(ring, 777) == capacity + 1;
          assert Ring.peekBack(ring) == ?777;
        }
      }
    })
  };

  public query func test_pages_and_iterators_are_sequence_ordered() : async Test.Metrics {
    Test.test(func() {
      let ring = Ring.empty<Nat>(129);
      var i = 0;
      while (i < 400) { ignore Ring.append(ring, i * 3); i += 1 };
      assert Ring.firstSequence(ring) == 271;
      for (from in [0, 270, 271, 272, 320, 399, 400, 401, 2 ** 140].values()) {
        for (limit in [0, 1, 63, 64, 65, 129, 1000, 2 ** 140].values()) {
          let start = if (from < 271) 271 else if (from > 400) 400 else from;
          let available = 400 - start;
          let length = if (limit < available) limit else available;
          assert Ring.page(ring, from, limit) == Prim.Array_tabulate<Nat>(length, func(j) { (start + j) * 3 });
        }
      };
      let iterator = Ring.values(ring);
      i := 271;
      while (i < 400) { assert iterator.next() == ?(i * 3); i += 1 };
      assert iterator.next() == null and iterator.next() == null;
      let snapshot = Ring.page(ring, 397, 3);
      Ring.clear(ring);
      assert snapshot == [1191, 1194, 1197];
      // The chunk immediately after these exact-end pages is unallocated.
      // Finishing a page must not eagerly load that next chunk.
      let sparse = Ring.empty<Nat>(257);
      i := 0;
      while (i < 192) { ignore Ring.append(sparse, i); i += 1 };
      assert Ring.page(sparse, 128, 0) == [];
      assert Ring.page(sparse, 128, 64) == Prim.Array_tabulate<Nat>(64, func(j) { 128 + j });
      assert Ring.page(sparse, 0, 192) == Prim.Array_tabulate<Nat>(192, func(j) { j });
      assert Ring.page(sparse, 192, 0) == [];
      assert Ring.page(sparse, 192, 2 ** 140) == [];
      assert Ring.drop(sparse, 65) == 65;
      assert Ring.page(sparse, 64, 127) == Prim.Array_tabulate<Nat>(127, func(j) { 65 + j });
      while (i < 385) { ignore Ring.append(sparse, i); i += 1 };
      assert Ring.page(sparse, 319, 65) == Prim.Array_tabulate<Nat>(65, func(j) { 319 + j });
      assert Ring.toArray(sparse) == Prim.Array_tabulate<Nat>(257, func(j) { 128 + j });
    })
  };

  public query func test_nullable_shared_payloads_and_closures() : async Test.Metrics {
    Test.test(func() {
      let ring = Ring.empty<?Null>(65);
      var i = 0;
      while (i < 200) { ignore Ring.append(ring, if (i % 2 == 0) null else ?null); i += 1 };
      assert Ring.get(ring, 135) == ??null;
      assert Ring.get(ring, 136) == ?null;
      assert Ring.get(ring, 134) == null;
      assert Ring.page(ring, 135, 3) == [?null, null, ?null];
      assert Ring.popFront(ring) == ??null;
      assert Ring.popFront(ring) == ?null;
      type Payload = {var count : Nat; read : () -> Nat};
      var count = 10;
      let value : Payload = {var count = 0; read = func() : Nat { count }};
      let refs = Ring.empty<?Payload>(129);
      i := 0;
      while (i < 400) { ignore Ring.append(refs, ?value); i += 1 };
      let snapshot = Ring.page(refs, 300, 2);
      switch (snapshot[0]) { case (?v) v.count := 99; case null assert false };
      count := 20;
      assert value.count == 99;
      for (payload in Ring.values(refs)) {
        switch payload { case (?v) assert v.count == 99 and v.read() == 20; case null assert false }
      };
      Ring.clear(refs);
      switch (snapshot[1]) { case (?v) assert v.count == 99 and v.read() == 20; case null assert false };
    })
  };

  public query func test_arbitrary_nat_sequence_and_lazy_huge_capacity() : async Test.Metrics {
    Test.test(func() {
      for (initial in [2 ** 30 - 2, 2 ** 60 - 2, 2 ** 61 - 2, 2 ** 62 - 2, 2 ** 63 - 2, 2 ** 64 - 2, 2 ** 140].values()) {
        let ring = Ring.emptyAt<Nat>(65, initial);
        var i = 0;
        while (i < 200) {
          assert Ring.append(ring, i) == initial + i;
          if (i < 8) {
            // Oldest and newest sequences straddle the compact/bigint boundary.
            assert Ring.get(ring, initial) == ?0;
            assert Ring.get(ring, initial + i) == ?i;
            assert Ring.page(ring, initial, 2 ** 140) == Prim.Array_tabulate<Nat>(i + 1, func(j) { j });
          };
          i += 1;
        };
        assert Ring.firstSequence(ring) == initial + 135;
        assert Ring.nextSequence(ring) == initial + 200;
        assert Ring.page(ring, initial + 198, 2 ** 140) == [198, 199];
        assert Ring.drop(ring, 2 ** 140) == 65;
        assert Ring.firstSequence(ring) == initial + 200;
        assert Ring.append(ring, 200) == initial + 200;
      };
      let capacity = 2 ** 140;
      let initial = 2 ** 140;
      let before = Prim.rts_total_allocation();
      let huge = Ring.emptyAt<Nat>(capacity, initial);
      let allocated = Prim.rts_total_allocation() - before;
      assert allocated < 1024;
      var i = 0;
      while (i < 129) { assert Ring.append(huge, i) == 2 ** 140 + i; i += 1 };
      assert Ring.size(huge) == 129 and Ring.capacity(huge) == 2 ** 140;
      assert Ring.page(huge, 0, 2 ** 140).size() == 129;
      assert Ring.get(huge, 2 ** 140 + 128) == ?128;
    })
  };

  public query func test_removed_slots_release_payload_references() : async Test.Metrics {
    Test.test(func() {
      // White-box storage invariant complements observable sequence tests:
      // removed payloads cannot remain reachable through spare chunk slots.
      for (capacity in [1, 63, 64, 65, 100, 129, 257].values()) {
        let ring = Ring.empty<Text>(capacity);
        var generation = 0;
        while (generation < 20) {
          var i = 0;
          while (i < capacity + 17) { ignore Ring.append(ring, "retained payload"); i += 1 };
          let drops = [0, 1, 63, 64, 65, 127, 128, 129];
          ignore Ring.drop(ring, drops[generation % drops.size()]);
          var occupied = 0;
          var slots = 0;
          for (chunk in ring.chunks.values()) {
            switch chunk {
              case null {};
              case (?cells) {
                slots += cells.size();
                for (cell in cells.values()) { switch cell { case null {}; case (?_) occupied += 1 } };
              }
            }
          };
          assert occupied == Ring.size(ring);
          assert slots <= capacity + 63;
          generation += 1;
        };
        Ring.clear(ring);
        assert ring.chunks.size() == 0;
      }
    })
  };

  public func test_references_survive_incremental_gc_and_message_boundaries() : async Test.Metrics {
    type Payload = {sequence : Nat; bytes : Blob; cell : {var count : Nat}; read : () -> Nat};
    let ring = Ring.empty<Payload>(129);
    let nullable = Ring.empty<?Null>(65);
    let cell = {var count = 0};
    let bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) { 37 }));
    var next = 0;
    func runtimeNull() : ?Null {
      // Decode freshly allocated optional-null boxes, not an immortal literal.
      let decoded : ??Null = from_candid(to_candid(?null : ?Null));
      switch decoded { case (?value) value; case null Prim.trap("null decode failed") }
    };
    func append(count : Nat) {
      var i = 0;
      while (i < count) {
        let payload : Payload = {sequence = next; bytes; cell; read = func() : Nat { cell.count }};
        assert Ring.append(ring, payload) == next;
        ignore Ring.append(nullable, if (next % 2 == 0) null else runtimeNull());
        next += 1;
        i += 1;
      }
    };
    func verify() {
      var expected = Ring.firstSequence(ring);
      for (value in Ring.values(ring)) {
        assert value.sequence == expected;
        assert value.cell.count == cell.count and value.read() == cell.count;
        assert value.bytes.size() == 1024 * 1024;
        assert value.bytes[0] == 37 and value.bytes[1024 * 1024 - 1] == 37;
        expected += 1;
      };
      assert expected == next;
      var sequence = Ring.firstSequence(nullable);
      let page = Ring.toArray(nullable);
      var index = 0;
      while (sequence < next) {
        assert Ring.get(nullable, sequence) == (if (sequence % 2 == 0) ?null else ??null);
        assert page[index] == (if (sequence % 2 == 0) null else ?null);
        sequence += 1;
        index += 1;
      }
    };
    append(270);
    let live = Prim.Array_tabulateVar<[var Nat]>(192, func(n) {
      ignore Prim.Array_init<Nat>(64 * 1024, 0);
      Prim.Array_init<Nat>(64 * 1024, n)
    });
    assert Prim.rts_heap_size() > 192 * 1024 * 1024;
    let reclaimedBefore = Prim.rts_reclaimed();
    var sawPendingCycle = false;
    var round = 0;
    await async {};
    while (round < 10) {
      sawPendingCycle := sawPendingCycle or
        (Prim.rts_heap_size() > 96 * 1024 * 1024 and Prim.rts_max_live_size() < 96 * 1024 * 1024);
      cell.count += 1;
      let remove = 63 + round % 3;
      assert Ring.drop(ring, remove) == remove;
      ignore Ring.popFront(ring);
      append(71);
      verify();
      assert live[0][65535] == 0 and live[191][65535] == 191;
      await async {};
      round += 1;
    };
    let iterator = Ring.values(ring);
    round := 0;
    while (round < 12) {
      ignore Prim.Array_init<Nat>(131072, round);
      await async {};
      verify();
      assert live[0][65535] == 0 and live[191][65535] == 191;
      round += 1;
    };
    assert sawPendingCycle;
    assert Prim.rts_reclaimed() > reclaimedBefore + 32 * 1024 * 1024;
    return Test.test(func() {
      var count = 0;
      for (value in iterator) { assert value.read() == 10; count += 1 };
      assert count == 129;
      verify();
    })
  };
}
