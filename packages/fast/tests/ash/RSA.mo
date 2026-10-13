import Test "mo:test";
import RSA "mo:fast/RSA";
import F "../fixtures/RSA";
import Prim "mo:⛔";

// Public fixture keys and signatures originate in Node.js/OpenSSL.
persistent actor {
  func unwrap<T>(result : RSA.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected RSA error") }
  };

  public func test_public_key_and_validators() : async Test.Metrics {
    Test.test(func() {
      assert F.privateKey.size() == 960 and F.publicKey.size() == 384;
      assert RSA.publicKey(F.privateKey) == #ok(F.publicKey);
      assert RSA.derivePublicKey(F.privateKey) == #ok(F.publicKey);
      assert RSA.validatePrivateKey(F.privateKey) == #ok true;
      assert RSA.validatePublicKey(F.publicKey) == #ok true;
      for (key in (["", F.prefix(F.privateKey, 959), F.append(F.privateKey, 0), F.zeros(960)] : [Blob]).values()) {
        assert RSA.validatePrivateKey(key) == #err(#invalidSecretKey);
        assert RSA.publicKey(key) == #err(#invalidSecretKey);
      };
      for (key in (["", F.prefix(F.publicKey, 383), F.append(F.publicKey, 0), F.zeros(384), F.flip(F.publicKey, 0, 128), F.flip(F.publicKey, 383, 1)] : [Blob]).values()) {
        assert RSA.validatePublicKey(key) == #err(#invalidPublicKey);
        assert RSA.verify(key, F.message, F.signature) == #err(#invalidPublicKey);
      };
    })
  };

  public func test_exact_openssl_prehash_signature() : async Test.Metrics {
    Test.test(func() {
      let signature = unwrap(RSA.signPrehash(F.privateKey, F.digest, F.salt));
      assert signature.size() == 384 and signature == F.signature;
      assert RSA.verifyPrehash(F.publicKey, F.digest, signature) == #ok true;
      assert RSA.verify(F.publicKey, F.message, signature) == #ok true;
    })
  };

  public func test_exact_openssl_message_signature() : async Test.Metrics {
    Test.test(func() {
      // The message contains a NUL byte, covering length-preserving hashing.
      let signature = unwrap(RSA.sign(F.privateKey, F.message, F.salt));
      assert signature == F.signature;
      assert RSA.verify(F.publicKey, F.message, signature) == #ok true;
      assert RSA.verifyPrehash(F.publicKey, F.digest, signature) == #ok true;
    })
  };

  public func test_mismatches_and_signature_encodings() : async Test.Metrics {
    Test.test(func() {
      assert RSA.verify(F.publicKey, F.append(F.message, 0), F.signature) == #ok false;
      assert RSA.verifyPrehash(F.publicKey, F.flip(F.digest, 0, 1), F.signature) == #ok false;
      assert RSA.verifyPrehash(F.publicKey, F.digest, F.flip(F.signature, 200, 1)) == #ok false;
      assert RSA.verifyPrehash(F.publicKey, F.digest, F.zeros(384)) == #ok false;
      for (signature in (["", F.prefix(F.signature, 383), F.append(F.signature, 0), F.publicKey] : [Blob]).values()) {
        assert RSA.verify(F.publicKey, F.message, signature) == #err(#invalidSignature);
        assert RSA.verifyPrehash(F.publicKey, F.digest, signature) == #err(#invalidSignature);
      };
      assert RSA.verify(F.publicKey, F.message, F.signature) == #ok true;
    })
  };

  public func test_lengths_and_error_precedence() : async Test.Metrics {
    Test.test(func() {
      for (digest in (["", F.prefix(F.digest, 31), F.append(F.digest, 0)] : [Blob]).values()) {
        assert RSA.signPrehash(F.privateKey, digest, F.salt) == #err(#invalidDigest);
        assert RSA.verifyPrehash(F.publicKey, digest, F.signature) == #err(#invalidDigest);
      };
      for (salt in (["", F.prefix(F.salt, 31), F.append(F.salt, 0)] : [Blob]).values()) {
        assert RSA.signPrehash(F.privateKey, F.digest, salt) == #err(#invalidSalt);
        assert RSA.sign(F.privateKey, F.message, salt) == #err(#invalidSalt);
      };
      assert RSA.signPrehash("", "", "") == #err(#invalidSecretKey);
      assert RSA.signPrehash(F.privateKey, "", "") == #err(#invalidDigest);
      assert RSA.signPrehash(F.privateKey, F.digest, "") == #err(#invalidSalt);
      assert RSA.sign("", "", "") == #err(#invalidSecretKey);
      assert RSA.verifyPrehash("", "", "") == #err(#invalidPublicKey);
      assert RSA.verifyPrehash(F.publicKey, "", "") == #err(#invalidDigest);
      assert RSA.verifyPrehash(F.publicKey, F.digest, "") == #err(#invalidSignature);
      assert RSA.verify("", "", "") == #err(#invalidPublicKey);
      assert RSA.verify(F.publicKey, "", "") == #err(#invalidSignature);
    })
  };

  public func test_corrupted_crt_components() : async Test.Metrics {
    Test.test(func() {
      // p and q become even; dP, dQ and qInv each fail their congruence.
      for (offset in [191, 383, 575, 767, 959].values()) {
        let key = F.flip(F.privateKey, offset, 1);
        assert RSA.validatePrivateKey(key) == #err(#invalidSecretKey);
        assert RSA.publicKey(key) == #err(#invalidSecretKey);
        assert RSA.signPrehash(key, F.digest, F.salt) == #err(#invalidSecretKey);
      };
      for (offset in [0, 192].values()) {
        assert RSA.validatePrivateKey(F.flip(F.privateKey, offset, 128)) == #err(#invalidSecretKey);
      };
      assert RSA.validatePrivateKey(F.privateKey) == #ok true;
    })
  };

  public func test_empty_message_and_explicit_salt() : async Test.Metrics {
    Test.test(func() {
      let emptyHash : Blob = "\e3\b0\c4\42\98\fc\1c\14\9a\fb\f4\c8\99\6f\b9\24\27\ae\41\e4\64\9b\93\4c\a4\95\99\1b\78\52\b8\55";
      let emptySignature = unwrap(RSA.sign(F.privateKey, "", F.salt));
      assert RSA.verify(F.publicKey, "", emptySignature) == #ok true;
      assert RSA.verifyPrehash(F.publicKey, emptyHash, emptySignature) == #ok true;
      assert RSA.verify(F.publicKey, F.message, emptySignature) == #ok false;
      let changed = unwrap(RSA.signPrehash(F.privateKey, F.digest, F.flip(F.salt, 0, 1)));
      assert changed != F.signature;
      assert RSA.verifyPrehash(F.publicKey, F.digest, changed) == #ok true;
      assert RSA.verify(F.publicKey, F.message, changed) == #ok true;
    })
  };

  public func test_aliases_and_argument_evaluation() : async Test.Metrics {
    Test.test(func() {
      let derive = RSA.publicKey;
      assert derive(F.privateKey) == #ok(F.publicKey);
      func verify(key : Blob, digest : Blob, signature : Blob) : RSA.Result<Bool> {
        RSA.verifyPrehash(key, digest, signature)
      };
      let callback : (Blob, Blob, Blob) -> RSA.Result<Bool> = verify;
      assert callback(F.publicKey, F.digest, F.signature) == #ok true;
      var order = "";
      let signed = (do { order #= "callee;"; RSA.signPrehash })(
        do { order #= "key;"; F.privateKey },
        do { order #= "digest;"; F.digest },
        do { order #= "salt;"; F.salt }
      );
      assert order == "callee;key;digest;salt;";
      assert signed == #ok(F.signature);
      assert RSA.publicKey("") == #err(#invalidSecretKey);
      assert RSA.publicKey(F.privateKey) == #ok(F.publicKey);
      assert signed == #ok(F.signature);
    })
  };

  var retained : ?{ privateKey : Blob; digest : Blob; salt : Blob; publicKey : Blob; signature : Blob } = null;

  public func test_retained_outputs_across_await_and_forced_gc() : async Test.Metrics {
    // Put movable input copies behind dead heap data rather than borrowing
    // the static fixture Blobs, which cannot demonstrate input relocation.
    ignore Prim.Array_init<Nat>(131_072, 0);
    func clone(value : Blob) : Blob {
      let bytes = Prim.blobToArray(value);
      Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(bytes.size(), func(i) { bytes[i] }))
    };
    let privateKey = clone(F.privateKey);
    let digest = clone(F.digest);
    let salt = clone(F.salt);
    let signature = unwrap(RSA.signPrehash(privateKey, digest, salt));
    let publicKey = unwrap(RSA.publicKey(privateKey));
    retained := ?{ privateKey; digest; salt; publicKey; signature };
    let aliases = [signature, signature, publicKey, privateKey, digest, salt];
    func check() {
      assert signature == F.signature and publicKey == F.publicKey;
      assert privateKey == F.privateKey and digest == F.digest and salt == F.salt;
      assert aliases[0] == F.signature and aliases[1] == F.signature and aliases[2] == F.publicKey;
      assert aliases[3] == F.privateKey and aliases[4] == F.digest and aliases[5] == F.salt;
      switch retained {
        case (?saved) {
          assert saved.publicKey == F.publicKey and saved.signature == F.signature;
          assert saved.privateKey == F.privateKey and saved.digest == F.digest and saved.salt == F.salt;
          assert RSA.verifyPrehash(saved.publicKey, saved.digest, saved.signature) == #ok true;
        };
        case null assert false;
      };
    };
    check();
    let reclaimedBefore = Prim.rts_reclaimed();
    let heapBefore = Prim.rts_heap_size();
    var peakHeap = heapBefore;
    var round = 0;
    while (round < 9) {
      // Crossing the active 64-MiB allocation partition allows collection of
      // the partition containing the retained managed plugin outputs.
      assert RSA.publicKey(F.privateKey) == #ok(F.publicKey);
      assert RSA.publicKey("") == #err(#invalidSecretKey);
      var pressure = 0;
      while (pressure < 8) {
        ignore Prim.Array_init<Nat>(131_072, round + pressure);
        pressure += 1;
      };
      let heap = Prim.rts_heap_size();
      if (heap > peakHeap) peakHeap := heap;
      await async {};
      check();
      round += 1;
    };
    var settle = 0;
    while (settle < 4) {
      await async {};
      check();
      settle += 1;
    };
    assert peakHeap > heapBefore;
    assert Prim.rts_reclaimed() > reclaimedBefore + 4 * 1024 * 1024;
    // Re-enter the private-key runtime after confirmed collection using all
    // three copied inputs fetched from their persistent managed container.
    switch retained {
      case (?saved) assert RSA.signPrehash(saved.privateKey, saved.digest, saved.salt) == #ok(F.signature);
      case null assert false;
    };
    Test.test(check)
  };
}
