import Test "mo:test";
import Secp "mo:fast/Secp256k1";
import Vectors "Vectors";
import Prim "mo:⛔";

persistent actor {
  type Retained = {
    vector : Vectors.Vector;
    publicKey : Secp.PreparedPublicKey;
    schnorrPublicKey : Secp.PreparedSchnorrPublicKey;
    schnorrSecretKey : Secp.PreparedSchnorrSecretKey;
  };

  // Each root shape owns a different prepared key. In particular, the frame
  // closure's handles have no actor-field or persistent alias to rescue them.
  transient var actorField : ?Retained = null;
  transient var nestedFields : [{ handles : [Retained] }] = [];

  func ok<T>(result : Secp.Result<T>) : T {
    switch result {
      case (#ok value) value;
      case (#err _) Prim.trap("unexpected prepared secp256k1 error");
    }
  };

  func clone(bytes : Blob) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(bytes.size(), func(i) { bytes[i] }))
  };

  func prepare(index : Nat) : Retained {
    let source = Vectors.cases[index];
    // Inputs as well as native prepared outputs must be managed heap values.
    let vector : Vectors.Vector = {
      secret = clone(source.secret); key = clone(source.key); xOnly = clone(source.xOnly);
      digest = clone(source.digest); message = clone(source.message); auxiliary = clone(source.auxiliary);
      ecdsa = clone(source.ecdsa); ecdsaHighS = clone(source.ecdsaHighS);
      schnorr = clone(source.schnorr); badSchnorr = clone(source.badSchnorr);
      otherEcdsa = clone(source.otherEcdsa); otherSchnorr = clone(source.otherSchnorr);
    };
    // Holes separate all three opaque allocations, so a compacting collection
    // must correctly find and forward the payload of each prepared type.
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let publicKey = ok(Secp.preparePublicKey(vector.key));
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let schnorrPublicKey = ok(Secp.prepareSchnorrPublicKey(vector.xOnly));
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let schnorrSecretKey = ok(Secp.prepareSchnorrSecretKey(vector.secret));
    { vector; publicKey; schnorrPublicKey; schnorrSecretKey }
  };

  func verify(retained : Retained) {
    let v = retained.vector;
    assert Secp.derivePublicKey(v.secret) == #ok(v.key);
    assert Secp.signPrehash(v.secret, v.digest) == #ok(v.ecdsa);
    assert Secp.verifyPrehash(v.key, v.digest, v.ecdsa) == #ok(true);
    assert Secp.verifyPrehashPrepared(retained.publicKey, v.digest, v.ecdsa) == #ok(true);
    assert Secp.verifyPrehashPrepared(retained.publicKey, v.digest, v.ecdsaHighS) == #ok(true);
    assert Secp.schnorrSign(v.secret, v.message, v.auxiliary) == #ok(v.schnorr);
    assert Secp.schnorrSignPrepared(retained.schnorrSecretKey, v.message, v.auxiliary) == #ok(v.schnorr);
    assert Secp.schnorrVerify(v.xOnly, v.message, v.schnorr) == #ok(true);
    assert Secp.schnorrVerifyPrepared(retained.schnorrPublicKey, v.message, v.schnorr) == #ok(true);

    // Well-formed wrong-key/equation failures are false, while malformed input
    // lengths are typed errors. Neither path may alter a retained cache.
    assert Secp.verifyPrehashPrepared(retained.publicKey, v.digest, v.otherEcdsa) == #ok(false);
    assert Secp.schnorrVerifyPrepared(retained.schnorrPublicKey, v.message, v.otherSchnorr) == #ok(false);
    assert Secp.schnorrVerifyPrepared(retained.schnorrPublicKey, v.message, v.badSchnorr) == #ok(false);
    let shortDigest = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(31, func(i) { v.digest[i] }));
    assert Secp.verifyPrehashPrepared(retained.publicKey, shortDigest, v.ecdsa) == #err(#invalidDigest);
    assert Secp.verifyPrehashPrepared(retained.publicKey, v.digest, "") == #err(#invalidSignature);
    assert Secp.schnorrVerifyPrepared(retained.schnorrPublicKey, v.message, "") == #err(#invalidSignature);
    for (length in [0, 31, 33].values()) {
      let malformedAuxiliary = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(length, func(_) { 0 }));
      assert Secp.schnorrSign(v.secret, v.message, malformedAuxiliary) == #err(#invalidAuxiliaryRandomness);
      assert Secp.schnorrSignPrepared(retained.schnorrSecretKey, v.message, malformedAuxiliary) == #err(#invalidAuxiliaryRandomness);
      // Recheck immediately after each rejected input, then again after GC.
      assert Secp.schnorrSignPrepared(retained.schnorrSecretKey, v.message, v.auxiliary) == #ok(v.schnorr);
    };
    assert Secp.verifyPrehashPrepared(retained.publicKey, v.digest, v.ecdsa) == #ok(true);
    assert Secp.schnorrVerifyPrepared(retained.schnorrPublicKey, v.message, v.schnorr) == #ok(true);
  };

  func makeFrameCheck(index : Nat) : () -> () {
    let frameOnly = prepare(index);
    func() { verify(frameOnly) }
  };

  func checkActorFields() {
    switch actorField {
      case (?retained) verify(retained);
      case null Prim.trap("missing actor-field prepared handles");
    };
    assert nestedFields.size() == 1 and nestedFields[0].handles.size() == 1;
    verify(nestedFields[0].handles[0]);
  };

  func checkFrame(frameCheck : ?(() -> ())) {
    switch frameCheck {
      case (?check) check();
      case null Prim.trap("missing suspended-frame prepared handles");
    }
  };

  func pressure() : [var [var Nat]] {
    // Same confirmed-GC pressure shape as the existing Secp256k1 Ash test:
    // 64 MiB live arrays interleaved with 64 MiB dead arrays on the 64-bit RTS.
    Prim.Array_tabulateVar<[var Nat]>(128, func(n) {
      ignore Prim.Array_init<Nat>(64 * 1024, 0);
      Prim.Array_init<Nat>(64 * 1024, n)
    })
  };

  public func test_prepared_handles_survive_gc_and_reprepare() : async Test.Metrics {
    actorField := ?prepare(0);
    nestedFields := [{ handles = [prepare(1)] }];
    var frameCheck : ?(() -> ()) = ?makeFrameCheck(2);
    checkActorFields();
    checkFrame(frameCheck);

    let reclaimedBefore = Prim.rts_reclaimed();
    var live = pressure();
    await async {};
    var round = 0;
    while (round < 16) {
      assert live[0][65535] == 0 and live[127][65535] == 127;
      // Reverse the root order on alternating rounds to interleave key use.
      if (round % 2 == 0) {
        checkActorFields(); checkFrame(frameCheck);
      } else {
        checkFrame(frameCheck); checkActorFields();
      };
      ignore Prim.Array_init<Nat>(128 * 1024, round);
      round += 1;
      await async {};
    };
    assert Prim.rts_reclaimed() > reclaimedBefore + 16 * 1024 * 1024;
    checkActorFields();
    checkFrame(frameCheck);

    // Remove every intentional prepared-handle root, including the closure,
    // then require another collection before constructing replacement caches.
    actorField := null;
    nestedFields := [];
    frameCheck := null;
    live := [var];
    await async {};
    let droppedBefore = Prim.rts_reclaimed();
    live := pressure();
    await async {};
    round := 0;
    while (round < 16) {
      assert live[0][65535] == 0 and live[127][65535] == 127;
      ignore Prim.Array_init<Nat>(128 * 1024, round);
      round += 1;
      await async {};
    };
    assert Prim.rts_reclaimed() > droppedBefore + 16 * 1024 * 1024;

    // Rotate the three keys among root shapes on reprepare, detecting stale
    // scratch-state reuse as well as references lost during the first GC.
    actorField := ?prepare(2);
    nestedFields := [{ handles = [prepare(0)] }];
    frameCheck := ?makeFrameCheck(1);
    await async {};
    // Ash metrics cover this final synchronous verification only. The two
    // allocation/collection phases above are correctness assertions, not a
    // prepared-operation benchmark.
    return Test.test(func() {
      assert live[0][65535] == 0 and live[127][65535] == 127;
      checkFrame(frameCheck);
      checkActorFields();
      actorField := null;
      nestedFields := [];
      frameCheck := null;
      live := [var];
    })
  };
}
