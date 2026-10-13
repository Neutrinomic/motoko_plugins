// Independent boundary/malleability checks. Known answers come from NIST ACVP,
// not from signing with the implementation under test.
import MLDSA "mo:fast/MLDSA";
import Prim "mo:⛔";
import Vectors "../../../../plugins/ml-dsa/tests/Vectors";

module {
  public func ok<T>(r : MLDSA.Result<T>) : T {
    switch r { case (#ok x) x; case (#err _) Prim.trap("ML-DSA audit: unexpected error") }
  };
  public func fill(n : Nat, b : Nat8) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(n, func(_) { b }))
  };
  public func copy(b : Blob) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(b.size(), func(i) { b[i] }))
  };
  func change(b : Blob, at : Nat, value : Nat8) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(b.size(), func(i) { if (i == at) value else b[i] }))
  };
  func changed(b : Blob) : Blob { change(b, 0, b[0] ^ 1) };

  public func knownAnswers() {
    for (v in Vectors.keyGen.values()) assert MLDSA.publicKey(v.seed) == #ok(v.publicKey);
    for (v in Vectors.sigGen.values()) {
      assert MLDSA.publicKey(v.seed) == #ok(v.publicKey);
      assert MLDSA.signRandomized(v.seed, v.message, v.context, v.randomness) == #ok(v.signature);
      if (v.deterministic) assert MLDSA.sign(v.seed, v.message, v.context) == #ok(v.signature);
      assert MLDSA.verify(v.publicKey, v.message, v.signature, v.context) == #ok(true);
    };
    for (v in Vectors.sigVer.values())
      assert MLDSA.verify(v.publicKey, v.message, v.signature, v.context) == #ok(v.valid);
  };

  public func boundaries() {
    let v = Vectors.sigGen[0];
    for (n in ([0, 1, 31, 33, 2560] : [Nat]).values()) {
      let seed = fill(n, 0);
      assert MLDSA.publicKey(seed) == #err(#invalidSecretKey);
      assert MLDSA.sign(seed, "", "") == #err(#invalidSecretKey);
      assert MLDSA.signRandomized(seed, "", fill(256, 0), "") == #err(#invalidSecretKey);
    };
    for (n in ([0, 1311, 1313] : [Nat]).values())
      assert MLDSA.verify(fill(n, 0), "", "", fill(256, 0)) == #err(#invalidPublicKey);
    for (n in ([0, 2419, 2421] : [Nat]).values())
      assert MLDSA.verify(v.publicKey, "", fill(n, 0), fill(256, 0)) == #err(#invalidSignature);
    assert MLDSA.verify(v.publicKey, v.message, v.signature, fill(256, 0)) == #err(#invalidContext);
    assert MLDSA.sign(v.seed, "", fill(256, 0)) == #err(#invalidContext);
    assert MLDSA.signRandomized(v.seed, "", fill(256, 0), "") == #err(#invalidContext);
    for (n in ([0, 31, 33] : [Nat]).values())
      assert MLDSA.signRandomized(v.seed, "", "", fill(n, 0)) == #err(#invalidRandomness);

    // 255 is valid, and a changed byte (including NUL bytes) changes the domain.
    let ctx = fill(255, 0);
    let signature = ok(MLDSA.sign(v.seed, "", ctx));
    assert MLDSA.verify(v.publicKey, "", signature, ctx) == #ok(true);
    assert MLDSA.verify(v.publicKey, "", signature, change(ctx, 254, 1)) == #ok(false);
    assert MLDSA.verify(v.publicKey, "", signature, "") == #ok(false);
    assert MLDSA.signRandomized(v.seed, "", ctx, fill(32, 0)) == #ok(signature);
    let randomized = ok(MLDSA.signRandomized(v.seed, "", ctx, fill(32, 255)));
    assert randomized != signature;
    assert MLDSA.verify(v.publicKey, "", randomized, ctx) == #ok(true);
    // All 32-byte strings are valid seeds; there is no scalar-range restriction.
    for (byte in ([0, 255] : [Nat8]).values()) {
      let seed = fill(32, byte);
      let publicKey = ok(MLDSA.publicKey(seed));
      let signed = ok(MLDSA.sign(seed, "\00\ff", "\00\01"));
      assert publicKey.size() == 1312 and signed.size() == 2420;
      assert MLDSA.verify(publicKey, "\00\ff", signed, "\00\01") == #ok(true);
    };
  };

  public func malformed() {
    let v = Vectors.sigGen[0];
    assert MLDSA.verify(changed(v.publicKey), v.message, v.signature, v.context) == #ok(false);
    assert MLDSA.verify(v.publicKey, changed(v.message), v.signature, v.context) == #ok(false);
    assert MLDSA.verify(v.publicKey, v.message, changed(v.signature), v.context) == #ok(false);
    // rho || packed-t1 has no unused bits; every length-correct key decodes.
    assert MLDSA.verify(fill(1312, 255), v.message, v.signature, v.context) == #ok(false);
    assert MLDSA.verify(fill(1312, 0), v.message, v.signature, v.context) == #ok(false);
    assert MLDSA.verify(v.publicKey, v.message, fill(2420, 0), v.context) == #ok(false);

    // ML-DSA-44 hint encoding: 80 index bytes then 4 cumulative endpoints.
    // Enforce endpoint bounds, monotonic endpoints, strictly increasing indices,
    // and zero unused index padding (FIPS 204 HintBitUnpack, Algorithm 21).
    let clean = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(2420, func(i) {
      if (i >= 2336) 0 else v.signature[i]
    }));
    let tooMany = change(change(change(change(clean, 2416, 81), 2417, 81), 2418, 81), 2419, 81);
    let decreasing = change(clean, 2416, 1);
    let two = change(change(change(change(clean, 2416, 2), 2417, 2), 2418, 2), 2419, 2);
    let duplicate = change(change(two, 2336, 3), 2337, 3);
    let unsorted = change(change(two, 2336, 3), 2337, 2);
    let dirtyPadding = change(clean, 2415, 1);
    // First packed z coefficient=0 decodes to gamma1, violating strict norm.
    let oversizedZ = change(change(change(v.signature, 32, 0), 33, 0), 34, v.signature[34] & 252);
    for (signature in [tooMany, decreasing, duplicate, unsorted, dirtyPadding, oversizedZ].values())
      assert MLDSA.verify(v.publicKey, v.message, signature, v.context) == #ok(false);
  };

  public func callsAndRetainedOutputs() {
    let v = Vectors.sigGen[0];
    var order : Nat = 0;
    func arg(expected : Nat, b : Blob) : Blob { assert order == expected; order += 1; b };
    let verify = MLDSA.verify;
    assert verify(arg(0, v.publicKey), arg(1, v.message), arg(2, v.signature), arg(3, v.context)) == #ok(true);
    assert order == 4;
    let callbacks : [(Blob, Blob, Blob, Blob) -> MLDSA.Result<Bool>] = [
      func(pk, msg, sig, ctx) { MLDSA.verify(pk, msg, sig, ctx) }
    ];
    assert callbacks[0](v.publicKey, v.message, v.signature, v.context) == #ok(true);
    let sign = MLDSA.signRandomized;
    let signatures = [sign(v.seed, v.message, v.context, v.randomness), sign(v.seed, v.message, v.context, fill(32, 255))];
    for (_ in ([0, 1, 2] : [Nat]).values()) {
      ignore Prim.Array_init<Nat>(4096, 9);
      assert MLDSA.publicKey(copy(v.seed)) == #ok(v.publicKey);
      ignore MLDSA.sign("", "", "");
    };
    assert signatures[0] == #ok(v.signature);
    assert MLDSA.verify(v.publicKey, v.message, ok(signatures[1]), v.context) == #ok(true);
  };
}
