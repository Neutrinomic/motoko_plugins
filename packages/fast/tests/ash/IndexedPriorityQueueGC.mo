import Test "mo:test";
import Q "mo:fast/IndexedPriorityQueue";
import Nat "mo:core/Nat";
import Nat64 "mo:core/Nat64";
import Prim "mo:⛔";

persistent actor {
  func isNull<T>(value : ?T) : Bool {switch value {case null true; case _ false}};
  type Priority = {n : Nat; generation : Nat; bytes : Blob};
  type Cell = {var generation : Nat};
  type Payload = {id : Nat; generation : Nat; bytes : Blob; cell : Cell; read : () -> Nat};

  public func test_references_and_handles_during_incremental_gc() : async Test.Metrics {
    let queue = Q.empty<Priority, ?Payload>();
    let side = Q.empty<Nat, Nat>();
    let scalarQueue = Q.empty<Nat64, ?Payload>();
    let cell = {var generation = 0};
    let bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) {73}));
    var generation = 0;
    func priority(n : Nat) : Priority {{n; generation; bytes}};
    func byNumber(a : Priority, b : Priority) : Q.Order {Nat.compare(a.n, b.n)};
    func payload(id : Nat) : ?Payload {
      ?{id; generation; bytes; cell; read = func() : Nat {cell.generation}}
    };
    let handles = Prim.Array_tabulateVar<Q.Handle<Priority, ?Payload>>(1024, func(id) {
      Q.push(queue, byNumber, priority(id), payload(id))
    });
    let nullHandle = Q.push(queue, byNumber, priority(1024), null);
    let scalarHandles = Prim.Array_tabulateVar<Q.Handle<Nat64, ?Payload>>(1024, func(id) {
      Q.push(scalarQueue, Nat64.compare, Nat.toNat64(id), payload(id))
    });
    let scalarNull = Q.push(scalarQueue, Nat64.compare, (1024 : Nat64), null);
    var comparisons = 0;
    func compare(a : Priority, b : Priority) : Q.Order {
      comparisons += 1;
      ignore Q.peek(queue);
      ignore Q.push(side, Nat.compare, comparisons, comparisons);
      ignore Prim.Array_init<Nat>(32, comparisons);
      byNumber(a, b)
    };
    func verifyScalarHandle(id : Nat) {
      switch (Q.get(scalarHandles[id])) {
        case (?(key, ?value)) {
          assert key == Nat.toNat64(id) and value.id == id;
          assert value.generation == (if (id < 128) generation else 0);
          assert value.cell.generation == generation and value.read() == generation;
          assert value.bytes.size() == 1024 * 1024 and value.bytes[0] == 73 and value.bytes[1024 * 1024 - 1] == 73;
        };
        case _ assert false;
      }
    };
    func verify() {
      assert Q.size(queue) == 1025 and Q.size(scalarQueue) == 1025;
      switch (Q.peekPriority(queue)) {
        case (?key) assert key.n == 0 and key.generation == generation and key.bytes[0] == 73;
        case null assert false;
      };
      for (id in [0, 1, 31, 32, 127, 128, 511, 1023].values()) {
        switch (Q.get(handles[id])) {
          case (?(priority, ?value)) {
            assert priority.n == id and priority.generation == (if (id < 128) generation else 0);
            assert priority.bytes.size() == 1024 * 1024 and priority.bytes[0] == 73;
            assert value.id == id and value.generation == (if (id < 128) generation else 0);
            assert value.cell.generation == generation and value.read() == generation;
            assert value.bytes.size() == 1024 * 1024 and value.bytes[0] == 73 and value.bytes[1024 * 1024 - 1] == 73;
          };
          case _ assert false;
        };
        verifyScalarHandle(id)
      };
      switch (Q.get(scalarNull)) {case (?(1024, null)) {}; case _ assert false};
      switch (Q.get(nullHandle)) {case (?(key, null)) assert key.n == 1024 and key.generation == 0; case _ assert false}
    };
    verify();
    // Enough live data to leave an incremental cycle pending while native
    // heap moves update handle owners, indices, and payload references.
    let live = Prim.Array_tabulateVar<[var Nat]>(192, func(n) {
      ignore Prim.Array_init<Nat>(64 * 1024, 0);
      Prim.Array_init<Nat>(64 * 1024, n)
    });
    assert Prim.rts_heap_size() > 192 * 1024 * 1024;
    let reclaimed = Prim.rts_reclaimed();
    var pending = false;
    var completed = false;
    await async {};
    while (generation < 8) {
      pending := pending or (Prim.rts_heap_size() > 96 * 1024 * 1024 and Prim.rts_max_live_size() < 96 * 1024 * 1024);
      completed := completed or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
      generation += 1;
      cell.generation := generation;
      var id = 0;
      while (id < 128) {
        ignore Q.replace(handles[id], compare, priority(2048 + id), payload(id));
        assert Q.reschedule(handles[id], compare, priority(id));
        id += 1;
      };
      id := 0;
      while (id < 64) {
        let stale = handles[id];
        ignore Q.remove(stale, compare);
        assert isNull(Q.get(stale)) and not Q.reschedule(stale, compare, priority(id));
        handles[id] := Q.push(queue, compare, priority(id), payload(id));
        id += 1;
      };
      // The scalar path may temporarily use holes because its comparator
      // cannot call Motoko. Managed entries and handles must nevertheless be
      // fully restored, with write barriers, before collection resumes.
      id := 0;
      while (id < 128) {
        ignore Q.replace(scalarHandles[id], Nat64.compare, Nat.toNat64(id), payload(id));
        id += 1;
      };
      id := 0;
      while (id < 64) {
        switch (Q.pop(scalarQueue, Nat64.compare)) {
          case (?(key, ?value)) assert key == Nat.toNat64(id) and value.id == id;
          case _ assert false;
        };
        assert isNull(Q.get(scalarHandles[id]));
        assert Q.peekPriority(scalarQueue) == ?Nat.toNat64(id + 1);
        for (probe in [id + 1, 127, 128, 511, 1023].values()) verifyScalarHandle(probe);
        id += 1;
      };
      id := 0;
      while (id < 64) {
        scalarHandles[id] := Q.push(scalarQueue, Nat64.compare, Nat.toNat64(id), payload(id));
        verifyScalarHandle(id);
        assert Q.peekPriority(scalarQueue) == ?(0 : Nat64);
        id += 1;
      };
      assert live[0][65535] == 0 and live[191][65535] == 191;
      verify();
      await async {};
    };
    var round = 0;
    while (round < 12) {
      ignore Prim.Array_init<Nat>(131072, round);
      await async {};
      assert live[0][65535] == 0 and live[191][65535] == 191;
      verify();
      round += 1;
    };
    assert pending;
    assert completed or Prim.rts_max_live_size() >= 96 * 1024 * 1024;
    assert Prim.rts_reclaimed() > reclaimed + 32 * 1024 * 1024;
    assert comparisons > 0 and Q.size(side) == comparisons;
    Test.test(verify)
  };

  public func test_detached_handles_release_owners_and_payloads() : async Test.Metrics {
    // Reuse one retained conversion array, so discarded conversion arrays
    // cannot be mistaken for reclaimed payloads. All 24 blobs are distinct.
    let template = Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) {29});
    var detached : [Q.Handle<Nat, Blob>] = [];
    var reclaimed = 0;
    var allocated = 0;
    func prepareDetached() : async () {
      func fill(queue : Q.Queue<Nat, Blob>) : Q.Handle<Nat, Blob> {
        var first : ?Q.Handle<Nat, Blob> = null;
        var i = 0;
        while (i < 8) {
          let bytes = Prim.arrayToBlob(template);
          let handle = Q.push(queue, Nat.compare, i, bytes);
          if (i == 0) first := ?handle;
          i += 1;
        };
        switch first {case (?handle) handle; case null Prim.trap("missing retention handle")}
      };
      let poppedQueue = Q.empty<Nat, Blob>();
      let removedQueue = Q.empty<Nat, Blob>();
      let clearedQueue = Q.empty<Nat, Blob>();
      let handles = [fill(poppedQueue), fill(removedQueue), fill(clearedQueue)];
      var round = 0;
      while (round < 12) {await async {}; round += 1};
      assert Q.size(poppedQueue) == 8 and Q.size(removedQueue) == 8 and Q.size(clearedQueue) == 8;
      let before = Prim.rts_reclaimed();
      allocated := Prim.rts_total_allocation();
      // Popped/removed queues deliberately retain seven other large payloads.
      // A stale handle that incorrectly retains its owner keeps those alive.
      ignore Q.pop(poppedQueue, Nat.compare);
      ignore Q.remove(handles[1], Nat.compare);
      Q.clear(clearedQueue);
      detached := handles;
      reclaimed := before;
    };
    await prepareDetached();
    // Idle continuations do not necessarily start a new collection. Create
    // enough dead blobs to force one, and subtract ALL subsequent allocation
    // from reclaimed bytes so this pressure cannot satisfy the payload check.
    var batches = 0;
    var released = false;
    while (batches < 8 and not released) {
      var pressure = 0;
      while (pressure < 128) {ignore Prim.arrayToBlob(template); pressure += 1};
      var round = 0;
      while (round < 16) {await async {}; round += 1};
      let reclaimedBytes = Prim.rts_reclaimed() - reclaimed;
      let allocatedBytes = Prim.rts_total_allocation() - allocated;
      released := reclaimedBytes > allocatedBytes + 20 * 1024 * 1024;
      batches += 1;
    };
    if (not released) {Prim.trap("payload accounting " # debug_show (Prim.rts_reclaimed() - reclaimed, Prim.rts_total_allocation() - allocated, Prim.rts_heap_size(), Prim.rts_max_live_size()))};
    assert template[0] == 29 and template[1024 * 1024 - 1] == 29;
    Test.test(func() {
      for (handle in detached.values()) {
        assert Q.get(handle) == null;
        assert Q.remove(handle, Nat.compare) == null;
        assert not Q.reschedule(handle, Nat.compare, 0);
        assert Q.replace(handle, Nat.compare, 0, ("new" : Blob)) == null;
      }
    })
  };

  // Actor methods are emitted in reverse declaration order: instantiate shared
  // helpers with immediate types before the heap-reference stress method.
  public query func test_scalar_specialization_seed() : async Test.Metrics {
    Test.test(func() {
      let queue = Q.empty<Bool, Null>();
      func compare(a : Bool, b : Bool) : Q.Order {if (a == b) #equal else if (a) #greater else #less};
      let first = Prim.ipq_push<Bool, Null>(queue, compare, true, null);
      ignore Prim.ipq_push<Bool, Null>(queue, compare, false, null);
      assert Prim.ipq_reschedule<Bool, Null>(first, compare, false);
      assert Prim.ipq_remove<Bool, Null>(first, compare) == ?(false, null);
      assert Prim.ipq_pop<Bool, Null>(queue, compare) == ?(false, null);
      Prim.ipq_clear<Bool, Null>(queue);
    })
  };
}
