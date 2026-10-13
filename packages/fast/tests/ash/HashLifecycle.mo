import Test "mo:test";
import Prim "mo:⛔";
import Audit "../../../../tests/crypto-audit/round5/hashes/Public";

persistent actor {
  transient var retained : ?Audit.Suite = null;
  func collect() : async () {
    var round = 0;
    while (round < 9) {
      var pressure = 0;
      while (pressure < 8) {
        ignore Prim.Array_init<Nat>(131_072, round + pressure);
        pressure += 1;
      };
      await async {};
      round += 1;
    };
    var settle = 0;
    while (settle < 4) { await async {}; settle += 1 };
  };
  public func test_hash_states_and_prepared_hmac_survive_collection() : async Test.Metrics {
    retained := ?Audit.Suite();
    let before = Prim.rts_reclaimed();
    await collect();
    assert Prim.rts_reclaimed() > before + 4 * 1024 * 1024;
    switch retained { case (?suite) suite.finish(); case null assert false };
    let second = Prim.rts_reclaimed();
    await collect();
    assert Prim.rts_reclaimed() > second + 4 * 1024 * 1024;
    let metrics = Test.test(func() {
      switch retained { case (?suite) suite.replay(); case null assert false };
    });
    retained := null;
    metrics
  };
}
