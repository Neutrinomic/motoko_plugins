import Test "mo:test";
import Ed25519 "mo:fast/Ed25519";
import Suite "../ed25519/Suite";
import Vectors "../ed25519/Vectors";
import Prim "mo:⛔";

persistent actor {
  public func test_rfc8032_all_pure_vectors() : async Test.Metrics { Test.test(func() { Suite.vectors(0, 5) }) };
  public func test_openssl_boundary_vectors() : async Test.Metrics { Test.test(func() { Suite.vectors(5, 15) }) };
  public func test_seed_lengths_and_error_recovery() : async Test.Metrics { Test.test(Suite.malformed) };
  public func test_canonical_points_small_order_and_scalar_ranges() : async Test.Metrics { Test.test(Suite.strictPointsAndScalars) };
  public func test_aliases_input_immutability_and_pure_mode() : async Test.Metrics { Test.test(Suite.aliasesAndImmutability) };
  public func test_retained_outputs_across_forced_gc() : async Test.Metrics {
    let v = Vectors.vectors[0];
    let saved = Ed25519.sign(v.seed, v.message);
    let pair = Ed25519.keyPairFromSeed(v.seed);
    let aliases = [saved, saved];
    func check() {
      assert saved == #ok (v.signature);
      assert aliases[0] == aliases[1] and aliases[1] == #ok (v.signature);
      assert pair == #ok { secretKey = v.seed; publicKey = v.publicKey };
      assert Ed25519.verify(v.publicKey, v.message, v.signature) == #ok true;
    };
    let reclaimed = Prim.rts_reclaimed();
    var round = 0;
    while (round < 9) {
      ignore Ed25519.sign(Vectors.vectors[1].seed, "different");
      assert Ed25519.sign("", "") == #err(#invalidSecretKey);
      var pressure = 0;
      while (pressure < 8) { ignore Prim.Array_init<Nat>(131_072, round + pressure); pressure += 1 };
      await async {};
      check();
      round += 1;
    };
    var settle = 0;
    while (settle < 4) { await async {}; check(); settle += 1 };
    assert Prim.rts_reclaimed() > reclaimed + 4 * 1024 * 1024;
    Test.test(check)
  };
}
