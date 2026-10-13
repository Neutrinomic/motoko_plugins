import Ed "mo:fast/Ed25519";
import Prim "mo:⛔";
import Vectors "Vectors";

module {
  func must<T>(result : Ed.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) { assert false; loop {} } }
  };

  public func prefixBoundaries() {
    for (v in Vectors.signing.values()) {
      let secret = must(Ed.prepareSecretKey(v.seed));
      let publicKey = must(Ed.preparePublicKey(v.publicKey));
      assert Ed.derivePublicKey(v.seed) == #ok(v.publicKey);
      assert Ed.keyPairFromSeed(v.seed) == #ok { secretKey = v.seed; publicKey = v.publicKey };
      assert Ed.sign(v.seed, v.message) == #ok(v.signature);
      assert Ed.signPrepared(secret, v.message) == v.signature;
      assert Ed.verify(v.publicKey, v.message, v.signature) == #ok true;
      assert Ed.verifyPrepared(publicKey, v.message, v.signature) == #ok true;
      let changed = Prim.blobToArray(v.message);
      let wrong = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(changed.size(), func(i) {
        if (i + 1 == changed.size()) changed[i] ^ 1 else changed[i]
      }));
      assert Ed.verify(v.publicKey, wrong, v.signature) == #ok false;
      assert Ed.verifyPrepared(publicKey, wrong, v.signature) == #ok false;
      // Invalid intervening calls must not replace retained expanded state.
      switch (Ed.prepareSecretKey("")) {
        case (#err(#invalidSecretKey)) {};
        case (_) assert false;
      };
      assert Ed.verifyPrepared(publicKey, v.message, "") == #err(#invalidSignature);
      assert Ed.signPrepared(secret, v.message) == v.signature;
    }
  };

  public func mixedOrderAndDomains() {
    let unrelated = must(Ed.preparePublicKey(Vectors.signing[0].publicKey));
    for (v in Vectors.verification.values()) {
      assert Ed.validatePublicKey(v.publicKey) == #ok true;
      let prepared = must(Ed.preparePublicKey(v.publicKey));
      assert Ed.verify(v.publicKey, v.message, v.signature) == #ok(v.expected);
      assert Ed.verifyPrepared(prepared, v.message, v.signature) == #ok(v.expected);
      assert Ed.verifyPrepared(unrelated, v.message, v.signature) == #ok false;
      assert Ed.verifyPrepared(prepared, v.message, v.signature) == #ok(v.expected);
    }
  };
}
