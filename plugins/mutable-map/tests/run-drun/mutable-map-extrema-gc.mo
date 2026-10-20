//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:prim";
import Map "mo:fast/Map";
import Text "mo:core/Text";

actor Self {
  type Payload = { var marker : Nat; var bytes : Blob };
  let original : Payload = { var marker = 0; var bytes = "" };
  let tree = Map.empty<Nat, Payload>();
  var retainedMin : ?Payload = null;
  var retainedMax : ?Payload = null;
  var live : [var [var Nat]] = [var];
  var generation = 0;
  var reclaimedBefore = 0;
  var sawPendingCycle = false;

  func compare(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a > b) #greater else #equal
  };
  func verify() {
    assert Map.size(tree) == 1024;
    switch (Map.minEntry(tree), Map.maxEntry(tree)) {
      case (?(minimum, minValue), ?(maximum, maxValue)) {
        assert minimum == 0 and maximum == 1023;
        assert minValue.marker == generation and maxValue.marker == generation;
        assert minValue.bytes.size() == 1024 * 1024;
        assert maxValue.bytes[0] == 37 and maxValue.bytes[1024 * 1024 - 1] == 37;
      };
      case _ assert false;
    };
    switch (retainedMin, retainedMax) {
      case (?minimum, ?maximum) {
        assert minimum.marker == generation and maximum.marker == generation;
      };
      case _ assert false;
    };
    assert original.marker == generation;
    for (i in live.keys()) if (i % 2 == 0) {
      assert live[i].size() == 65536;
      assert live[i][0] == i and live[i][65535] == i;
    } else assert live[i].size() == 0;
  };
  func verifyAliases() {
    // This also runs immediately after upgrade before replacing any payload.
    switch (Map.minEntry(tree), Map.maxEntry(tree), retainedMin, retainedMax) {
      case (?(_, minimum), ?(_, maximum), ?oldMinimum, ?oldMaximum) {
        minimum.marker += 1;
        assert original.marker == generation + 1;
        assert maximum.marker == generation + 1;
        assert oldMinimum.marker == generation + 1;
        assert oldMaximum.marker == generation + 1;
        maximum.marker := generation;
        assert minimum.marker == generation and original.marker == generation;
      };
      case _ assert false;
    };
    verify();
  };

  public func prepare() : async () {
    original.bytes := Prim.arrayToBlob(
      Prim.Array_tabulate<Nat8>(1024 * 1024, func(_) { 37 }));
    var i = 0;
    while (i < 1024) { Map.addNat(tree, i, original); i += 1 };
    switch (Map.minEntry(tree), Map.maxEntry(tree)) {
      case (?(_, minimum), ?(_, maximum)) {
        retainedMin := ?minimum; retainedMax := ?maximum;
      };
      case _ assert false;
    };
    // Interleaved holes force collection while the retained extrema stay live.
    live := Prim.Array_tabulateVar<[var Nat]>(384,
      func(i) { Prim.Array_init<Nat>(65536, i) });
    for (i in live.keys()) if (i % 2 == 1) live[i] := [var];
    reclaimedBefore := Prim.rts_reclaimed();
    verifyAliases();
  };

  public func step() : async () {
    sawPendingCycle := sawPendingCycle or
      Prim.rts_max_live_size() < 96 * 1024 * 1024;
    verifyAliases();
    generation += 1;
    original.marker := generation;
    // Bounded prefix/suffix pruning moves extrema across leaf boundaries.
    var i = 0;
    while (i < 48) {
      assert Map.delete(tree, compare, i);
      assert Map.delete(tree, compare, Prim.abs((1023 : Int) - i));
      switch (Map.minEntry(tree), Map.maxEntry(tree)) {
        case (?(minimum, left), ?(maximum, right)) {
          assert minimum == i + 1 and maximum == Prim.abs((1022 : Int) - i);
          assert left.marker == generation and right.marker == generation;
        };
        case _ assert false;
      };
      i += 1;
    };
    i := 0;
    while (i < 48) {
      Map.addNat(tree, i, original);
      Map.addNat(tree, Prim.abs((1023 : Int) - i), original);
      i += 1;
    };
    Map.assertValid(tree, compare);
    verifyAliases();
  };

  public func checkAliases() : async () { verifyAliases() };

  public func finish() : async () {
    verifyAliases();
    assert generation >= 16;
    assert sawPendingCycle;
    assert Prim.rts_max_live_size() >= 96 * 1024 * 1024;
    assert Prim.rts_reclaimed() > reclaimedBefore + 32 * 1024 * 1024;
    Prim.debugPrint("mutable-map extrema retained exact payload aliases across GC and upgrade");
  };

  func leaf(count : Nat32) : Map.Node<Nat, Nat> {
    let entries = Prim.Array_init<?(Nat, Nat)>(31, null);
    entries[0] := ?(1, 2);
    { var count; entries; children = [var] }
  };
  func deep(depth : Nat) : Map.Map<Nat, Nat> {
    var node = leaf(1);
    var i = 0;
    while (i < depth) {
      let child = node;
      node := { var count = (1 : Nat32);
        entries = [var ?(1, 2)]; children = [var ?child, ?child] };
      i += 1;
    };
    { var root = ?node; var size = 1 }
  };
  public func invalid(mode : Nat) : async () {
    let malformed = if (mode < 2) {
      { var root = ?leaf(0); var size = 0 }
    } else if (mode < 4) deep(129) else {
      let node = leaf(1);
      node.entries[0] := null;
      { var root = ?node; var size = 1 }
    };
    if (mode % 2 == 0) ignore Map.minEntry(malformed)
    else ignore Map.maxEntry(malformed);
  };
  public func checkMalformed() : async () {
    for (mode in [0, 1, 2, 3, 4, 5].values()) {
      var rejected = false;
      try { await Self.invalid(mode) } catch error {
        rejected := Text.contains(Prim.errorMessage(error),
          #text "mutable-map: malformed tree");
      };
      assert rejected;
    };
    Prim.debugPrint("mutable-map extrema reject zero count, depth 129 and null entries in both directions");
  };
};

//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress finish "DIDL\x00\x00"
//CALL ingress checkMalformed "DIDL\x00\x00"
//CALL upgrade ""
//CALL ingress checkAliases "DIDL\x00\x00"
//CALL ingress step "DIDL\x00\x00"
//CALL ingress finish "DIDL\x00\x00"
