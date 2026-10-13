import Test "mo:test";
import Prim "mo:⛔";
import CandidX "mo:fast/CandidX";
import Array "mo:core/Array";
import Principal "mo:core/Principal";

persistent actor {
  public query func test_scalars_and_references() : async Test.Metrics {
    Test.test(func() {
      assert CandidX.estimateSize() >= (to_candid()).size();
      assert CandidX.estimateSize(()) >= (to_candid(())).size();
      assert CandidX.estimateSize(null, true, '😀', 1.5) >= (to_candid(null, true, '😀', 1.5)).size();
      assert CandidX.estimateSize(0 : Nat8, 1 : Nat16, 2 : Nat32, 3 : Nat64,
        -1 : Int8, -2 : Int16, -3 : Int32, -4 : Int64) >=
        (to_candid(0 : Nat8, 1 : Nat16, 2 : Nat32, 3 : Nat64,
          -1 : Int8, -2 : Int16, -3 : Int32, -4 : Int64)).size();
      let service : actor { sample : shared (Nat, Text) -> async ?Blob } = actor "aaaaa-aa";
      assert CandidX.estimateSize(service, service.sample) >= (to_candid(service, service.sample)).size();
      assert CandidX.estimateSize(service) >= (to_candid(service)).size();
      assert CandidX.estimateSize(service.sample) == 2 ** 61 - 1;
      assert CandidX.estimateSize(test_scalars_and_references) == 2 ** 61 - 1;
      assert CandidX.estimateSize(null : ?(shared () -> async ())) < 100;
      assert CandidX.estimateSize(Principal.fromText("2vxsx-fae")) >=
        (to_candid(Principal.fromText("2vxsx-fae"))).size();
      var calls = 0;
      func next() : Nat { calls += 1; calls };
      ignore CandidX.estimateSize(next(), next(), next());
      assert calls == 3;
      assert CandidX.estimateSize([var 1] : Any) == CandidX.estimateSize(null : Any);
    })
  };

  public query func test_dynamic_values_and_unused_schema() : async Test.Metrics {
    Test.test(func() {
      type List = ?(Nat, List);
      type Choice = { #a : Nat; #b : Text; #unused : { words : [Text]; next : List } };
      let selected : Choice = #a 42;
      assert CandidX.estimateSize(selected) >= (to_candid(selected)).size();
      let noReference : { #data : Nat; #function : shared () -> async () } = #data 42;
      assert CandidX.estimateSize(noReference) < 100;
      let list : List = ?(1, ?(2, ?(3, null)));
      assert CandidX.estimateSize(list) >= (to_candid(list)).size();
      var seed : Nat = 17;
      var i = 0;
      while (i < 100) {
        seed := (seed * 48271) % 2147483647;
        let rows = Array.tabulate<{ name : Text; amount : Int; bytes : Blob; choice : Choice }>(
          seed % 13, func(j) {
            { name = if (j % 2 == 0) "hello 🌍" else "";
              amount = (seed : Int) - 1000000000;
              bytes = "\00\ff\01";
              choice = if (j % 2 == 0) #a(seed) else #b("λ") }
          });
        let oracle = to_candid(rows, list, null : ?Blob);
        assert CandidX.estimateSize(rows, list, null : ?Blob) >= oracle.size();
        i += 1;
      };
    })
  };

  public query func test_large_integers_without_allocation() : async Test.Metrics {
    Test.test(func() {
      for (bits in [60, 61, 62, 63, 64, 65, 255, 256, 257, 1023, 1024, 1025, 4095, 4096, 4097, 65536].vals()) {
        let value : Nat = 2 ** bits;
        let negative : Int = -(value : Int);
        let before = Prim.rts_total_allocation();
        let positiveSize = CandidX.estimateSize(value);
        let negativeSize = CandidX.estimateSize(negative);
        let after = Prim.rts_total_allocation();
        assert after == before;
        assert positiveSize >= (to_candid(value)).size();
        assert negativeSize >= (to_candid(negative)).size();
      };
    })
  };

  public query func test_fixed_arrays_and_text_ropes() : async Test.Metrics {
    Test.test(func() {
      type Row = { id : Nat64; flag : ?Bool; choice : { #small : Nat8; #big : Int64 } };
      let rows = Array.repeat<Row>({ id = 42; flag = null; choice = #small 1 }, 10000);
      let blob = Prim.arrayToBlob(Array.repeat<Nat8>(0, 65536));
      var rope = "🌍";
      var i = 0;
      while (i < 12) { rope #= rope; i += 1 };
      let before = Prim.rts_total_allocation();
      let bound = CandidX.estimateSize(rows, blob, rope);
      let after = Prim.rts_total_allocation();
      assert before == after;
      assert bound >= (to_candid(rows, blob, rope)).size();
      assert CandidX.estimateSize([] : [Row]) >= (to_candid([] : [Row])).size();
      assert CandidX.estimateSize([null, ?null, ??null] : [???Null]) >=
        (to_candid([null, ?null, ??null] : [???Null])).size();
    })
  };

  public func test_bounded_work_depth_and_recovery() : async Test.Metrics {
    Test.test(func() {
      type Tree = { #leaf : Text; #fork : (Tree, Tree) };
      var tree : Tree = #leaf "x";
      var i = 0;
      while (i < 25) { tree := #fork(tree, tree); i += 1 };
      assert CandidX.estimateSize(tree) == 2 ** 61 - 1;
      type List = ?(Text, List);
      var list : List = null;
      i := 0;
      while (i < 300) { list := ?("", list); i += 1 };
      assert CandidX.estimateSize(list) == 2 ** 61 - 1;
      let tooMany = Array.repeat<Text>("", 1000000);
      assert CandidX.estimateSize(tooMany) == 2 ** 61 - 1;
      assert CandidX.estimateSize("recovery") >= (to_candid("recovery")).size();
      assert CandidX.estimateSize("recovery") < 100;
    })
  };
}
