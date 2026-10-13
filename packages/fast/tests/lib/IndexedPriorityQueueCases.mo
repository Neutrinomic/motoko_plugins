import Prim "mo:⛔";
import Q "mo:fast/IndexedPriorityQueue";
import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Nat64 "mo:core/Nat64";
import Text "mo:core/Text";

module {
  func isNull<T>(value : ?T) : Bool {switch value {case null true; case _ false}};
  type ModelEntry = {id : Nat; priority : Nat; value : ?Nat};
  type Saved = {id : Nat; handle : Q.Handle<Nat, ?Nat>};
  func pair(entry : ModelEntry) : (Nat, ?Nat) { (entry.priority, entry.value) };

  /// Array oracle deliberately has no heap, position index, or plugin handles.
  public func model(seed : Nat, steps : Nat) {
    let queue = Q.empty<Nat, ?Nat>();
    var expected : [ModelEntry] = [];
    var handles : [Saved] = [];
    var serial = 0;
    var random = seed;
    func draw(bound : Nat) : Nat {
      random := (random * 48271 + 1) % 2147483647;
      random % bound
    };
    func lookup(id : Nat) : ?ModelEntry {
      for (entry in expected.values()) if (entry.id == id) return ?entry;
      null
    };
    func drop(id : Nat) { expected := Array.filter<ModelEntry>(expected, func(e) {e.id != id}) };
    func minimum() : ?Nat {
      var best : ?Nat = null;
      for (entry in expected.values()) {
        switch best {case null best := ?entry.priority; case (?p) if (entry.priority < p) best := ?entry.priority};
      };
      best
    };
    func check() {
      assert Q.size(queue) == expected.size();
      assert Q.isEmpty(queue) == (expected.size() == 0);
      assert Q.peekPriority(queue) == minimum();
      switch (Q.peek(queue), minimum()) {
        case (null, null) {};
        case (?(p, value), ?best) {
          assert p == best;
          var found = false;
          for (entry in expected.values()) if (pair(entry) == (p, value)) found := true;
          assert found;
        };
        case _ assert false;
      };
      var actual : [(Nat, ?Nat)] = [];
      for (entry in Q.entries(queue)) actual := Array.concat(actual, [entry]);
      assert actual.size() == expected.size();
      for (entry in expected.values()) {
        var matches = 0;
        for (candidate in actual.values()) if (candidate == pair(entry)) matches += 1;
        var expectedMatches = 0;
        for (candidate in expected.values()) if (pair(candidate) == pair(entry)) expectedMatches += 1;
        assert matches == expectedMatches;
      };
      // Handles survive heap movement and cannot start pointing at a reused slot.
      for (saved in handles.values()) {
        let want = switch (lookup(saved.id)) {case null null; case (?entry) ?pair(entry)};
        assert Q.get(saved.handle) == want;
      };
    };
    var step = 0;
    while (step < steps) {
      let operation = draw(100);
      if (operation < 39 or handles.size() == 0) {
        let priority = draw(31);
        let value = if (draw(7) == 0) null else ?serial;
        let handle = Q.push(queue, Nat.compare, priority, value);
        expected := Array.concat(expected, [{id = serial; priority; value}]);
        handles := Array.concat(handles, [{id = serial; handle}]);
        serial += 1;
      } else if (operation < 57) {
        let oldSize = expected.size();
        let best = minimum();
        let result = Q.pop(queue, Nat.compare);
        switch (result, best) {
          case (null, null) {};
          case (?(priority, value), ?p) {
            assert priority == p;
            // Equal priority payloads need not be stable: identify the removed
            // entry by its invalidated handle instead of imposing a tie order.
            var removed : ?Nat = null;
            for (saved in handles.values()) {
              switch (lookup(saved.id), Q.get(saved.handle)) {
                case (?entry, null) { assert removed == null; assert pair(entry) == (priority, value); removed := ?entry.id };
                case _ {};
              };
            };
            switch removed {case (?id) drop(id); case null assert false};
            assert expected.size() + 1 == oldSize;
          };
          case _ assert false;
        }
      } else if (operation < 98) {
        let saved = handles[draw(handles.size())];
        let previous = lookup(saved.id);
        let before = switch previous {case null null; case (?entry) ?pair(entry)};
        if (operation < 71) {
          assert Q.remove(saved.handle, Nat.compare) == before;
          drop(saved.id);
          assert Q.remove(saved.handle, Nat.compare) == null;
        } else if (operation < 85) {
          let priority = draw(37);
          assert Q.reschedule(saved.handle, Nat.compare, priority) == (previous != null);
          expected := Array.map<ModelEntry, ModelEntry>(expected, func(entry) {
            if (entry.id == saved.id) ({id = entry.id; priority; value = entry.value}) else entry
          });
        } else {
          let priority = draw(19);
          let value = if (draw(4) == 0) null else ?(serial + draw(1000));
          assert Q.replace(saved.handle, Nat.compare, priority, value) == before;
          expected := Array.map<ModelEntry, ModelEntry>(expected, func(entry) {
            if (entry.id == saved.id) ({id = entry.id; priority; value}) else entry
          });
        }
      } else {
        Q.clear(queue);
        expected := [];
      };
      check();
      step += 1;
    };
    while (not Q.isEmpty(queue)) {
      let ?best = minimum() else {assert false; return};
      let ?(priority, _) = Q.pop(queue, Nat.compare) else {assert false; return};
      assert priority == best;
      expected := Array.filter<ModelEntry>(expected, func(entry) {
        for (saved in handles.values()) if (saved.id == entry.id) return Q.get(saved.handle) != null;
        assert false;
        false
      });
      check();
    };
    assert expected.size() == 0;
    assert Q.pop(queue, Nat.compare) == null;
  };

  public func boundaries() {
    for (count in [0, 1, 7, 8, 9, 15, 16, 17, 31, 32, 33, 127, 128, 129, 1024].values()) {
      let queue = Q.empty<Nat, Nat>();
      let handles = Array.tabulate<Q.Handle<Nat, Nat>>(count, func(i) {Q.push(queue, Nat.compare, Nat.sub(count, i), i)});
      assert Q.size(queue) == count;
      // Moving the tail both up and down updates every intermediate handle.
      for (i in Nat.range(0, count)) {
        assert Q.get(handles[i]) == ?(Nat.sub(count, i), i);
        assert Q.reschedule(handles[i], Nat.compare, count + i);
      };
      var expected = 0;
      while (expected < count) {
        assert Q.pop(queue, Nat.compare) == ?(count + expected, expected);
        assert Q.get(handles[expected]) == null;
        assert not Q.reschedule(handles[expected], Nat.compare, 0);
        expected += 1;
      };
      assert Q.peek(queue) == null and Q.size(queue) == 0;
      // Repeated shrinking, emptying and growing must not revive old handles.
      let fresh = Q.push(queue, Nat.compare, 0, 42);
      for (handle in handles.values()) assert Q.remove(handle, Nat.compare) == null;
      assert Q.get(fresh) == ?(0, 42);
      Q.clear(queue);
      assert Q.get(fresh) == null and Q.replace(fresh, Nat.compare, 9, 9) == null;
    }
  };

  public func handleOwners() {
    let first = Q.empty<Nat, Nat>();
    let second = Q.empty<Nat, Nat>();
    let firstHandle = Q.push(first, Nat.compare, 7, 70);
    let secondHandle = Q.push(second, Nat.compare, 7, 71);
    Q.clear(first);
    assert Q.get(firstHandle) == null;
    assert Q.get(secondHandle) == ?(7, 71);
    assert not Q.reschedule(firstHandle, Nat.compare, 0);
    assert Q.replace(firstHandle, Nat.compare, 0, 0) == null;
    assert Q.reschedule(secondHandle, Nat.compare, 1);
    assert Q.peek(second) == ?(1, 71) and Q.isEmpty(first);
    let replacement = Q.push(first, Nat.compare, 2, 22);
    assert Q.remove(firstHandle, Nat.compare) == null;
    assert Q.get(replacement) == ?(2, 22);
    assert Q.remove(secondHandle, Nat.compare) == ?(1, 71);
    assert Q.isEmpty(second) and Q.size(first) == 1;
  };

  public func peekPriorityContracts() {
    func generic<K, V>(queue : Q.Queue<K, V>) : ?K {Q.peekPriority(queue)};
    let scalar = Q.empty<Nat, Nat>();
    assert Q.peekPriority(scalar) == null;
    ignore Q.push(scalar, Nat.compare, 9, 90);
    let earlier = Q.push(scalar, Nat.compare, 2, 20);
    assert Q.peekPriority(scalar) == ?2 and generic(scalar) == ?2;
    assert Q.reschedule(earlier, Nat.compare, 12);
    assert Q.peekPriority(scalar) == ?9;
    Q.clear(scalar);
    assert Q.peekPriority(scalar) == null;
    let optional = Q.empty<?Nat, Nat>();
    func order(a : ?Nat, b : ?Nat) : Q.Order {
      switch (a, b) {case (null, null) #equal; case (null, _) #less; case (_, null) #greater; case (?a, ?b) Nat.compare(a, b)}
    };
    ignore Q.push(optional, order, ?0, 0);
    assert Q.peekPriority(optional) == ??0;
    let absent = Q.push(optional, order, null, 1);
    assert Q.peekPriority(optional) == ?null and generic(optional) == ?null;
    ignore Q.remove(absent, order);
    assert Q.peekPriority(optional) == ??0;
    let nulls = Q.empty<Null, Null>();
    func equal(_ : Null, _ : Null) : Q.Order {#equal};
    ignore Q.push(nulls, equal, null, null);
    assert Q.peekPriority(nulls) == ?null and generic(nulls) == ?null;
    type Priority = {n : Nat; cell : {var value : Nat}};
    let cell = {var value = 7};
    let key : Priority = {n = 5; cell};
    let records = Q.empty<Priority, Null>();
    func byNumber(a : Priority, b : Priority) : Q.Order {Nat.compare(a.n, b.n)};
    ignore Q.push(records, byNumber, key, null);
    switch (Q.peekPriority(records)) {
      case (?priority) {assert priority.n == 5; priority.cell.value := 41};
      case null assert false;
    };
    assert key.cell.value == 41;
    switch (generic(records)) {case (?priority) assert priority.cell.value == 41; case null assert false};
  };

  public func scalarOrders() {
    let naturals : [Nat] = [0, 1, 4611686018427387903, 4611686018427387904, 18446744073709551615, 18446744073709551616, 340282366920938463463374607431768211457, 2 ** 2048];
    let nq = Q.empty<Nat, Nat>();
    for (p in naturals.values()) ignore Q.push(nq, Nat.compare, p, p);
    for (p in naturals.values()) assert Q.pop(nq, Nat.compare) == ?(p, p);
    let integers : [Int] = [-(2 ** 2048), -340282366920938463463374607431768211457, -4611686018427387904, -1, 0, 1, 4611686018427387904, 2 ** 2048];
    let iq = Q.empty<Int, Int>();
    for (p in integers.values()) ignore Q.push(iq, Int.compare, p, p);
    for (p in integers.values()) assert Q.pop(iq, Int.compare) == ?(p, p);
    let words : [Nat64] = [0, 1, 9223372036854775807, 9223372036854775808, 18446744073709551615];
    let wq = Q.empty<Nat64, Nat64>();
    for (p in words.values()) ignore Q.push(wq, Nat64.compare, p, p);
    for (p in words.values()) assert Q.pop(wq, Nat64.compare) == ?(p, p);
    let texts = ["", "a", "aa", "ab", "b", "z", "é", "🌍"];
    let tq = Q.empty<Text, Text>();
    for (p in texts.values()) ignore Q.push(tq, Text.compare, p, p);
    for (p in texts.values()) assert Q.pop(tq, Text.compare) == ?(p, p);
    // A lawful reverse comparator must not be mistaken for the built-in order.
    let reversed = Q.empty<Nat, Nat>();
    var calls = 0;
    func descending(a : Nat, b : Nat) : Q.Order {calls += 1; Nat.compare(b, a)};
    for (p in naturals.values()) ignore Q.push(reversed, descending, p, p);
    var i = naturals.size();
    while (i > 0) {i -= 1; assert Q.pop(reversed, descending) == ?(naturals[i], naturals[i])};
    assert calls > 0;
  };

  public func genericReferences() {
    type Cell = {var value : Nat};
    type Payload = {cell : Cell; call : () -> Nat; bytes : Blob};
    let cell = {var value = 0};
    let payload : Payload = {cell; call = func() : Nat {cell.value += 1; cell.value}; bytes = "\00\7f\ff"};
    let queue = Q.empty<Nat, ??Payload>();
    let absent = Q.push(queue, Nat.compare, 0, null);
    let innerAbsent = Q.push(queue, Nat.compare, 1, ?null);
    let present = Q.push(queue, Nat.compare, 2, ??payload);
    switch (Q.get(absent)) {case (?(0, null)) {}; case _ assert false};
    switch (Q.get(innerAbsent)) {case (?(1, ?null)) {}; case _ assert false};
    switch (Q.get(present)) {case (?(2, ??value)) {assert value.call() == 1; value.cell.value := 8}; case _ assert false};
    assert payload.call() == 9 and cell.value == 9;
    assert Q.reschedule(present, Nat.compare, 0);
    let replacement : Payload = {cell; call = payload.call; bytes = "new"};
    switch (Q.replace(present, Nat.compare, 3, ??replacement)) {case (?(0, ??value)) assert value.bytes == "\00\7f\ff"; case _ assert false};
    switch (Q.remove(present, Nat.compare)) {case (?(3, ??value)) {assert value.bytes == "new"; assert value.call() == 10}; case _ assert false};
    assert isNull(Q.get(present));
    // Explicit composite priorities retain caller-selected tie ordering.
    type Priority = {at : Int; ticket : Nat};
    func compare(a : Priority, b : Priority) : Q.Order {
      switch (Int.compare(a.at, b.at)) {case (#equal) Nat.compare(a.ticket, b.ticket); case order order}
    };
    let compositeQueue = Q.empty<Priority, Nat>();
    for (ticket in [7, 2, 9, 0, 4].values()) ignore Q.push(compositeQueue, compare, {at = -100; ticket}, ticket);
    for (ticket in [0, 2, 4, 7, 9].values()) assert Q.pop(compositeQueue, compare) == ?({at = -100; ticket}, ticket);
    // Null itself as a stored priority/value must remain distinguishable from
    // an absent entry after plugin specialization and heap movement.
    let nulls = Q.empty<Null, Null>();
    func equal(_ : Null, _ : Null) : Q.Order {#equal};
    let nh = Q.push(nulls, equal, null, null);
    assert Q.get(nh) == ?(null, null);
    assert Q.pop(nulls, equal) == ?(null, null);
    assert Q.get(nh) == null;
  };

  /// Comparator effects are observable: reference and native heap repair must
  /// call in the same order, once per compared parent rather than repeating the
  /// first upward comparison after deciding the repair direction.
  public func comparatorRepairTrace() {
    var trace : [(Nat, Nat)] = [];
    func compare(a : Nat, b : Nat) : Q.Order {
      trace := Array.concat(trace, [(a, b)]);
      Nat.compare(a, b)
    };
    let small = Q.empty<Nat, Nat>();
    ignore Q.push(small, compare, 1, 1);
    let moving = Q.push(small, compare, 2, 2);
    trace := [];
    assert Q.reschedule(moving, compare, 0);
    assert trace == [(0, 1)];
    assert Q.peek(small) == ?(0, 2);
    assert Q.reschedule(moving, compare, 2);
    trace := [];
    assert Q.replace(moving, compare, 0, 20) == ?(2, 2);
    assert trace == [(0, 1)];
    assert Q.peek(small) == ?(0, 20);

    // The last entry fills an interior hole and repairs toward a nonroot
    // parent, then stops against the root. The argument order matters too.
    let deeper = Q.empty<Nat, Nat>();
    let handles = Array.map<Nat, Q.Handle<Nat, Nat>>([0, 10, 1, 11, 12, 2, 3], func(p) {
      Q.push(deeper, compare, p, p)
    });
    trace := [];
    assert Q.remove(handles[3], compare) == ?(11, 11);
    assert trace == [(3, 10), (3, 0)];
    trace := [];
    assert Q.reschedule(handles[4], compare, 2);
    assert trace == [(2, 3), (2, 0)];
    assert Q.reschedule(handles[4], compare, 12);
    trace := [];
    assert Q.replace(handles[4], compare, 2, 120) == ?(12, 12);
    assert trace == [(2, 3), (2, 0)];

    // Detached and empty operations do not invoke the comparator at all.
    Q.clear(deeper);
    trace := [];
    assert Q.remove(handles[4], compare) == null;
    assert Q.replace(handles[4], compare, 0, 0) == null;
    assert not Q.reschedule(handles[4], compare, 0);
    assert Q.pop(deeper, compare) == null;
    assert trace == [];
    let exhausted = Q.entries(deeper);
    assert exhausted.next() == null and exhausted.next() == null;
  };

  public func comparatorReadConsistency() {
    let queue = Q.empty<Nat, Nat>();
    let side = Q.empty<Nat, Nat>();
    let handles = Prim.Array_init<?Q.Handle<Nat, Nat>>(32, null);
    let expected = Prim.Array_init<?(Nat, Nat)>(32, null);
    var calls = 0;
    func check() {
      var i = 0;
      while (i < handles.size()) {
        switch (handles[i]) {case (?handle) assert Q.get(handle) == expected[i]; case null {}};
        i += 1;
      }
    };
    func compare(a : Nat, b : Nat) : Q.Order {
      calls += 1;
      // Previously returned handles must still identify their own entries
      // during native repair, including handles whose priority just changed.
      check();
      ignore Q.push(side, Nat.compare, calls, calls);
      Nat.compare(a, b)
    };
    var i = 0;
    while (i < 32) {
      let p = Nat.sub(1000, i);
      expected[i] := ?(p, i);
      handles[i] := ?Q.push(queue, compare, p, i);
      check();
      i += 1;
    };
    func handle(i : Nat) : Q.Handle<Nat, Nat> {
      switch (handles[i]) {case (?handle) handle; case null Prim.trap("missing callback test handle")}
    };
    i := 0;
    while (i < 16) {
      expected[i] := ?(i, i);
      assert Q.reschedule(handle(i), compare, i);
      check();
      i += 1;
    };
    i := 0;
    while (i < 8) {
      let old = expected[i];
      expected[i] := null;
      assert Q.remove(handle(i), compare) == old;
      check();
      i += 1;
    };
    while (i < 24) {
      let old = expected[i];
      let p = Nat.sub(100, i);
      expected[i] := ?(p, i + 10000);
      assert Q.replace(handle(i), compare, p, i + 10000) == old;
      check();
      i += 1;
    };
    while (not Q.isEmpty(queue)) {
      let entry = Q.peek(queue);
      var found = false;
      i := 0;
      while (i < 32) {
        if (expected[i] == entry) {assert not found; found := true; expected[i] := null};
        i += 1;
      };
      assert found;
      assert Q.pop(queue, compare) == entry;
      check();
    };
    assert calls > 0 and Q.size(side) == calls;
  };

  /// Compare the observable behavior of mixed scalar/callback dispatch with
  /// the ordinary callback path. This is not a FIFO promise for equal keys:
  /// equivalent lawful comparators must not change entry identity or heap
  /// traversal merely because one is recognized as a built-in comparator.
  public func mixedDispatchDuplicates() {
    for ((count, pattern) in [
      (0, 0), (1, 0), (2, 0), (3, 0), (7, 0), (8, 0), (9, 0),
      (15, 1), (16, 1), (17, 1), (31, 2), (32, 2), (33, 2),
      (127, 0), (128, 1), (129, 2),
    ].values()) {
      let mixed = Q.empty<Nat64, Nat>();
      let ordinary = Q.empty<Nat64, Nat>();
      let mixedHandles = Prim.Array_init<?Q.Handle<Nat64, Nat>>(count, null);
      let ordinaryHandles = Prim.Array_init<?Q.Handle<Nat64, Nat>>(count, null);
      let mixedExpected = Prim.Array_init<?(Nat64, Nat)>(count, null);
      let ordinaryExpected = Prim.Array_init<?(Nat64, Nat)>(count, null);
      var mixedTrace : [(Nat64, Nat64)] = [];
      var ordinaryTrace : [(Nat64, Nat64)] = [];
      func priority(id : Nat) : Nat64 {
        if (pattern == 0) 18_446_744_073_709_551_615
        else if (pattern == 1) {
          if (id % 3 == 0) 0 else 9_223_372_036_854_775_808 + Nat.toNat64(id % 3)
        } else Nat.toNat64((id * 73 + 19) % 17)
      };
      func observe(queue : Q.Queue<Nat64, Nat>, handles : [var ?Q.Handle<Nat64, Nat>], expected : [var ?(Nat64, Nat)]) {
        var live = 0;
        var id = 0;
        while (id < count) {
          if (expected[id] != null) live += 1;
          switch (handles[id]) {case (?handle) assert Q.get(handle) == expected[id]; case null {}};
          id += 1;
        };
        assert Q.size(queue) == live;
        switch (Q.peek(queue), Q.peekPriority(queue)) {
          case (null, null) {};
          case (?(key, _), ?p) assert key == p;
          case _ assert false;
        }
      };
      // Observable effects force these equivalent comparators down the
      // callback path; reading handles catches partially committed swaps.
      func mixedCompare(a : Nat64, b : Nat64) : Q.Order {
        mixedTrace := Array.concat(mixedTrace, [(a, b)]);
        // Check the boundary after a scalar operation hands state back to
        // callbacks. comparatorReadConsistency checks every callback step.
        if (mixedTrace.size() == 1) observe(mixed, mixedHandles, mixedExpected);
        Nat64.compare(a, b)
      };
      func ordinaryCompare(a : Nat64, b : Nat64) : Q.Order {
        ordinaryTrace := Array.concat(ordinaryTrace, [(a, b)]);
        Nat64.compare(a, b)
      };
      func snapshot(queue : Q.Queue<Nat64, Nat>) : [(Nat64, Nat)] {
        let iterator = Q.entries(queue);
        let entries = Array.tabulate<(Nat64, Nat)>(Q.size(queue), func(_) {
          switch (iterator.next()) {case (?entry) entry; case null Prim.trap("short heap iterator")}
        });
        assert iterator.next() == null and iterator.next() == null;
        entries
      };
      func check(callback : Bool) {
        observe(mixed, mixedHandles, mixedExpected);
        observe(ordinary, ordinaryHandles, ordinaryExpected);
        assert snapshot(mixed) == snapshot(ordinary);
        assert Q.peek(mixed) == Q.peek(ordinary);
        if (callback) assert mixedTrace == ordinaryTrace;
        mixedTrace := [];
        ordinaryTrace := [];
      };
      func handle(handles : [var ?Q.Handle<Nat64, Nat>], id : Nat) : Q.Handle<Nat64, Nat> {
        switch (handles[id]) {case (?handle) handle; case null Prim.trap("missing mixed-dispatch handle")}
      };
      var id = 0;
      while (id < count) {
        let p = priority(id);
        let callback = id % 2 == 1;
        mixedExpected[id] := ?(p, id);
        mixedHandles[id] := ?(if (callback) Q.push(mixed, mixedCompare, p, id) else Q.push(mixed, Nat64.compare, p, id));
        ordinaryExpected[id] := ?(p, id);
        ordinaryHandles[id] := ?Q.push(ordinary, ordinaryCompare, p, id);
        check(callback);
        id += 1;
      };
      id := 0;
      while (id < count) {
        let p = priority(count + id + 5);
        let callback = id % 3 == 0;
        if (id % 4 == 0) {
          mixedExpected[id] := ?(p, id);
          assert (if (callback) Q.reschedule(handle(mixedHandles, id), mixedCompare, p) else Q.reschedule(handle(mixedHandles, id), Nat64.compare, p));
          ordinaryExpected[id] := ?(p, id);
          assert Q.reschedule(handle(ordinaryHandles, id), ordinaryCompare, p);
        } else if (id % 4 == 1) {
          let previous = mixedExpected[id];
          mixedExpected[id] := ?(p, id + count);
          assert (if (callback) Q.replace(handle(mixedHandles, id), mixedCompare, p, id + count) else Q.replace(handle(mixedHandles, id), Nat64.compare, p, id + count)) == previous;
          ordinaryExpected[id] := ?(p, id + count);
          assert Q.replace(handle(ordinaryHandles, id), ordinaryCompare, p, id + count) == previous;
        };
        check(callback);
        id += 1;
      };
      var removed = 0;
      while (not Q.isEmpty(mixed)) {
        let ?entry = Q.peek(mixed) else {assert false; return};
        let id = entry.1 % count;
        let callback = removed % 3 == 1;
        let useHandle = removed % 5 == 2;
        mixedExpected[id] := null;
        let actual = if (useHandle) {
          if (callback) Q.remove(handle(mixedHandles, id), mixedCompare) else Q.remove(handle(mixedHandles, id), Nat64.compare)
        } else if (callback) Q.pop(mixed, mixedCompare) else Q.pop(mixed, Nat64.compare);
        assert actual == ?entry;
        ordinaryExpected[id] := null;
        let reference = if (useHandle) Q.remove(handle(ordinaryHandles, id), ordinaryCompare) else Q.pop(ordinary, ordinaryCompare);
        assert actual == reference;
        check(callback);
        // Stale handles must remain detached when later removals move entries
        // through their former positions, including shrink boundaries.
        assert Q.get(handle(mixedHandles, id)) == null;
        assert Q.remove(handle(mixedHandles, id), mixedCompare) == null;
        assert not Q.reschedule(handle(mixedHandles, id), mixedCompare, priority(id));
        assert mixedTrace == [];
        removed += 1;
      };
      assert removed == count;
      assert Q.pop(mixed, Nat64.compare) == null and Q.pop(ordinary, ordinaryCompare) == null;
      check(true);
    }
  };

  public func comparatorCallbacks() {
    type Priority = {n : Nat; bytes : Text};
    let queue = Q.empty<Priority, Nat>();
    let side = Q.empty<Nat, Nat>();
    var calls = 0;
    func compare(a : Priority, b : Priority) : Q.Order {
      calls += 1;
      ignore Q.peek(queue);
      ignore Q.size(queue);
      ignore Q.push(side, Nat.compare, calls, calls);
      let bytes = Array.tabulate<Nat>(64, func(i) {i + calls});
      assert bytes[63] == 63 + calls;
      Nat.compare(a.n, b.n)
    };
    let handles = Array.tabulate<Q.Handle<Priority, Nat>>(80, func(i) {
      Q.push(queue, compare, {n = Nat.sub(80, i); bytes = Nat.toText(i)}, i)
    });
    for (i in Nat.range(0, 80)) assert Q.reschedule(handles[i], compare, {n = 100 + i; bytes = "changed"});
    for (i in Nat.range(0, 80)) {
      switch (Q.pop(queue, compare)) {case (?({n; bytes}, value)) assert n == 100 + i and bytes == "changed" and value == i; case null assert false};
    };
    assert calls > 0 and Q.size(side) == calls;
  };
}
