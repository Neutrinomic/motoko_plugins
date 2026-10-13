import MLDSA "mo:fast/MLDSA";
import Prim "mo:⛔";
import Vectors "../../../../plugins/ml-dsa/tests/Vectors";

module {
  public func ok<T>(r : MLDSA.Result<T>) : T {
    switch r { case (#ok x) x; case (#err _) Prim.trap("prepared MLDSA audit: unexpected error") }
  };
  public func fill(n : Nat, b : Nat8) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(n, func(_) { b }))
  };
  public func copy(b : Blob) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(b.size(), func(i) { b[i] }))
  };
  func error<T>(r : MLDSA.Result<T>, expected : MLDSA.Error) {
    switch r { case (#err actual) assert actual == expected; case (#ok _) assert false }
  };
  func changed(b : Blob, at : Nat, value : Nat8) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(b.size(), func(i) { if (i == at) value else b[i] }))
  };

  public func officialParity() {
    for (v in Vectors.sigGen.values()) {
      let publicKey = ok(MLDSA.preparePublicKey(v.publicKey));
      let secretKey = ok(MLDSA.prepareSecretKey(v.seed));
      assert MLDSA.signRandomizedPrepared(secretKey, v.message, v.context, v.randomness) == #ok(v.signature);
      if (v.deterministic) assert MLDSA.signPrepared(secretKey, v.message, v.context) == #ok(v.signature);
      assert MLDSA.verifyPrepared(publicKey, v.message, v.signature, v.context) == #ok(true);
      // Direct and prepared paths agree on the exact external FIPS bytes.
      assert MLDSA.signRandomized(v.seed, v.message, v.context, v.randomness) == #ok(v.signature);
    };
    for (v in Vectors.sigVer.values()) {
      let publicKey = ok(MLDSA.preparePublicKey(v.publicKey));
      assert MLDSA.verifyPrepared(publicKey, v.message, v.signature, v.context) == #ok(v.valid);
    };
  };

  public func errorsAndMutation() {
    let v = Vectors.sigGen[0];
    for (n in ([0, 31, 33, 2560] : [Nat]).values()) error(MLDSA.prepareSecretKey(fill(n, 0)), #invalidSecretKey);
    for (n in ([0, 1311, 1313] : [Nat]).values()) error(MLDSA.preparePublicKey(fill(n, 0)), #invalidPublicKey);
    let pk = ok(MLDSA.preparePublicKey(v.publicKey));
    let sk = ok(MLDSA.prepareSecretKey(v.seed));
    for (n in ([0, 2419, 2421] : [Nat]).values())
      assert MLDSA.verifyPrepared(pk, "", fill(n, 0), fill(256, 0)) == #err(#invalidSignature);
    assert MLDSA.verifyPrepared(pk, "", v.signature, fill(256, 0)) == #err(#invalidContext);
    assert MLDSA.signPrepared(sk, "", fill(256, 0)) == #err(#invalidContext);
    assert MLDSA.signRandomizedPrepared(sk, "", fill(256, 0), "") == #err(#invalidContext);
    for (n in ([0, 31, 33] : [Nat]).values())
      assert MLDSA.signRandomizedPrepared(sk, "", "", fill(n, 0)) == #err(#invalidRandomness);
    let ctx = fill(255, 0);
    let signature = ok(MLDSA.signPrepared(sk, "", ctx));
    assert MLDSA.sign(v.seed, "", ctx) == #ok(signature);
    assert MLDSA.signRandomizedPrepared(sk, "", ctx, fill(32, 0)) == #ok(signature);
    assert MLDSA.verifyPrepared(pk, "", signature, ctx) == #ok(true);
    assert MLDSA.verifyPrepared(pk, "", signature, changed(ctx, 254, 1)) == #ok(false);
    let randomized = ok(MLDSA.signRandomizedPrepared(sk, "", ctx, fill(32, 255)));
    assert MLDSA.signRandomized(v.seed, "", ctx, fill(32, 255)) == #ok(randomized);
    assert randomized != signature;
    assert MLDSA.verifyPrepared(pk, "", randomized, ctx) == #ok(true);

    // Each syntactically valid public-key byte string is accepted by factory.
    for (b in ([0, 255] : [Nat8]).values()) {
      let arbitrary = ok(MLDSA.preparePublicKey(fill(1312, b)));
      assert MLDSA.verifyPrepared(arbitrary, v.message, v.signature, v.context) == #ok(false);
      let seed = fill(32, b);
      let publicBytes = ok(MLDSA.publicKey(seed));
      let preparedSecret = ok(MLDSA.prepareSecretKey(seed));
      assert MLDSA.signPrepared(preparedSecret, "", "") == MLDSA.sign(seed, "", "");
      assert MLDSA.verifyPrepared(ok(MLDSA.preparePublicKey(publicBytes)), "", ok(MLDSA.signPrepared(preparedSecret, "", "")), "") == #ok(true);
    };
    // Exact challenge/z/hint corruption comparisons against independent reference.
    let clean = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(2420, func(i) { if (i >= 2336) 0 else v.signature[i] }));
    let two = changed(changed(changed(changed(clean, 2416, 2), 2417, 2), 2418, 2), 2419, 2);
    let bad : [Blob] = [
      changed(v.signature, 0, v.signature[0] ^ 1),
      changed(changed(changed(v.signature, 32, 0), 33, 0), 34, v.signature[34] & 252),
      changed(clean, 2416, 81),
      changed(clean, 2416, 1),
      changed(changed(two, 2336, 3), 2337, 3),
      changed(changed(two, 2336, 3), 2337, 2),
      changed(clean, 2415, 1)
    ];
    for (s in bad.values()) {
      assert MLDSA.verifyPrepared(pk, v.message, s, v.context) == #ok(false);
      assert MLDSA.verify(v.publicKey, v.message, s, v.context) == #ok(false);
    };
    assert MLDSA.verifyPrepared(pk, changed(v.message, 0, v.message[0] ^ 1), v.signature, v.context) == #ok(false);
  };

  public func interleavedKeys() {
    let a = Vectors.sigGen[0];
    let b = Vectors.sigGen[1];
    let publicKeys = [ok(MLDSA.preparePublicKey(copy(a.publicKey))), ok(MLDSA.preparePublicKey(copy(b.publicKey)))];
    let secretKeys = [ok(MLDSA.prepareSecretKey(copy(a.seed))), ok(MLDSA.prepareSecretKey(copy(b.seed)))];
    let verify : (MLDSA.PreparedPublicKey, Blob, Blob, Blob) -> MLDSA.Result<Bool> = func(pk, msg, sig, ctx) {
      MLDSA.verifyPrepared(pk, msg, sig, ctx)
    };
    let callbacks = [verify];
    for (_ in ([0, 1, 2] : [Nat]).values()) {
      assert MLDSA.signRandomizedPrepared(secretKeys[1], b.message, b.context, b.randomness) == #ok(b.signature);
      assert MLDSA.signRandomizedPrepared(secretKeys[0], a.message, a.context, a.randomness) == #ok(a.signature);
      assert callbacks[0](publicKeys[1], b.message, b.signature, b.context) == #ok(true);
      assert callbacks[0](publicKeys[0], a.message, a.signature, a.context) == #ok(true);
      assert callbacks[0](publicKeys[0], b.message, b.signature, b.context) == #ok(false);
      assert callbacks[0](publicKeys[1], a.message, a.signature, a.context) == #ok(false);
    };
    var order : Nat = 0;
    func key() : MLDSA.PreparedPublicKey { assert order == 0; order += 1; publicKeys[0] };
    func argument(n : Nat, value : Blob) : Blob { assert order == n; order += 1; value };
    let inferred = MLDSA.verifyPrepared;
    assert inferred(key(), argument(1, a.message), argument(2, a.signature), argument(3, a.context)) == #ok(true);
    assert order == 4;
  };
}
