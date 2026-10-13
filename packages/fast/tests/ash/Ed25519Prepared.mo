import Test "mo:test";
import Ed25519 "mo:fast/Ed25519";
import Suite "../ed25519/PreparedSuite";
import Vectors "../ed25519/Vectors";
import Prim "mo:⛔";
import Map "mo:core/Map";
import Nat "mo:core/Nat";

persistent actor {
  public func test_prepared_rfc8032_all_pure_vectors() : async Test.Metrics { Test.test(func() { Suite.vectors(0, 5) }) };
  public func test_prepared_openssl_boundary_vectors() : async Test.Metrics { Test.test(func() { Suite.vectors(5, 15) }) };
  public func test_prepared_invalid_factories_and_recovery() : async Test.Metrics { Test.test(Suite.malformed) };
  public func test_prepared_aliases_and_input_immutability() : async Test.Metrics { Test.test(Suite.aliasesAndImmutability) };
  public func test_prepared_keys_retained_across_forced_gc() : async Test.Metrics {
    let v = Vectors.vectors[0];
    let secret = Suite.must(Ed25519.prepareSecretKey(v.seed));
    let publicKey = Suite.must(Ed25519.preparePublicKey(v.publicKey));
    let saved = { secret; publicKey };
    let aliases = [saved, saved];
    let stored = Map.empty<Nat, { secret : Ed25519.PreparedSecretKey; publicKey : Ed25519.PreparedPublicKey }>();
    Map.add(stored, Nat.compare, 0, saved);
    let signature = Ed25519.signPrepared(secret, v.message);
    func check() {
      assert Ed25519.signPrepared(aliases[1].secret, v.message) == v.signature;
      assert Ed25519.verifyPrepared(aliases[0].publicKey, v.message, signature) == #ok true;
      assert Ed25519.verifyPrepared(saved.publicKey, v.message, "") == #err(#invalidSignature);
      assert Ed25519.signPrepared(saved.secret, v.message) == v.signature;
      switch (Map.get(stored, Nat.compare, 0)) {
        case (?keys) {
          assert Ed25519.signPrepared(keys.secret, v.message) == v.signature;
          assert Ed25519.verifyPrepared(keys.publicKey, v.message, signature) == #ok true;
        };
        case null Prim.trap("lost prepared map entry");
      };
    };
    let reclaimed = Prim.rts_reclaimed();
    var round = 0;
    while (round < 9) {
      ignore Ed25519.signPrepared(Suite.must(Ed25519.prepareSecretKey(Vectors.vectors[1].seed)), "other");
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
