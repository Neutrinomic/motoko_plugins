//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Map "mo:fast/pure/Map";

actor {
  type Cell = {var count : Nat};
  type Payload = {revision : Nat; bytes : Blob; cell : Cell; read : () -> Nat};
  type Tree = Map.Map<Nat, Payload>;
  transient var tree : Tree = null;
  transient var history : [var ?Tree] = [var];
  transient var side : Map.Map<Nat, Nat> = null;
  transient var retainedReplace : ?(Tree, ?Payload) = null;
  transient var retainedStaticReplace : ?(Tree, ?Payload) = null;
  transient var retainedSplit : ?(Tree, ?(Nat, Payload), Tree) = null;
  transient var step = 0;
  transient var comparatorCalls = 0;
  transient var reclaimedBefore = 0;

  func compare(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func allocatingCompare(a : Nat, b : Nat) : Map.Order {
    comparatorCalls += 1;
    // Reenter another native search while outer frames retain this map's path.
    assert Map.getNat(side, 9) == ?90;
    ignore Prim.Array_init<Nat>(2048, comparatorCalls);
    compare(a, b)
  };

  func retainResults() {
    let payload = switch (Map.get(tree, compare, 128)) {
      case null Prim.trap("missing native result payload");
      case (?value) value;
    };
    // These results must be packed as managed tuples when retained, despite
    // staying on the stack for an immediate destructuring consumer.
    retainedReplace := ?Prim.pmap_replace<Nat, Payload>(tree, compare, 128, payload);
    retainedStaticReplace := ?Prim.pmap_replace_static<Nat, Payload>(tree, 128, payload);
    retainedSplit := ?Prim.pmap_split<Nat, Payload>(tree, compare, 128);
  };

  func verifyPayload(value : Payload, revision : Nat) {
    assert value.revision == revision;
    assert value.bytes.size() == 1024 * 1024;
    assert value.bytes[0] == 17;
    assert value.bytes[1024 * 1024 - 1] == 17;
    assert value.cell.count == step;
    assert value.read() == step;
  };

  func verify() {
    var version = 0;
    while (version <= step) {
      let old = switch (history[version]) {
        case null Prim.trap("missing retained map version");
        case (?value) value;
      };
      assert Map.size(old) == 256;
      for (key in [0, 128, 255].values()) {
        switch (Map.get(old, compare, key)) {
          case null Prim.trap("missing retained map payload");
          case (?value) {
            verifyPayload(value, if (key == 128) version else 0);
          };
        }
      };
      version += 1;
    };
    for (result in [retainedReplace, retainedStaticReplace].values()) {
      switch result {
        case (?(next, ?previous)) {
          assert Map.size(next) == 256;
          verifyPayload(previous, step);
          switch (Map.get(next, compare, 128)) {
            case null Prim.trap("missing replacement result entry");
            case (?value) verifyPayload(value, step);
          };
        };
        case _ Prim.trap("missing retained replacement tuple");
      }
    };
    switch retainedSplit {
      case (?(left, ?(key, previous), right)) {
        assert key == 128;
        assert Map.size(left) == 128;
        assert Map.size(right) == 127;
        verifyPayload(previous, step);
        switch (Map.get(left, compare, 127), Map.get(right, compare, 129)) {
          case (?a, ?b) {verifyPayload(a, 0); verifyPayload(b, 0)};
          case _ Prim.trap("missing retained split subtree");
        };
      };
      case _ Prim.trap("missing retained split tuple");
    };
  };

  public func prepare() : async () {
    tree := null;
    side := Map.addNat(Map.empty<Nat, Nat>(), 9, 90);
    history := Prim.Array_init<?Tree>(5, null);
    step := 0;
    comparatorCalls := 0;
    let cell : Cell = {var count = 0};
    let bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024,
      func (_index : Nat) : Nat8 {17}));
    let payload : Payload = {revision = 0; bytes; cell; read = func () : Nat {cell.count}};
    var key = 0;
    while (key < 256) {
      tree := Map.add(tree, compare, key, payload);
      key += 1;
    };
    history[0] := ?tree;
    // A point update with a 1 MiB shared payload must not copy that payload or
    // every node. This bound permits argument/result overhead and path copies.
    let before : Int = Prim.rts_total_allocation();
    let replaced = Map.add(tree, compare, 128, payload);
    let after : Int = Prim.rts_total_allocation();
    assert after - before < 16384;
    assert Map.size(replaced) == 256;
    retainResults();
    verify();
  };

  public func change() : async () {
    assert step < 4;
    var alterations = 0;
    let nextStep = step + 1;
    tree := Map.alter(tree, allocatingCompare, 128, func (old : ?Payload) : ?Payload {
      alterations += 1;
      assert Map.getNat(side, 9) == ?90;
      ignore Prim.Array_init<Nat>(8192, nextStep);
      switch old {
        case null Prim.trap("missing alteration payload");
        case (?value) {
          assert value.revision == step;
          value.cell.count += 1;
          ?{value with revision = nextStep}
        };
      }
    });
    assert alterations == 1;
    assert comparatorCalls > 0;
    step := nextStep;
    history[step] := ?tree;
    retainResults();
    verify();
  };

  public func churn() : async () {
    reclaimedBefore := Prim.rts_reclaimed();
    var i = 0;
    while (i < 9) {
      ignore Prim.Array_init<Nat>(1024 * 1024, i);
      i += 1;
    };
  };
  public func collectAndCheck() : async () {
    var i = 0;
    while (i < 4) {
      await async {};
      verify();
      i += 1;
    };
    assert Prim.rts_reclaimed() > reclaimedBefore + 32 * 1024 * 1024;
    Prim.debugPrint("pure-map shared versions survived GC and allocating callbacks");
  };
};

//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
