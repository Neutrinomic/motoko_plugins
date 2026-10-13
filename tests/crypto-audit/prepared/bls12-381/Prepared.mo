import Test "mo:test";
import B "mo:fast/BLS12381";
import C "Cases";
import E "Extra";
import Prim "mo:⛔";
persistent actor Self {
  type Keys = { ic : [B.PreparedICPublicKey]; eth : [B.PreparedEthereumPublicKey]; pop : [B.PreparedEthereumPoPKey] };
  transient var retained : ?Keys = null;
  transient var closure : ?(() -> ()) = null;
  public func tick() : async () {};
  public func test_factory_validation() : async Test.Metrics { Test.test(C.factories) };
  public func test_prepared_single_signatures() : async Test.Metrics { Test.test(C.singles) };
  public func test_prepared_aggregates_0() : async Test.Metrics { Test.test(func() { C.aggregatePart(0) }) };
  public func test_prepared_aggregates_1() : async Test.Metrics { Test.test(func() { C.aggregatePart(1) }) };
  public func test_prepared_aggregates_2() : async Test.Metrics { Test.test(func() { C.aggregatePart(2) }) };
  public func test_boundaries_and_callbacks() : async Test.Metrics { Test.test(E.boundariesAndCallbacks) };
  public func test_prepared_values_survive_actual_gc_and_interleaving() : async Test.Metrics {
    let before = Prim.rts_reclaimed();
    let a = C.keys();
    retained := ?a;
    closure := ?(func() { C.checkRetained(a) });
    var round = 0;
    while (round < 9) {
      var chunk = 0;
      while (chunk < 8) { ignore Prim.Array_init<Nat>(131_072, round + chunk); chunk += 1 };
      // Fresh keys are interleaved with older heap-rooted arrays and a closure.
      let fresh = C.keys();
      await Self.tick();
      C.checkRetained(fresh);
      switch retained { case (?keys) C.checkRetained(keys); case null assert false };
      switch closure { case (?check) check(); case null assert false };
      round += 1;
    };
    var settle = 0;
    while (settle < 4) { await Self.tick(); C.checkRetained(a); settle += 1 };
    assert Prim.rts_reclaimed() > before + 4 * 1024 * 1024;
    retained := null; closure := null;
    Test.test(func() {})
  };
}
