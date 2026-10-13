import Test "mo:test";
import MLDSA "mo:fast/MLDSA";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Prim "mo:⛔";
import Vectors "../../../../plugins/ml-dsa/tests/Vectors";

persistent actor {
  transient var storedPublic : ?MLDSA.PreparedPublicKey = null;
  transient var storedSecret : ?MLDSA.PreparedSecretKey = null;

  func unwrap<T>(result : MLDSA.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected prepared MLDSA error") }
  };
  func filled(size : Nat, byte : Nat8) : Blob {
    Blob.fromArray(Array.tabulate<Nat8>(size, func _ { byte }))
  };
  func checkSignature(v : Vectors.SigGen) {
    let publicKey = unwrap(MLDSA.preparePublicKey(v.publicKey));
    let secretKey = unwrap(MLDSA.prepareSecretKey(v.seed));
    assert MLDSA.signRandomizedPrepared(secretKey, v.message, v.context, v.randomness) == #ok(v.signature);
    if (v.deterministic) assert MLDSA.signPrepared(secretKey, v.message, v.context) == #ok(v.signature);
    assert MLDSA.verifyPrepared(publicKey, v.message, v.signature, v.context) == #ok(true);
  };

  public func test_official_prepared_deterministic_short_message() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[0]) })
  };
  public func test_official_prepared_deterministic_empty_context() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[1]) })
  };
  public func test_official_prepared_deterministic_255_context() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[2]) })
  };
  public func test_official_prepared_randomized_empty_context() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[3]) })
  };
  public func test_official_prepared_randomized_255_context() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[4]) })
  };
  public func test_official_prepared_randomized_short_message() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[5]) })
  };

  public func test_official_prepared_verification() : async Test.Metrics {
    Test.test(func() {
      for (v in Vectors.sigVer.values()) {
        let key = unwrap(MLDSA.preparePublicKey(v.publicKey));
        assert MLDSA.verifyPrepared(key, v.message, v.signature, v.context) == #ok(v.valid);
      };
    })
  };

  public func test_prepared_invalid_lengths_and_error_precedence() : async Test.Metrics {
    Test.test(func() {
      for (size in ([0, 1, 31, 33, 2560] : [Nat]).values()) {
        switch (MLDSA.prepareSecretKey(filled(size, 0))) {
          case (#err(#invalidSecretKey)) {}; case _ assert false;
        };
      };
      for (size in ([0, 1, 1311, 1313] : [Nat]).values()) {
        switch (MLDSA.preparePublicKey(filled(size, 0))) {
          case (#err(#invalidPublicKey)) {}; case _ assert false;
        };
      };
      let v = Vectors.sigGen[0];
      let publicKey = unwrap(MLDSA.preparePublicKey(v.publicKey));
      let secretKey = unwrap(MLDSA.prepareSecretKey(v.seed));
      let context = filled(256, 0);
      for (size in ([0, 1, 2419, 2421] : [Nat]).values()) {
        assert MLDSA.verifyPrepared(publicKey, "", filled(size, 0), context) == #err(#invalidSignature);
      };
      assert MLDSA.verifyPrepared(publicKey, "", v.signature, context) == #err(#invalidContext);
      assert MLDSA.signPrepared(secretKey, "", context) == #err(#invalidContext);
      assert MLDSA.signRandomizedPrepared(secretKey, "", context, "") == #err(#invalidContext);
      for (size in ([0, 1, 31, 33] : [Nat]).values()) {
        assert MLDSA.signRandomizedPrepared(secretKey, "", "", filled(size, 0)) == #err(#invalidRandomness);
      };
      assert MLDSA.signPrepared(secretKey, v.message, v.context) == #ok(v.signature);
      assert MLDSA.verifyPrepared(publicKey, v.message, v.signature, v.context) == #ok(true);
    })
  };

  public func test_prepared_keys_interleave_and_bind_context_message() : async Test.Metrics {
    Test.test(func() {
      let a = Vectors.sigGen[0];
      let b = Vectors.sigGen[5];
      let pa = unwrap(MLDSA.preparePublicKey(a.publicKey));
      let sa = unwrap(MLDSA.prepareSecretKey(a.seed));
      let pb = unwrap(MLDSA.preparePublicKey(b.publicKey));
      let sb = unwrap(MLDSA.prepareSecretKey(b.seed));
      let retained = MLDSA.signPrepared(sa, a.message, a.context);
      assert retained == #ok(a.signature);
      assert MLDSA.signRandomizedPrepared(sb, b.message, b.context, b.randomness) == #ok(b.signature);
      assert MLDSA.verifyPrepared(pa, a.message, a.signature, a.context) == #ok(true);
      assert MLDSA.verifyPrepared(pb, b.message, b.signature, b.context) == #ok(true);
      assert MLDSA.verifyPrepared(pb, a.message, a.signature, a.context) == #ok(false);
      assert MLDSA.verifyPrepared(pa, b.message, b.signature, b.context) == #ok(false);
      assert MLDSA.verifyPrepared(pa, "different", a.signature, a.context) == #ok(false);
      assert MLDSA.verifyPrepared(pa, a.message, a.signature, "") == #ok(false);
      assert MLDSA.signPrepared(sa, a.message, a.context) == retained;
      assert MLDSA.sign(a.seed, a.message, a.context) == retained;
      let randomized = unwrap(MLDSA.signRandomizedPrepared(sa, a.message, a.context, filled(32, 1)));
      assert randomized != a.signature;
      assert MLDSA.verifyPrepared(pa, a.message, randomized, a.context) == #ok(true);
      let empty = unwrap(MLDSA.signPrepared(sa, "", ""));
      assert MLDSA.verifyPrepared(pa, "", empty, "") == #ok(true);
      assert retained == #ok(a.signature);
    })
  };

  public func test_prepared_noncanonical_hints_and_z_return_false() : async Test.Metrics {
    Test.test(func() {
      let v = Vectors.sigGen[0];
      let key = unwrap(MLDSA.preparePublicKey(v.publicKey));
      let source = v.signature.toArray();
      func altered(at : Nat, byte : Nat8) : Blob {
        Blob.fromArray(Array.tabulate<Nat8>(2420, func i { if (i == at) byte else source[i] }))
      };
      let duplicateHints = Blob.fromArray(Array.tabulate<Nat8>(2420, func i {
        if (i < 2336) source[i] else if (i == 2336 or i == 2337) 1
        else if (i >= 2416) 2 else 0
      }));
      let badNorm = Blob.fromArray(Array.tabulate<Nat8>(2420, func i {
        if (i == 32 or i == 33) 0 else if (i == 34) source[i] & 252 else source[i]
      }));
      for (signature in ([altered(2416, 81), duplicateHints, badNorm, filled(2420, 0), filled(2420, 255)] : [Blob]).values()) {
        assert MLDSA.verifyPrepared(key, v.message, signature, v.context) == #ok(false);
      };
      assert MLDSA.verifyPrepared(key, v.message, v.signature, v.context) == #ok(true);
    })
  };

  public func test_prepared_aliases_and_argument_order() : async Test.Metrics {
    Test.test(func() {
      let v = Vectors.sigGen[0];
      let prepare = MLDSA.prepareSecretKey;
      let key = unwrap(prepare(v.seed));
      func identity<T>(value : T) : T = value;
      let keys = [key, identity(key)];
      let signers = [MLDSA.signPrepared, identity(MLDSA.signPrepared)];
      var order = "";
      let signature = (do { order #= "callee;"; signers[1] })(
        do { order #= "key;"; keys[1] },
        do { order #= "message;"; v.message },
        do { order #= "context;"; v.context }
      );
      assert order == "callee;key;message;context;";
      assert signature == #ok(v.signature);
      let verify : (MLDSA.PreparedPublicKey, Blob, Blob, Blob) -> MLDSA.Result<Bool> = MLDSA.verifyPrepared;
      assert verify(unwrap(MLDSA.preparePublicKey(v.publicKey)), v.message, v.signature, v.context) == #ok(true);
      assert MLDSA.signPrepared(keys[0], v.message, v.context) == signature;
    })
  };

  public func test_prepared_handles_in_transient_state_survive_await_gc() : async Test.Metrics {
    let v = Vectors.sigGen[0];
    let publicKey = unwrap(MLDSA.preparePublicKey(v.publicKey));
    let secretKey = unwrap(MLDSA.prepareSecretKey(v.seed));
    let publicAliases = [publicKey, publicKey];
    let secretAliases = [secretKey, secretKey];
    storedPublic := ?publicKey;
    storedSecret := ?secretKey;
    let retained = unwrap(MLDSA.signPrepared(secretKey, v.message, v.context));
    func checkSaved() {
      assert retained == v.signature;
      assert MLDSA.verifyPrepared(publicAliases[1], v.message, retained, v.context) == #ok(true);
      assert MLDSA.signPrepared(secretAliases[0], v.message, v.context) == #ok(retained);
      switch (storedPublic, storedSecret) {
        case (?pk, ?sk) {
          assert MLDSA.verifyPrepared(pk, v.message, retained, v.context) == #ok(true);
          assert MLDSA.signPrepared(sk, v.message, v.context) == #ok(retained);
        };
        case _ assert false;
      };
    };
    checkSaved();
    let reclaimed = Prim.rts_reclaimed();
    var round = 0;
    while (round < 9) {
      let other = Vectors.sigGen[5];
      let otherKey = unwrap(MLDSA.prepareSecretKey(other.seed));
      assert MLDSA.signRandomizedPrepared(otherKey, other.message, other.context, other.randomness) == #ok(other.signature);
      var pressure = 0;
      while (pressure < 8) {
        ignore Prim.Array_init<Nat>(131_072, round + pressure);
        pressure += 1;
      };
      await async {};
      checkSaved();
      round += 1;
    };
    var settle = 0;
    while (settle < 4) { await async {}; checkSaved(); settle += 1 };
    assert Prim.rts_reclaimed() > reclaimed + 4 * 1024 * 1024;
    let result = Test.test(checkSaved);
    storedPublic := null;
    storedSecret := null;
    result
  };
}
