import Test "mo:test";
import MLDSA "mo:fast/MLDSA";
import Cases "Cases";
import Vectors "../../../../plugins/ml-dsa/tests/Vectors";
import Prim "mo:⛔";

persistent actor Self {
  type Retained = { seed : Blob; message : Blob; context : Blob; randomness : Blob; publicKey : Blob; signature : Blob };
  var durable : ?Retained = null;
  transient var temporary : ?Retained = null;

  public func tick() : async () {};
  public func test_retained_inputs_and_outputs_cross_forced_gc() : async Test.Metrics {
    let v = Vectors.sigGen[0];
    let reclaimedBefore = Prim.rts_reclaimed();
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let seed = Cases.copy(v.seed);
    let message = Cases.copy(v.message);
    let context = Cases.copy(v.context);
    let randomness = Cases.copy(v.randomness);
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let publicKey = Cases.ok(MLDSA.publicKey(seed));
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let signature = Cases.ok(MLDSA.signRandomized(seed, message, context, randomness));
    let retained : Retained = { seed; message; context; randomness; publicKey; signature };
    durable := ?retained; temporary := ?retained;
    func check() {
      assert durable == ?retained and temporary == ?retained;
      assert retained.seed == v.seed and retained.message == v.message;
      assert retained.context == v.context and retained.randomness == v.randomness;
      assert retained.publicKey == v.publicKey and retained.signature == v.signature;
      assert MLDSA.verify(retained.publicKey, retained.message, retained.signature, retained.context) == #ok(true);
      assert MLDSA.signRandomized(retained.seed, retained.message, retained.context, retained.randomness) == #ok(v.signature);
    };
    // Incremental GC pacing can defer small discarded allocations even with
    // --force-gc. Apply bounded 72 MiB pressure and allow collection to finish.
    var round = 0;
    while (round < 9) {
      var chunk = 0;
      while (chunk < 8) {
        ignore Prim.Array_init<Nat>(131_072, round + chunk);
        chunk += 1;
      };
      await Self.tick();
      check();
      round += 1;
    };
    var settle = 0;
    while (settle < 4) { await Self.tick(); check(); settle += 1 };
    // Confirm a collection actually reclaimed discarded allocations.
    assert Prim.rts_reclaimed() > reclaimedBefore + 4 * 1024 * 1024;
    durable := null; temporary := null;
    Test.test(func() {})
  };
}
