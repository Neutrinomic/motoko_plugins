//MOC-FLAG --plugin ../../../../dist/pure-map
//MOC-FLAG --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Map "../../motoko/Map";
actor {
  type Tree = Map.Map<Nat, Blob>;
  var original : Tree = null;
  var retained : [Tree] = [];
  var payload : Blob = "";
  var originalBytes : Nat = 0;

  func cmp(a : Nat, b : Nat) : Map.Order { if (a < b) #less else if (a == b) #equal else #greater };
  func verify() {
    assert Map.size(original) == 4096;
    assert retained.size() == 16;
    assert payload.size() == 1024 * 1024;
    assert Map.getNat(original, 0) == ?payload;
    var version = 0;
    for (tree in retained.values()) {
      assert Map.size(tree) == 4096;
      Map.assertValid(tree, cmp);
      var key = 0;
      for ((stored, value) in Map.entries(tree)) {
        assert stored == key;
        if (key <= version) assert value == "changed"
        else {
          assert value.size() == originalBytes;
          // Every unchanged payload is a pre-existing ordinary managed Blob.
          // Equality is outside the allocation interval.
          if (key == 4095) assert value == payload;
        };
        key += 1;
      };
      assert key == 4096;
      version += 1;
    }
  };

  public func prepare() : async () {
    payload := Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024 * 1024, func(i) { Prim.natToNat8(i % 251) }));
    originalBytes := payload.size();
    let small : Blob = "small";
    let smallTree = Map.fromSortedDistinctArray(Prim.Array_tabulate<(Nat, Blob)>(4096, func(i) { (i, small) }), cmp);
    original := Map.fromSortedDistinctArray(Prim.Array_tabulate<(Nat, Blob)>(4096, func(i) { (i, payload) }), cmp);

    // Identical changed paths must cost the same with 5-byte and 1-MiB values.
    let beforeSmall = Prim.rts_total_allocation();
    let changedSmall = Map.addNat(smallTree, 0, small);
    let smallAllocation : Nat = Prim.rts_total_allocation() - beforeSmall;
    let beforeLarge = Prim.rts_total_allocation();
    let changedLarge = Map.addNat(original, 0, payload);
    let largeAllocation : Nat = Prim.rts_total_allocation() - beforeLarge;
    assert smallAllocation == largeAllocation;
    assert largeAllocation < 4096;
    assert Map.getNat(changedSmall, 0) == ?small;
    assert Map.getNat(changedLarge, 0) == ?payload;

    let beforeNoop = Prim.rts_total_allocation();
    let noChange = Map.removeNat(original, 999999);
    let noChangeAllocation : Nat = Prim.rts_total_allocation() - beforeNoop;
    assert noChangeAllocation == 0;
    assert Map.size(noChange) == 4096;
    let beforeReplace = Prim.rts_total_allocation();
    let (noReplacement, absentValue) = Map.replaceNat(original, 999999, small);
    let replaceAllocation : Nat = Prim.rts_total_allocation() - beforeReplace;
    assert replaceAllocation == 0;
    assert absentValue == null;
    assert Map.size(noReplacement) == 4096;

    var tree = original;
    let replacement : Blob = "changed";
    retained := Prim.Array_tabulate<Tree>(16, func(i) {
      let before = Prim.rts_total_allocation();
      tree := Map.addNat(tree, i, replacement);
      let allocated : Nat = Prim.rts_total_allocation() - before;
      assert allocated < 4096;
      tree
    });
    verify();
    Prim.debugPrint("pure-map update allocation ignores payload size; absent removal allocates zero");
  };
  public func churn() : async () {
    var i = 0;
    while (i < 10) { ignore Prim.Array_init<Nat>(1024 * 1024, i); i += 1 }
  };
  public func check() : async () {
    var i = 0;
    while (i < 4) { await async {}; verify(); i += 1 };
    Prim.debugPrint("pure-map branching roots and shared payload survived GC");
  };
};
//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress check "DIDL\x00\x00"
