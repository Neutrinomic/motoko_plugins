import Test "mo:test";
import Q "mo:fast/Queue";
import Prim "mo:⛔";

persistent actor {
  let management : actor {raw_rand : shared () -> async Blob} = actor "aaaaa-aa";
  public func test_payloads_survive_incremental_collection() : async Test.Metrics {
    type Value = {id : Nat; cell : {var value : Nat}; read : () -> Nat; bytes : Blob};
    let cell = {var value = 0};
    let bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) { 19 }));
    let queue = Q.empty<Value>();
    let nested = Q.empty<??Value>();
    let nulls = Q.empty<?Null>();
    let erased = Q.empty<Any>();
    func value(id : Nat) : Value { {id; cell; read = func() : Nat { cell.value }; bytes} };
    func erasedValue(id : Nat) : Any {
      switch (id % 4) { case 0 null; case 1 ?null; case 2 value(id); case _ ??value(id) }
    };
    var front = 0;
    var generation = 0;
    var i = 0;
    while (i < 1024) {
      Q.pushBack(queue, value(i));
      Q.pushBack(nested, ??value(i));
      Q.pushBack(nulls, if (i % 2 == 0) null else ?null);
      Q.pushBack(erased, erasedValue(i));
      i += 1;
    };
    func verify() {
      assert Q.size(queue) == 1024 and Q.size(nested) == 1024 and Q.size(nulls) == 1024;
      assert Q.size(erased) == 1024;
      Q.assertValid(queue); Q.assertValid(nested); Q.assertValid(nulls); Q.assertValid(erased);
      var erasedCount = 0;
      for (_ in Q.values(erased)) { erasedCount += 1 };
      assert erasedCount == 1024;
      var expected = front;
      for (v in Q.values(queue)) {
        assert v.id == expected and v.read() == generation and v.cell.value == generation;
        assert v.bytes.size() == 1024 * 1024 and v.bytes[0] == 19 and v.bytes[1024 * 1024 - 1] == 19;
        expected += 1;
      };
      expected := front;
      for (v in Q.values(nested)) {
        switch v { case (??item) assert item.id == expected and item.read() == generation; case _ assert false };
        expected += 1;
      };
      expected := front;
      for (v in Q.values(nulls)) { assert v == (if (expected % 2 == 0) null else ?null); expected += 1 };
      expected := front + 1024;
      for (v in Q.reverseValues(queue)) { expected -= 1; assert v.id == expected };
      assert expected == front;
    };
    verify();
    // 96 MiB remains live between dead blocks, so collection spans messages.
    let live = Prim.Array_tabulateVar<[var Nat]>(192, func(n) {
      ignore Prim.Array_init<Nat>(64 * 1024, 0);
      Prim.Array_init<Nat>(64 * 1024, n)
    });
    assert Prim.rts_heap_size() > 192 * 1024 * 1024;
    let reclaimedBefore = Prim.rts_reclaimed();
    var sawPending = false;
    var sawCompleted = false;
    ignore await management.raw_rand();
    while (generation < 8) {
      sawPending := sawPending or (Prim.rts_heap_size() > 96 * 1024 * 1024 and Prim.rts_max_live_size() < 96 * 1024 * 1024);
      sawCompleted := sawCompleted or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
      generation += 1;
      cell.value := generation;
      // Pop and replace enough items to detach and allocate multiple chunks.
      i := 0;
      while (i < 99) {
        switch (Q.popFront(queue)) { case (?v) assert v.id == front; case null assert false };
        switch (Q.popFront(nested)) { case (???v) assert v.id == front; case _ assert false };
        assert Q.popFront(nulls) == (if (front % 2 == 0) ?null else ??null);
        switch (Q.popFront(erased)) { case (?_) {}; case null assert false };
        let next = front + 1024;
        Q.pushBack(queue, value(next));
        Q.pushBack(nested, ??value(next));
        Q.pushBack(nulls, if (next % 2 == 0) null else ?null);
        Q.pushBack(erased, erasedValue(next));
        front += 1;
        i += 1;
      };
      // Exercise the opposite allocation/detachment path under the same GC.
      i := 0;
      while (i < 65) { Q.pushFront(queue, value(50_000 + i)); i += 1 };
      while (i > 0) {
        i -= 1;
        switch (Q.popFront(queue)) { case (?v) assert v.id == 50_000 + i; case null assert false };
      };
      i := 0;
      while (i < 65) { Q.pushBack(queue, value(60_000 + i)); i += 1 };
      while (i > 0) {
        i -= 1;
        switch (Q.popBack(queue)) { case (?v) assert v.id == 60_000 + i; case null assert false };
      };
      assert live[0][65535] == 0 and live[191][65535] == 191;
      verify();
      // Native array stores run while the collection is pending, then their
      // results remain live across the next message and pointer forwarding.
      let immutableExport = Q.toArray(queue);
      let mutableExport = Q.toVarArray(nested);
      let nullableExport = Q.toArray(nulls);
      let erasedExport = Q.toArray(erased);
      let erasedMutableExport = Q.toVarArray(erased);
      ignore await management.raw_rand();
      assert erasedExport.size() == 1024 and erasedMutableExport.size() == 1024;
      var exportIndex = 0;
      while (exportIndex < 1024) {
        assert immutableExport[exportIndex].id == front + exportIndex;
        assert immutableExport[exportIndex].read() == generation;
        switch (mutableExport[exportIndex]) {
          case (??v) assert v.id == front + exportIndex and v.read() == generation;
          case _ assert false;
        };
        assert nullableExport[exportIndex] == (if ((front + exportIndex) % 2 == 0) null else ?null);
        exportIndex += 1;
      };
    };
    let forward = Q.values(queue);
    let reverse = Q.reverseValues(queue);
    i := 0;
    while (i < 12) {
      ignore Prim.Array_init<Nat>(131072, i);
      ignore await management.raw_rand();
      assert live[0][65535] == 0 and live[191][65535] == 191;
      verify();
      i += 1;
    };
    assert sawPending;
    assert sawCompleted or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
    assert Prim.rts_reclaimed() > reclaimedBefore + 32 * 1024 * 1024;
    var expected = front;
    for (v in forward) { assert v.id == expected and v.read() == 8; expected += 1 };
    assert expected == front + 1024;
    for (v in reverse) { expected -= 1; assert v.id == expected and v.read() == 8 };
    assert expected == front;
    Q.clear(queue); Q.clear(nested); Q.clear(nulls); Q.clear(erased);
    i := 0;
    while (i < 8) {
      ignore Prim.Array_init<Nat>(131072, i);
      ignore await management.raw_rand();
      i += 1;
    };
    Test.test(func() {
      switch (forward.next(), reverse.next()) { case (null, null) {}; case _ assert false };
      switch (forward.next(), reverse.next()) { case (null, null) {}; case _ assert false };
      assert Q.isEmpty(queue) and Q.isEmpty(nested) and Q.isEmpty(nulls) and Q.isEmpty(erased);
    })
  };

  // Focused representation invariant, not a heap-size proxy. A popped slot or
  // detached link must release its reference immediately, even if the collector
  // keeps the allocation partition reserved for later reuse.
  public query func test_vacated_slots_and_detached_links_release_references() : async Test.Metrics {
    Test.test(func() {
      let queue = Q.empty<Blob>();
      let bytes : Blob = "payload";
      func endpoint(value : ?Q.Chunk<Blob>) : Q.Chunk<Blob> {
        switch value { case (?chunk) chunk; case null Prim.trap("missing chunk") }
      };
      func cleared(chunk : Q.Chunk<Blob>) {
        // The sole retained empty endpoint may keep its low five start bits.
        assert chunk.meta >> 5 == 0;
        switch (chunk.previous, chunk.next) { case (null, null) {}; case _ assert false };
        for (value in chunk.values.values()) { assert value == null };
      };
      func clearedSpare() {
        let spare = endpoint(queue.spare);
        assert spare.meta == 0;
        cleared(spare);
      };
      var i = 0;
      while (i < 96) { Q.pushBack(queue, bytes); i += 1 };
      let front = endpoint(queue.front);
      let back = endpoint(queue.back);
      i := 0;
      while (i < 32) { assert Q.popFront(queue) == ?bytes; i += 1 };
      cleared(front);
      assert front.meta == 0;
      i := 0;
      while (i < 32) { assert Q.popBack(queue) == ?bytes; i += 1 };
      cleared(back);
      assert back.meta == 0;
      let remaining = endpoint(queue.front);
      i := 0;
      while (i < 32) { assert Q.popFront(queue) == ?bytes; i += 1 };
      cleared(remaining);
      Q.assertValid(queue);
      switch (queue.spare) { case null {}; case _ assert false };
      Q.pushFront(queue, bytes);
      assert Q.popBack(queue) == ?bytes;
      cleared(remaining);
      i := 0;
      while (i < 32) { Q.pushBack(queue, bytes); i += 1 };
      // Full-chunk LIFO churn alternates which endpoint consumes the bounded
      // spare. The spare must always be completely cleared and unlinked.
      i := 0;
      while (i < 128) {
        Q.pushFront(queue, bytes);
        assert Q.popFront(queue) == ?bytes;
        clearedSpare();
        Q.pushBack(queue, bytes);
        assert Q.popBack(queue) == ?bytes;
        clearedSpare();
        Q.assertValid(queue);
        i += 1;
      };
      Q.clear(queue);
      assert Q.isEmpty(queue);
      switch (queue.front, queue.back, queue.spare) { case (null, null, null) {}; case _ assert false };
      Q.assertValid(queue);
    })
  };

  // Last declared means emitted first. Seed shared helpers with pointer-free
  // values before the pointer-bearing instantiations above.
  public query func test_scalar_specialization_seed() : async Test.Metrics {
    Test.test(func() {
      let queue = Q.empty<Null>();
      var i = 0;
      while (i < 65) { Prim.queue_push_front<Null>(queue, null); i += 1 };
      assert Prim.queue_to_array<Null>(queue).size() == 65;
      assert Prim.queue_to_var_array<Null>(queue).size() == 65;
      while (i > 0) { assert Prim.queue_pop_back<Null>(queue) == ?null; i -= 1 };
      assert Q.isEmpty(queue);
    })
  };
}
