//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Map "mo:fast/pure/Map";

actor {
  type Value = {cell : {var n : Nat}; read : () -> Nat};
  transient var cursors : [Map.EntryIter<Nat, Value>] = [];
  transient var view : ?Map.EntrySnapshot<Nat, Value> = null;
  transient var index = 0;
  transient var reclaimed = 0;

  public func prepare() : async () {
    var tree = Map.empty<Nat, Value>();
    var key = 0;
    while (key < 64) {
      let cell = {var n = key};
      tree := Map.addNat(tree, key, {cell; read = func() : Nat { cell.n }});
      key += 1;
    };
    let range = {root = tree; start = 7; end = 39; reverse = false};
    view := ?range;
    cursors := [Map.replay(range), Map.replay({range with reverse = true})];
    // Only snapshots and unstarted cursors retain the original root.
    ignore Map.addNat(tree, 7, {cell = {var n = 999}; read = func() : Nat { 999 }});
  };

  public func churn() : async () {
    reclaimed := Prim.rts_reclaimed();
    var i = 0;
    while (i < 8) { ignore Prim.Array_init<Nat>(1024 * 1024, i); i += 1 };
  };

  public func advance() : async () {
    var round = 0;
    while (round < 4) { await async {}; round += 1 };
    assert Prim.rts_reclaimed() > reclaimed + 16 * 1024 * 1024;
    var steps = 0;
    while (steps < 16) {
      var direction = 0;
      for (cursor in cursors.values()) {
        let expected = if (direction == 0) 7 + index else (38 - index : Nat);
        switch (cursor.next()) {
          case null { assert false };
          case (?(key, value)) {
            assert key == expected;
            assert value.cell.n == key and value.read() == key;
          }
        };
        direction += 1;
      };
      index += 1;
      steps += 1;
    };
    if (index == 32) {
      for (cursor in cursors.values()) {
        switch (cursor.next()) { case null {}; case _ { assert false } };
        switch (cursor.next()) { case null {}; case _ { assert false } };
      };
      let saved = switch view { case (?v) v; case null { assert false; loop {} } };
      let replay = Map.replay(saved);
      switch (replay.next()) { case (?(7, value)) { assert value.read() == 7 }; case _ { assert false } };
    };
  };
};
//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress advance "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress advance "DIDL\x00\x00"
