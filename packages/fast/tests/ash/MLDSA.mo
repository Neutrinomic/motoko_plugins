import Test "mo:test";
import MLDSA "mo:fast/MLDSA";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Prim "mo:⛔";
import Vectors "../../../../plugins/ml-dsa/tests/Vectors";

// Final FIPS 204 ML-DSA-44, pure external interface. Expectations come from
// pinned official NIST ACVP answers; see coverage/MLDSA.md.
persistent actor {
  func filled(size : Nat, byte : Nat8) : Blob {
    Blob.fromArray(Array.tabulate<Nat8>(size, func _ { byte }))
  };
  func changed(bytes : Blob, at : Nat, byte : Nat8) : Blob {
    let source = bytes.toArray();
    Blob.fromArray(Array.tabulate<Nat8>(bytes.size(), func i {
      if (i == at) byte else source[i]
    }))
  };
  func append(a : Blob, b : Blob) : Blob { Blob.fromArray(a.toArray().concat(b.toArray())) };
  func unwrap<T>(result : MLDSA.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected MLDSA failure") }
  };
  func checkSignature(v : Vectors.SigGen) {
    assert MLDSA.publicKey(v.seed) == #ok(v.publicKey);
    assert MLDSA.signRandomized(v.seed, v.message, v.context, v.randomness) == #ok(v.signature);
    if (v.deterministic) assert MLDSA.sign(v.seed, v.message, v.context) == #ok(v.signature);
    assert MLDSA.verify(v.publicKey, v.message, v.signature, v.context) == #ok(true);
  };
  func checkVerification(first : Nat, last : Nat) {
    var i = first;
    while (i < last) {
      let v = Vectors.sigVer[i];
      assert MLDSA.verify(v.publicKey, v.message, v.signature, v.context) == #ok(v.valid);
      i += 1;
    }
  };

  public func test_official_key_generation() : async Test.Metrics {
    Test.test(func() {
      for (v in Vectors.keyGen.values()) assert MLDSA.publicKey(v.seed) == #ok(v.publicKey);
      // The secret is a seed, not a scalar: all bit patterns are accepted.
      assert unwrap(MLDSA.publicKey(filled(32, 0))).size() == 1312;
      assert unwrap(MLDSA.publicKey(filled(32, 255))).size() == 1312;
    })
  };
  public func test_official_deterministic_short_message() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[0]) })
  };
  public func test_official_deterministic_empty_context() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[1]) })
  };
  public func test_official_deterministic_8192_message_255_context() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[2]) })
  };
  public func test_official_randomized_empty_context() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[3]) })
  };
  public func test_official_randomized_255_context() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[4]) })
  };
  public func test_official_randomized_short_message() : async Test.Metrics {
    Test.test(func() { checkSignature(Vectors.sigGen[5]) })
  };
  public func test_official_verification_1() : async Test.Metrics { Test.test(func() { checkVerification(0, 3) }) };
  public func test_official_verification_2() : async Test.Metrics { Test.test(func() { checkVerification(3, 6) }) };
  public func test_official_verification_3() : async Test.Metrics { Test.test(func() { checkVerification(6, 9) }) };
  public func test_official_verification_4() : async Test.Metrics { Test.test(func() { checkVerification(9, 12) }) };
  public func test_official_verification_5() : async Test.Metrics { Test.test(func() { checkVerification(12, 15) }) };

  public func test_input_lengths_and_error_precedence() : async Test.Metrics {
    Test.test(func() {
      let v = Vectors.sigGen[0];
      let tooLong = filled(256, 0);
      for (size in ([0, 1, 31, 33, 2560] : [Nat]).values()) {
        let key = filled(size, 0);
        assert MLDSA.publicKey(key) == #err(#invalidSecretKey);
        assert MLDSA.sign(key, "", tooLong) == #err(#invalidSecretKey);
        assert MLDSA.signRandomized(key, "", tooLong, "") == #err(#invalidSecretKey);
      };
      for (size in ([0, 1, 1311, 1313] : [Nat]).values()) {
        assert MLDSA.verify(filled(size, 0), "", "", tooLong) == #err(#invalidPublicKey);
      };
      for (size in ([0, 1, 2419, 2421] : [Nat]).values()) {
        assert MLDSA.verify(v.publicKey, "", filled(size, 0), tooLong) == #err(#invalidSignature);
      };
      assert MLDSA.verify(v.publicKey, "", v.signature, tooLong) == #err(#invalidContext);
      assert MLDSA.sign(v.seed, "", tooLong) == #err(#invalidContext);
      assert MLDSA.signRandomized(v.seed, "", tooLong, "") == #err(#invalidContext);
      for (size in ([0, 1, 31, 33] : [Nat]).values()) {
        assert MLDSA.signRandomized(v.seed, "", "", filled(size, 0)) == #err(#invalidRandomness);
      };
      assert MLDSA.sign(v.seed, v.message, v.context) == #ok(v.signature);
    })
  };

  public func test_context_message_and_randomness_binding() : async Test.Metrics {
    Test.test(func() {
      let v = Vectors.sigGen[0];
      assert MLDSA.verify(v.publicKey, append(v.message, "!"), v.signature, v.context) == #ok(false);
      assert MLDSA.verify(v.publicKey, v.message, v.signature, "different") == #ok(false);
      assert MLDSA.verify(v.publicKey, v.message, v.signature, "") == #ok(false);
      assert MLDSA.verify(Vectors.keyGen[0].publicKey, v.message, v.signature, v.context) == #ok(false);
      let signature = unwrap(MLDSA.signRandomized(v.seed, v.message, v.context, filled(32, 1)));
      assert signature != v.signature;
      assert MLDSA.verify(v.publicKey, v.message, signature, v.context) == #ok(true);
      let empty = unwrap(MLDSA.sign(v.seed, "", ""));
      assert MLDSA.verify(v.publicKey, "", empty, "") == #ok(true);
      assert MLDSA.sign(v.seed, "", "") == #ok(empty);
    })
  };

  public func test_noncanonical_hints_and_out_of_bound_z() : async Test.Metrics {
    Test.test(func() {
      let v = Vectors.sigGen[0];
      let original = v.signature.toArray();
      let zeroTail = Blob.fromArray(Array.tabulate<Nat8>(2420, func i {
        if (i < 2336) original[i] else 0
      }));
      let duplicateHints = Blob.fromArray(Array.tabulate<Nat8>(2420, func i {
        if (i < 2336) original[i]
        else if (i == 2336 or i == 2337) 1
        else if (i >= 2416) 2 else 0
      }));
      let badNorm = Blob.fromArray(Array.tabulate<Nat8>(2420, func i {
        if (i == 32 or i == 33) 0
        else if (i == 34) original[i] & 252
        else original[i]
      }));
      let malformed : [Blob] = [
        changed(v.signature, 2416, 81),
        changed(changed(v.signature, 2416, 2), 2417, 1),
        changed(zeroTail, 2336, 1), duplicateHints, badNorm,
        filled(2420, 0), filled(2420, 255),
      ];
      for (signature in malformed.values()) {
        assert MLDSA.verify(v.publicKey, v.message, signature, v.context) == #ok(false);
      };
      assert MLDSA.verify(v.publicKey, v.message, v.signature, v.context) == #ok(true);
    })
  };

  public func test_aliases_argument_order_and_retained_outputs() : async Test.Metrics {
    Test.test(func() {
      let v = Vectors.sigGen[0];
      func identity<T>(x : T) : T = x;
      let signers = [MLDSA.sign, identity(MLDSA.sign)];
      var order = "";
      let saved = (do { order #= "callee;"; signers[1] })(
        do { order #= "seed;"; v.seed },
        do { order #= "message;"; v.message },
        do { order #= "context;"; v.context }
      );
      assert order == "callee;seed;message;context;";
      assert saved == #ok(v.signature);
      let randomized = MLDSA.signRandomized;
      assert randomized(v.seed, v.message, v.context, filled(32, 0)) == saved;
      let verify : (Blob, Blob, Blob, Blob) -> MLDSA.Result<Bool> = func(pk, msg, sig, ctx) {
        MLDSA.verify(pk, msg, sig, ctx)
      };
      assert verify(v.publicKey, v.message, v.signature, v.context) == #ok(true);
      assert MLDSA.publicKey(Vectors.keyGen[0].seed) == #ok(Vectors.keyGen[0].publicKey);
      assert MLDSA.sign("", "", "") == #err(#invalidSecretKey);
      assert saved == #ok(v.signature);
    })
  };

  public func test_outputs_survive_await_and_confirmed_collection() : async Test.Metrics {
    let v = Vectors.sigGen[0];
    let publicKey = unwrap(MLDSA.publicKey(v.seed));
    let signature = unwrap(MLDSA.sign(v.seed, v.message, v.context));
    let aliases = [signature, publicKey, signature];
    func checkSaved() {
      assert publicKey == v.publicKey and publicKey.size() == 1312;
      assert signature == v.signature and signature.size() == 2420;
      assert aliases[0] == v.signature and aliases[1] == v.publicKey and aliases[2] == v.signature;
    };
    checkSaved();
    let reclaimed = Prim.rts_reclaimed();
    var round = 0;
    while (round < 9) {
      assert MLDSA.publicKey(Vectors.keyGen[0].seed) == #ok(Vectors.keyGen[0].publicKey);
      assert MLDSA.sign("", "", "") == #err(#invalidSecretKey);
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
    Test.test(func() {
      checkSaved();
      assert MLDSA.verify(publicKey, v.message, signature, v.context) == #ok(true);
    })
  };
}
