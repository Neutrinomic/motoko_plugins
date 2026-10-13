import Q "mo:fast/Queue";
import Core "mo:core/Queue";
import Array "mo:core/Array";
import Iter "mo:core/Iter";
import VarArray "mo:core/VarArray";
import Nat "mo:core/Nat";

// Shared independent tests: the run suite covers the interpreter and Wasm;
// QueueCollection runs these same assertions as PocketIC canister calls.
module {
  func check(q : Q.Queue<Nat>, expected : Core.Queue<Nat>) {
    assert Q.size(q) == Core.size(expected);
    assert Q.isEmpty(q) == Core.isEmpty(expected);
    assert Q.peekFront(q) == Core.peekFront(expected);
    assert Q.peekBack(q) == Core.peekBack(expected);
    assert Q.toArray(q) == Core.toArray(expected);
    assert Iter.toArray(Q.reverseValues(q)) == Iter.toArray(Core.reverseValues(expected));
    Q.assertValid(q);
  };

  public func boundaries() {
    for (n in [0, 1, 2, 30, 31, 32, 33, 34, 63, 64, 65, 95, 96, 97, 127, 128, 129, 1024].values()) {
      let q = Q.empty<Nat>();
      let expected = Core.empty<Nat>();
      for (cycle in Nat.range(0, 3)) {
        var i = 0;
        while (i < n) {
          let value = i + cycle * 10_000;
          if (i % 2 == 0) { Q.pushBack(q, value); Core.pushBack(expected, value) }
          else { Q.pushFront(q, value); Core.pushFront(expected, value) };
          i += 1;
        };
        check(q, expected);
        // A partial drain followed by refill makes both chunk ends wrap.
        i := 0;
        while (i < n / 2) {
          assert Q.popFront(q) == Core.popFront(expected);
          Q.pushBack(q, 50_000 + i);
          Core.pushBack(expected, 50_000 + i);
          i += 1;
        };
        check(q, expected);
        i := 0;
        while (i < n) {
          if ((i + cycle) % 2 == 0) { assert Q.popFront(q) == Core.popFront(expected) }
          else { assert Q.popBack(q) == Core.popBack(expected) };
          i += 1;
        };
        check(q, expected);
        assert Q.popFront(q) == null and Q.popBack(q) == null;
      };
      Q.clear(q);
      Q.clear(q);
      Q.pushFront(q, 7);
      assert Q.popBack(q) == ?7;
      Q.assertValid(q);
    };

    // Packing start/count must preserve all start offsets at the full-chunk
    // boundary. Check both peeks after every removal, including the retained
    // empty endpoint where computing back's index before checking count fails.
    for (n in [31, 32, 33].values()) {
      for (forward in [true, false].values()) {
        for (offset in Nat.range(0, 32)) {
          let q = Q.empty<Nat>();
          let expected = Core.empty<Nat>();
          for (i in Nat.range(0, n)) { Q.pushBack(q, i); Core.pushBack(expected, i) };
          for (i in Nat.range(0, offset)) {
            if (forward) {
              assert Q.popFront(q) == Core.popFront(expected);
              Q.pushBack(q, 1000 + i); Core.pushBack(expected, 1000 + i);
            } else {
              assert Q.popBack(q) == Core.popBack(expected);
              Q.pushFront(q, 1000 + i); Core.pushFront(expected, 1000 + i);
            };
          };
          check(q, expected);
          while (not Core.isEmpty(expected)) {
            if (forward) { assert Q.popFront(q) == Core.popFront(expected) }
            else { assert Q.popBack(q) == Core.popBack(expected) };
            assert Q.peekFront(q) == Core.peekFront(expected);
            assert Q.peekBack(q) == Core.peekBack(expected);
          };
          check(q, expected);
          assert Q.peekFront(q) == null and Q.peekBack(q) == null;
          assert Q.popFront(q) == null and Q.popBack(q) == null;
          assert Q.reverseValues(q).next() == null;
          Q.pushFront(q, 7);
          assert Q.peekBack(q) == ?7 and Q.popBack(q) == ?7;
          assert Q.peekBack(q) == null;
          Q.pushBack(q, 8);
          assert Q.peekFront(q) == ?8 and Q.popFront(q) == ?8;
          assert Q.peekFront(q) == null and Q.peekBack(q) == null;
          Q.assertValid(q);
        };
      };
    };
  };

  public func model() {
    for (initialSeed in [1, 17, 42, 982_451_653].values()) {
      let q = Q.empty<Nat>();
      let expected = Core.empty<Nat>();
      var seed = initialSeed;
      var step = 0;
      while (step < 2000) {
        seed := (seed * 1_664_525 + 1_013_904_223) % 4_294_967_296;
        let op = (seed / 256) % 16;
        let value = seed % 100_003;
        switch op {
          case (0 or 1 or 2 or 3) { Q.pushFront(q, value); Core.pushFront(expected, value) };
          case (4 or 5 or 6 or 7) { Q.pushBack(q, value); Core.pushBack(expected, value) };
          case (8 or 9) { assert Q.popFront(q) == Core.popFront(expected) };
          case (10 or 11) { assert Q.popBack(q) == Core.popBack(expected) };
          case (12) {
            let copy = Q.clone(q);
            let before = Q.toArray(q);
            Q.pushFront(copy, 999_999);
            Q.pushBack(copy, 999_998);
            assert Q.popFront(copy) == ?999_999;
            assert Q.popBack(copy) == ?999_998;
            assert Q.toArray(copy) == before;
            Q.clear(copy);
            assert Q.toArray(q) == before;
          };
          case (13) { Q.clear(q); Core.clear(expected) };
          case (14) { assert Q.peekFront(q) == Core.peekFront(expected) };
          case _ { assert Q.peekBack(q) == Core.peekBack(expected) };
        };
        check(q, expected);
        step += 1;
      };
    };
  };

  public func publicSurface() {
    let empty = Q.empty<Nat>();
    let coreEmpty = Core.empty<Nat>();
    assert Q.toText(empty, Nat.toText) == Core.toText(coreEmpty, Nat.toText);
    assert Q.equal(empty, Q.clone(empty), Nat.equal);
    assert Q.compare(empty, empty, Nat.compare) == #equal;
    var calls = 0;
    func predicate(_ : Nat) : Bool { calls += 1; true };
    assert Q.all(empty, predicate);
    assert not Q.any(empty, predicate);
    assert not Q.contains(empty, Nat.equal, 0);
    Q.forEach(empty, func(_) { calls += 1 });
    assert Q.isEmpty(Q.map<Nat, Nat>(empty, func(n) { calls += 1; n }));
    assert Q.isEmpty(Q.filter(empty, predicate));
    assert Q.isEmpty(Q.filterMap<Nat, Nat>(empty, func(n) { calls += 1; ?n }));
    assert calls == 0;
    for (iter in [Q.values(empty), Q.reverseValues(empty)].values()) {
      assert iter.next() == null and iter.next() == null;
    };

    let input = [9, 2, 9, 4, 0, 7];
    let expected = Core.fromArray<Nat>(input);
    let mutable = [var 9, 2, 9, 4, 0, 7];
    let fromMutable = Q.fromVarArray<Nat>(mutable);
    mutable[0] := 999;
    let constructions = [Q.fromArray<Nat>(input), Q.fromIter<Nat>(input.values()), Q.toQueue<Nat>(input.values()), fromMutable,
      Q.fromPure<Nat>(Core.toPure(expected)), Q.fromPure<Nat>(Q.toPure(Q.fromArray<Nat>(input)))];
    for (q in constructions.values()) {
      check(q, expected);
      let array = Q.toVarArray(q);
      assert VarArray.toArray(array) == input;
      array[0] := 123;
      assert Q.toArray(q) == input;
      assert Q.toText(q, Nat.toText) == Core.toText(expected, Nat.toText);
      assert Q.contains(q, Nat.equal, 9) and not Q.contains(q, Nat.equal, 100);
      assert Q.contains(q, func(a : Nat, b : Nat) : Bool { a % 2 == b % 2 }, 100);
      assert Q.all(q, func(n : Nat) : Bool { n < 10 });
      assert not Q.all(q, func(n : Nat) : Bool { n > 0 });
      assert Q.any(q, func(n : Nat) : Bool { n == 0 });
      assert not Q.any(q, func(n : Nat) : Bool { n == 3 });
      assert Q.toArray(Q.map<Nat, Nat>(q, func(n) { n * 10 + 1 })) ==
        Core.toArray(Core.map<Nat, Nat>(expected, func(n) { n * 10 + 1 }));
      assert Q.toArray(Q.filter(q, func(n : Nat) : Bool { n % 2 == 0 })) == [2, 4, 0];
      assert Q.toArray(Q.filterMap<Nat, Text>(q, func(n) {
        if (n % 2 == 0) ?Nat.toText(n) else null
      })) == ["2", "4", "0"];
      var trace : [Nat] = [];
      Q.forEach(q, func(n) { trace := Array.concat(trace, [n]) });
      assert trace == input;
      let forward = Q.values(q);
      for (n in input.values()) { assert forward.next() == ?n };
      assert forward.next() == null and forward.next() == null;
      assert Iter.toArray(Q.reverseValues(q)) == [7, 0, 4, 9, 2, 9];
    };
    let single = Q.singleton<Nat>(5);
    assert Q.toArray(single) == [5];
    assert Q.popFront(single) == ?5 and Q.popFront(single) == null;
    for (xs in [[], [1], [1, 2], [1, 2, 0], [1, 3], [2], [0, 99]].values()) {
      for (ys in [[], [1], [1, 2], [1, 2, 0], [1, 3], [2], [0, 99]].values()) {
        let a = Q.fromArray<Nat>(xs);
        let b = Q.fromArray<Nat>(ys);
        assert Q.equal(a, b, Nat.equal) == Core.equal(Core.fromArray<Nat>(xs), Core.fromArray<Nat>(ys), Nat.equal);
        assert Q.compare(a, b, Nat.compare) == Core.compare(Core.fromArray<Nat>(xs), Core.fromArray<Nat>(ys), Nat.compare);
      };
    };
    let stops = Q.fromArray<Nat>([1, 2, 3, 4]);
    calls := 0;
    assert Q.any(stops, func(n : Nat) : Bool { calls += 1; n == 2 });
    assert calls == 2;
    calls := 0;
    assert not Q.all(stops, func(n : Nat) : Bool { calls += 1; n < 3 });
    assert calls == 3;
  };

  public func genericValues() {
    // Each level of optionality is a value, including ?null. The slot's own
    // occupancy option must never conflate one of these with an empty slot.
    let nulls = Q.empty<Null>();
    let options = Q.empty<?Null>();
    let nested = Q.empty<??Nat>();
    var i = 0;
    while (i < 130) {
      Q.pushBack(nulls, null);
      Q.pushFront(options, if (i % 2 == 0) null else ?null);
      Q.pushBack(nested, switch (i % 3) { case 0 null; case 1 ?null; case _ ??i });
      i += 1;
    };
    i := 0;
    while (i < 130) {
      assert Q.popFront(nulls) == ?null;
      assert Q.popBack(options) == (if (i % 2 == 0) ?null else ??null);
      let expected : ???Nat = switch (i % 3) { case 0 ?null; case 1 ??null; case _ ???i };
      assert Q.popFront(nested) == expected;
      i += 1;
    };
    assert Q.popFront(nulls) == null and Q.popFront(options) == null and Q.popFront(nested) == null;
    assert Q.peekFront(nulls) == null and Q.peekBack(nulls) == null;
    assert Q.peekFront(options) == null and Q.peekBack(options) == null;
    assert Q.peekFront(nested) == null and Q.peekBack(nested) == null;
    Q.assertValid(nulls); Q.assertValid(options); Q.assertValid(nested);

    type Value = {id : Nat; cell : {var value : Nat}; read : () -> Nat; bytes : Blob};
    let cell = {var value = 0};
    let q = Q.empty<Value>();
    let alias = q;
    i := 0;
    while (i < 65) {
      Q.pushBack(q, {id = i; cell; read = func() : Nat { cell.value }; bytes = ("\00\ff" : Blob)});
      i += 1;
    };
    let clone = Q.clone(q);
    Q.clear(alias);
    assert Q.isEmpty(q) and Q.size(clone) == 65;
    switch (Q.peekFront(clone)) { case (?value) { value.cell.value := 70 }; case null assert false };
    assert cell.value == 70;
    i := 0;
    for (value in Q.values(clone)) {
      assert value.id == i and value.read() == 70 and value.bytes == "\00\ff";
      i += 1;
    };
    // Supported traversal callbacks can read this queue and mutate payloads or
    // a distinct queue. This also checks callback order and short-circuiting.
    let side = Q.empty<Nat>();
    Q.forEach(clone, func(value) {
      assert Q.size(clone) == 65;
      value.cell.value += 1;
      Q.pushBack(side, value.id);
    });
    assert cell.value == 135;
    assert Q.toArray(side) == Array.tabulate<Nat>(65, func(n) { n });
    let functions = Q.fromArray<() -> Nat>([func() : Nat { cell.value }, func() : Nat { 42 }]);
    switch (Q.popFront(functions)) { case (?f) assert f() == 135; case null assert false };
    switch (Q.popBack(functions)) { case (?f) assert f() == 42; case null assert false };
    assert Q.isEmpty(functions);
    let huge = 2 ** 256;
    let mixed = Q.fromArray<{#nat : Nat; #text : Text; #array : [var Nat]}>([
      #nat(huge), #text("plain ☃️ 雪"), #array([var 1, 2, 3])
    ]);
    switch (Q.popFront(mixed)) { case (?#nat(n)) assert n == huge; case _ assert false };
    switch (Q.popFront(mixed)) { case (?#text(t)) assert t == "plain ☃️ 雪"; case _ assert false };
    switch (Q.popBack(mixed)) { case (?#array(a)) { a[1] := 9; assert a[1] == 9 }; case _ assert false };
    Q.assertValid(mixed);
  };

  public func bulkExports() {
    // The optimized array path must preserve the option used for occupancy
    // separately from options that are actual payload values.
    for (n in [0, 1, 31, 32, 33, 63, 64, 65, 129].values()) {
      let q = Q.empty<??Nat>();
      let expected = Core.empty<??Nat>();
      let nulls = Q.empty<Null>();
      let options = Q.empty<?Null>();
      var i = 0;
      while (i < n) {
        let value : ??Nat = switch (i % 3) { case 0 null; case 1 ?null; case _ ??i };
        if (i % 2 == 0) { Q.pushBack(q, value); Core.pushBack(expected, value) }
        else { Q.pushFront(q, value); Core.pushFront(expected, value) };
        Q.pushBack(nulls, null);
        Q.pushFront(options, if (i % 2 == 0) null else ?null);
        i += 1;
      };
      // Churn both ends to cover nonzero start offsets in first/last chunks.
      i := 0;
      while (i < n / 2) {
        assert Q.popFront(q) == Core.popFront(expected);
        Q.pushBack(q, ??(1000 + i)); Core.pushBack(expected, ??(1000 + i));
        i += 1;
      };
      assert Q.toArray(q) == Core.toArray(expected);
      let mutable = Q.toVarArray(q);
      assert VarArray.toArray(mutable) == Core.toArray(expected);
      if (n > 0) { mutable[0] := ??999_999 };
      assert Q.toArray(q) == Core.toArray(expected);
      assert Q.toArray(nulls) == Array.tabulate<Null>(n, func(_) { null });
      assert VarArray.toArray(Q.toVarArray(nulls)) == Array.tabulate<Null>(n, func(_) { null });
      let optionExpected = Array.tabulate<?Null>(n, func(index) {
        if ((n - 1 - index : Nat) % 2 == 0) null else ?null
      });
      assert Q.toArray(options) == optionExpected;
      assert VarArray.toArray(Q.toVarArray(options)) == optionExpected;
      assert Iter.toArray(Q.reverseValues(q)) == Iter.toArray(Core.reverseValues(expected));
    };

    type Value = {id : Nat; cell : {var value : Nat}; read : () -> Nat};
    let cell = {var value = 10};
    let q = Q.empty<Value>();
    let functions = Q.empty<() -> Nat>();
    var i = 0;
    while (i < 129) {
      let id = i;
      Q.pushBack(q, {id; cell; read = func() : Nat { id + cell.value }});
      Q.pushFront(functions, func() : Nat { id + cell.value });
      i += 1;
    };
    let immutable = Q.toArray(q);
    let mutable = Q.toVarArray(q);
    let immutableFunctions = Q.toArray(functions);
    let mutableFunctions = Q.toVarArray(functions);
    immutable[64].cell.value := 20;
    for (index in Nat.range(0, 129)) {
      assert immutable[index].id == index and immutable[index].read() == index + 20;
      assert mutable[index].cell.value == 20 and mutable[index].read() == index + 20;
      assert immutableFunctions[index]() == (148 - index : Nat);
      assert mutableFunctions[index]() == (148 - index : Nat);
    };
    mutable[0] := {id = 999; cell = {var value = 0}; read = func() : Nat { 999 }};
    mutableFunctions[0] := func() : Nat { 0 };
    switch (Q.peekFront(q)) { case (?v) assert v.id == 0 and v.read() == 20; case null assert false };
    switch (Q.peekFront(functions)) { case (?f) assert f() == 148; case null assert false };
    Q.clear(q); Q.clear(functions);
    assert immutable[128].read() == 148 and immutableFunctions[0]() == 148;
    assert mutable[128].read() == 148 and mutableFunctions[128]() == 20;

    // Any intentionally erases inspectable payload types. Count/iteration and
    // invariant checks still detect lost entries from optional representations.
    let erased = Q.fromArray<Any>([null, ?null, ??(7 : Nat), cell, func() : Nat { 8 }, "text", [var 1]]);
    assert Q.toArray(erased).size() == 7 and Q.toVarArray(erased).size() == 7;
    var count = 0;
    for (_ in Q.values(erased)) { count += 1 };
    assert count == 7;
    Q.assertValid(erased);
    while (not Q.isEmpty(erased)) { ignore Q.popBack(erased) };
    switch (Q.peekFront(erased), Q.peekBack(erased)) { case (null, null) {}; case _ assert false };
    Q.assertValid(erased);
  };
}
