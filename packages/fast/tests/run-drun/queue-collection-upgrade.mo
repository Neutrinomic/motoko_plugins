//MOC-FLAG --plugin ../../../../dist/queue --package fast ../../src --package core $MOTOKO_CORE
//MOC-FLAG --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Q "mo:fast/Queue";
import Prim "mo:⛔";

actor {
  type Value = {id : Nat; bytes : Blob; cell : {var count : Nat}};
  let queue = Q.empty<Value>();
  let alias = queue;
  var copy = Q.empty<Value>();
  let nested = Q.empty<??Nat>();
  let nulls = Q.empty<?Null>();
  // This queue deliberately retains a detached spare over every upgrade.
  let recycled = Q.empty<?Null>();
  let cell = {var count = 0};
  var bytes : Blob = "";
  var front = 0;
  var generation = 0;

  func verify() {
    assert Q.size(queue) == 130 and Q.size(alias) == 130 and Q.size(copy) == 130;
    Q.assertValid(queue); Q.assertValid(copy); Q.assertValid(nested); Q.assertValid(nulls); Q.assertValid(recycled);
    assert Q.size(recycled) == 32;
    var recycledIndex = 0;
    for (v in Q.values(recycled)) {
      assert v == (if (recycledIndex % 2 == 0) null else ?null);
      recycledIndex += 1;
    };
    assert recycledIndex == 32;
    var expected = front;
    for (v in Q.values(alias)) {
      assert v.id == expected and v.cell.count == generation;
      assert v.bytes.size() == 1024 * 1024 and v.bytes[0] == 29 and v.bytes[1024 * 1024 - 1] == 29;
      expected += 1;
    };
    expected := 0;
    for (v in Q.values(copy)) { assert v.id == expected and v.cell.count == generation; expected += 1 };
    assert expected == 130;
    expected := 0;
    for (v in Q.values(nested)) {
      assert v == (switch (expected % 3) { case 0 null; case 1 ?null; case _ ??expected });
      expected += 1;
    };
    assert expected == 130;
    expected := 0;
    for (v in Q.reverseValues(nulls)) {
      assert v == (if (expected % 2 == 0) ?null else null);
      expected += 1;
    };
    assert expected == 130;
  };

  public func prepare() : async () {
    assert Q.isEmpty(queue);
    bytes := Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) { 29 }));
    var i = 0;
    while (i < 130) {
      Q.pushBack(queue, {id = i; bytes; cell});
      Q.pushBack(nested, switch (i % 3) { case 0 null; case 1 ?null; case _ ??i });
      Q.pushBack(nulls, if (i % 2 == 0) null else ?null);
      i += 1;
    };
    copy := Q.clone(queue);
    i := 0;
    while (i < 32) {
      Q.pushBack(recycled, if (i % 2 == 0) null else ?null);
      i += 1;
    };
    Q.pushFront(recycled, ?null);
    assert Q.popFront(recycled) == ??null;
    verify();
  };

  public func change() : async () {
    verify();
    generation += 1;
    switch (Q.peekFront(copy)) { case (?v) v.cell.count += 1; case null assert false };
    Q.pushBack(recycled, ?null);
    assert Q.popBack(recycled) == ??null;
    Q.pushFront(recycled, null);
    assert Q.popFront(recycled) == ?null;
    var i = 0;
    while (i < 17) {
      switch (Q.popFront(alias)) { case (?v) assert v.id == front; case null assert false };
      Q.pushBack(alias, {id = front + 130; bytes; cell});
      front += 1;
      i += 1;
    };
    verify();
  };

  public func collectAndCheck() : async () {
    let before = Prim.rts_reclaimed();
    var i = 0;
    while (i < 8) { ignore Prim.Array_init<Nat>(1024 * 1024, i); i += 1 };
    i := 0;
    while (i < 8) { await async {}; verify(); i += 1 };
    assert Prim.rts_reclaimed() > before + 16 * 1024 * 1024;
    Prim.debugPrint("queue upgrade preserves chunks, aliases, clones and nullable values");
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
