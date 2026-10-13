import Test "mo:test";
import MLDSA "mo:fast/MLDSA";
import Cases "Cases";
import Vectors "../../../../plugins/ml-dsa/tests/Vectors";
import Prim "mo:⛔";

persistent actor Self {
  type Keys = {
    publicKey : MLDSA.PreparedPublicKey;
    secretKey : MLDSA.PreparedSecretKey;
    message : Blob; context : Blob; signature : Blob; randomness : Blob
  };
  transient var saved : ?[Keys] = null;

  func prepare(v : Vectors.SigGen) : Keys {
    assert v.deterministic;
    // Dynamically copied constructor inputs go out of scope here. Consumers
    // must use managed prepared bytes, never retained native input pointers.
    let secretKey = Cases.ok(MLDSA.prepareSecretKey(Cases.copy(v.seed)));
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let publicKey = Cases.ok(MLDSA.preparePublicKey(Cases.copy(v.publicKey)));
    { publicKey; secretKey; message = v.message; context = v.context;
      signature = v.signature; randomness = v.randomness }
  };

  func check(keys : [Keys]) {
    for (key in keys.values()) {
      assert MLDSA.verifyPrepared(key.publicKey, key.message, key.signature, key.context) == #ok(true);
      assert MLDSA.signPrepared(key.secretKey, key.message, key.context) == #ok(key.signature);
      assert MLDSA.signRandomizedPrepared(key.secretKey, key.message, key.context, key.randomness) == #ok(key.signature);
    };
    assert MLDSA.verifyPrepared(keys[0].publicKey, keys[1].message, keys[1].signature, keys[1].context) == #ok(false);
    assert MLDSA.verifyPrepared(keys[1].publicKey, keys[0].message, keys[0].signature, keys[0].context) == #ok(false);
  };
  public func tick() : async () {};
  public func test_prepared_keys_survive_interleaved_calls_and_collection() : async Test.Metrics {
    let reclaimed = Prim.rts_reclaimed();
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let keys = [prepare(Vectors.sigGen[0]), prepare(Vectors.sigGen[1])];
    saved := ?keys;
    // Capture a generic record/array of distinct prepared objects in an async
    // frame and in a closure, while another root comes from transient state.
    let closure = func() { check(keys) };
    var round = 0;
    while (round < 9) {
      var chunk = 0;
      while (chunk < 8) {
        ignore Prim.Array_init<Nat>(131_072, round + chunk);
        chunk += 1;
      };
      await Self.tick();
      closure();
      switch saved { case (?retained) check(retained); case null assert false };
      round += 1;
    };
    var settle = 0;
    while (settle < 4) { await Self.tick(); closure(); settle += 1 };
    assert Prim.rts_reclaimed() > reclaimed + 4 * 1024 * 1024;
    saved := null;
    // Printed Ash metrics cover this empty final block, not the async workload.
    Test.test(func() {})
  };
}
