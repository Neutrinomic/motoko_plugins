import Test "mo:test";
import RSA "mo:fast/RSA";
import F "../fixtures/RSA";
import Prim "mo:⛔";

persistent actor {
  func unwrap<T>(result : RSA.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected RSA error") }
  };
  func expectError<T>(result : RSA.Result<T>, expected : RSA.Error) {
    switch result { case (#err error) assert error == expected; case (#ok _) assert false }
  };

  public func test_public_preparation_and_verification() : async Test.Metrics {
    Test.test(func() {
      let key : RSA.PreparedPublicKey = unwrap(RSA.preparePublicKey(F.publicKey));
      assert RSA.verifyPrepared(key, F.message, F.signature) == #ok true;
      assert RSA.verifyPrehashPrepared(key, F.digest, F.signature) == #ok true;
      assert RSA.verifyPrepared(key, "wrong", F.signature) == #ok false;
      assert RSA.verifyPrehashPrepared(key, F.flip(F.digest, 0, 1), F.signature) == #ok false;
      assert RSA.verifyPrehashPrepared(key, F.digest, F.zeros(384)) == #ok false;
      assert RSA.verifyPrepared(key, F.message, F.signature) == RSA.verify(F.publicKey, F.message, F.signature);
      assert RSA.verifyPrehashPrepared(key, F.digest, F.signature) == RSA.verifyPrehash(F.publicKey, F.digest, F.signature);
    })
  };

  public func test_secret_preparation_and_exact_prehash_signature() : async Test.Metrics {
    Test.test(func() {
      let key : RSA.PreparedSecretKey = unwrap(RSA.prepareSecretKey(F.privateKey));
      let signature = unwrap(RSA.signPrehashPrepared(key, F.digest, F.salt));
      assert signature == F.signature;
      let publicKey = unwrap(RSA.preparePublicKey(F.publicKey));
      assert RSA.verifyPrehashPrepared(publicKey, F.digest, signature) == #ok true;
      assert RSA.verifyPrehash(F.publicKey, F.digest, signature) == #ok true;
    })
  };

  public func test_exact_message_signature_and_changed_salt() : async Test.Metrics {
    Test.test(func() {
      let key = unwrap(RSA.prepareSecretKey(F.privateKey));
      assert RSA.signPrepared(key, F.message, F.salt) == #ok(F.signature);
      let changed = unwrap(RSA.signPrehashPrepared(key, F.digest, F.flip(F.salt, 0, 1)));
      assert changed != F.signature;
      assert RSA.verify(F.publicKey, F.message, changed) == #ok true;
    })
  };

  public func test_factory_rejections() : async Test.Metrics {
    Test.test(func() {
      for (key in (["", F.prefix(F.publicKey, 383), F.append(F.publicKey, 0), F.zeros(384), F.flip(F.publicKey, 0, 128), F.flip(F.publicKey, 383, 1)] : [Blob]).values()) {
        expectError(RSA.preparePublicKey(key), #invalidPublicKey);
      };
      for (key in (["", F.prefix(F.privateKey, 959), F.append(F.privateKey, 0), F.zeros(960)] : [Blob]).values()) {
        expectError(RSA.prepareSecretKey(key), #invalidSecretKey);
      };
      for (offset in [191, 383, 575, 767, 959, 0, 192].values()) {
        let mask : Nat8 = if (offset == 0 or offset == 192) 128 else 1;
        expectError(RSA.prepareSecretKey(F.flip(F.privateKey, offset, mask)), #invalidSecretKey);
      };
      let key = unwrap(RSA.preparePublicKey(F.publicKey));
      assert RSA.verifyPrepared(key, F.message, F.signature) == #ok true;
    })
  };

  public func test_hot_operation_errors() : async Test.Metrics {
    Test.test(func() {
      let publicKey = unwrap(RSA.preparePublicKey(F.publicKey));
      let secretKey = unwrap(RSA.prepareSecretKey(F.privateKey));
      for (digest in (["", F.prefix(F.digest, 31), F.append(F.digest, 0)] : [Blob]).values()) {
        assert RSA.verifyPrehashPrepared(publicKey, digest, "") == #err(#invalidDigest);
        assert RSA.signPrehashPrepared(secretKey, digest, "") == #err(#invalidDigest);
      };
      for (salt in (["", F.prefix(F.salt, 31), F.append(F.salt, 0)] : [Blob]).values()) {
        assert RSA.signPrepared(secretKey, F.message, salt) == #err(#invalidSalt);
        assert RSA.signPrehashPrepared(secretKey, F.digest, salt) == #err(#invalidSalt);
      };
      for (signature in (["", F.prefix(F.signature, 383), F.append(F.signature, 0), F.publicKey] : [Blob]).values()) {
        assert RSA.verifyPrepared(publicKey, F.message, signature) == #err(#invalidSignature);
        assert RSA.verifyPrehashPrepared(publicKey, F.digest, signature) == #err(#invalidSignature);
      };
      assert RSA.verifyPrepared(publicKey, F.message, F.signature) == #ok true;
    })
  };

  public func test_aliases_and_evaluation_order() : async Test.Metrics {
    Test.test(func() {
      let prepare = RSA.preparePublicKey;
      let key = unwrap(prepare(F.publicKey));
      func verify(key : RSA.PreparedPublicKey, digest : Blob, signature : Blob) : RSA.Result<Bool> {
        RSA.verifyPrehashPrepared(key, digest, signature)
      };
      let callbacks : [(RSA.PreparedPublicKey, Blob, Blob) -> RSA.Result<Bool>] = [verify];
      assert callbacks[0](key, F.digest, F.signature) == #ok true;
      var order = "";
      let result = (do { order #= "callee;"; RSA.verifyPrehashPrepared })(
        do { order #= "key;"; key },
        do { order #= "digest;"; F.digest },
        do { order #= "signature;"; F.signature }
      );
      assert order == "callee;key;digest;signature;" and result == #ok true;
      let aliases : [RSA.PreparedPublicKey] = [key, unwrap(RSA.preparePublicKey(F.publicKey))];
      for (alias in aliases.values()) assert RSA.verifyPrepared(alias, F.message, F.signature) == #ok true;
    })
  };

  // Prepared contexts cannot be stable actor fields. This transient field
  // remains GC-managed between messages but is rebuilt after an upgrade.
  transient var retained : ?{ publicKey : RSA.PreparedPublicKey; secretKey : RSA.PreparedSecretKey } = null;
  transient var released : ?{ publicKey : RSA.PreparedPublicKey; secretKey : RSA.PreparedSecretKey } = null;

  public func test_drop_contexts_collect_and_prepare_again() : async Test.Metrics {
    released := null;
    // No prepared handle escapes this async frame except through released.
    // Returning unit lets the frame holding its local roots finish first.
    await async {
      let publicKey = unwrap(RSA.preparePublicKey(F.publicKey));
      let secretKey = unwrap(RSA.prepareSecretKey(F.privateKey));
      released := ?{ publicKey; secretKey };
      assert RSA.signPrehashPrepared(secretKey, F.digest, F.salt) == #ok(F.signature);
      assert RSA.verifyPrehashPrepared(publicKey, F.digest, F.signature) == #ok true;
    };
    switch released {
      case (?saved) assert RSA.verifyPrehashPrepared(saved.publicKey, F.digest, F.signature) == #ok true;
      case null assert false;
    };
    released := null;
    await async {};
    let reclaimedBefore = Prim.rts_reclaimed();
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
    while (settle < 4) {
      await async {};
      settle += 1;
    };
    assert Prim.rts_reclaimed() > reclaimedBefore + 4 * 1024 * 1024;
    // This confirms GC activity after dropping roots, not reclamation or
    // zeroization of particular context bytes. Fresh contexts must work
    // independently of any discarded native arithmetic state.
    let publicKey = unwrap(RSA.preparePublicKey(F.publicKey));
    let secretKey = unwrap(RSA.prepareSecretKey(F.privateKey));
    assert RSA.signPrehashPrepared(secretKey, F.digest, F.salt) == #ok(F.signature);
    Test.test(func() {
      assert RSA.verifyPrepared(publicKey, F.message, F.signature) == #ok true;
      assert RSA.verifyPrehashPrepared(publicKey, F.digest, F.signature) == #ok true;
    })
  };

  public func test_prepared_handles_survive_real_collection() : async Test.Metrics {
    ignore Prim.Array_init<Nat>(131_072, 0);
    let rawPublicKey = Prim.arrayToBlob(Prim.blobToArray(F.publicKey));
    let rawPrivateKey = Prim.arrayToBlob(Prim.blobToArray(F.privateKey));
    let publicKey = unwrap(RSA.preparePublicKey(rawPublicKey));
    let secretKey = unwrap(RSA.prepareSecretKey(rawPrivateKey));
    retained := ?{ publicKey; secretKey };
    let publicAliases : [RSA.PreparedPublicKey] = [publicKey, publicKey];
    let secretAliases : [RSA.PreparedSecretKey] = [secretKey, secretKey];
    let signature = unwrap(RSA.signPrehashPrepared(secretKey, F.digest, F.salt));
    assert signature == F.signature;
    func check() {
      assert rawPublicKey == F.publicKey and rawPrivateKey == F.privateKey;
      assert signature == F.signature;
      for (key in publicAliases.values()) assert RSA.verifyPrehashPrepared(key, F.digest, signature) == #ok true;
      // Check both private handle aliases on cheap prehash-error paths while
      // retaining an exact successful signing check until after collection.
      for (key in secretAliases.values()) assert RSA.signPrehashPrepared(key, "", "") == #err(#invalidDigest);
      switch retained {
        case (?saved) assert RSA.verifyPrepared(saved.publicKey, F.message, signature) == #ok true;
        case null assert false;
      };
    };
    check();
    let reclaimedBefore = Prim.rts_reclaimed();
    let heapBefore = Prim.rts_heap_size();
    var peakHeap = heapBefore;
    var round = 0;
    while (round < 9) {
      // Later contexts must not overwrite either previously prepared key.
      let later = unwrap(RSA.preparePublicKey(F.publicKey));
      assert RSA.verifyPrepared(later, F.message, F.signature) == #ok true;
      expectError(RSA.prepareSecretKey(""), #invalidSecretKey);
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
    switch retained {
      case (?saved) {
        assert RSA.signPrehashPrepared(saved.secretKey, F.digest, F.salt) == #ok(F.signature);
        assert RSA.verifyPrehashPrepared(saved.publicKey, F.digest, F.signature) == #ok true;
      };
      case null assert false;
    };
    Test.test(check)
  };
}
