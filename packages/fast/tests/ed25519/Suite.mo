import Ed25519 "mo:fast/Ed25519";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Vectors "Vectors";

module {
  public func vectors(from : Nat, end : Nat) {
    var index = from;
    while (index < end) {
      let v = Vectors.vectors[index];
      assert Ed25519.derivePublicKey(v.seed) == #ok (v.publicKey);
      assert Ed25519.validatePublicKey(v.publicKey) == #ok true;
      assert Ed25519.sign(v.seed, v.message) == #ok (v.signature);
      assert Ed25519.verify(v.publicKey, v.message, v.signature) == #ok true;
      assert Ed25519.verify(v.publicKey, concat(v.message, "\00"), v.signature) == #ok false;
      index += 1;
    }
  };
  public func concat(a : Blob, b : Blob) : Blob { Blob.fromArray(a.toArray().concat(b.toArray())) };
  public func fill(n : Nat, byte : Nat8) : Blob { Blob.fromArray(Array.repeat<Nat8>(byte, n)) };
  public func malformed() {
    let v = Vectors.vectors[0];
    for (n in [0, 1, 31, 33, 64].values()) {
      let bad = fill(n, 0);
      assert Ed25519.derivePublicKey(bad) == #err(#invalidSecretKey);
      assert Ed25519.keyPairFromSeed(bad) == #err(#invalidSecretKey);
      assert Ed25519.sign(bad, v.message) == #err(#invalidSecretKey);
      assert Ed25519.verify(v.publicKey, v.message, bad) == #err(#invalidSignature);
    };
    for (seed in [fill(32, 0), fill(32, 255)].values()) {
      switch (Ed25519.keyPairFromSeed(seed)) {
        case (#err _) assert false;
        case (#ok pair) {
          assert pair.secretKey == seed;
          assert Ed25519.derivePublicKey(pair.secretKey) == #ok (pair.publicKey);
          switch (Ed25519.sign(pair.secretKey, "seed boundary")) {
            case (#err _) assert false;
            case (#ok signature) assert Ed25519.verify(pair.publicKey, "seed boundary", signature) == #ok true;
          }
        }
      }
    };
    assert Ed25519.verify("", "", "") == #err(#invalidPublicKey);
    assert Ed25519.verify(v.publicKey, "", "") == #err(#invalidSignature);
    assert Ed25519.sign(v.seed, v.message) == #ok (v.signature);
  };
  public func strictPointsAndScalars() {
    let v = Vectors.vectors[0];
    let scalar = Blob.fromArray(v.signature.toArray().sliceToArray(32, 64));
    let r = Blob.fromArray(v.signature.toArray().sliceToArray(0, 32));
    let invalidPoints : [Blob] = [
      "", "\01", fill(31, 0), fill(33, 0), fill(32, 0),
      concat("\01", fill(31, 0)), // identity
      concat(concat("\01", fill(30, 0)), "\80"), // negative zero x
      concat(concat("\ec", fill(30, 255)), "\7f"), // order two
      concat(concat("\ed", fill(30, 255)), "\7f"), // y = p
      concat(concat("\ee", fill(30, 255)), "\7f"), // y = p+1
      fill(32, 255),
    ];
    for (key in invalidPoints.values()) {
      assert Ed25519.validatePublicKey(key) == #err(#invalidPublicKey);
      assert Ed25519.verify(key, v.message, v.signature) == #err(#invalidPublicKey);
      assert Ed25519.verify(v.publicKey, v.message, concat(key, scalar)) == #err(#invalidSignature);
    };
    let order : Blob = "\ed\d3\f5\5c\1a\63\12\58\d6\9c\f7\a2\de\f9\de\14\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\10";
    assert Ed25519.verify(v.publicKey, v.message, concat(r, order)) == #err(#invalidSignature);
    assert Ed25519.verify(v.publicKey, v.message, concat(r, fill(32, 255))) == #err(#invalidSignature);
    assert Ed25519.verify(v.publicKey, v.message, concat(r, fill(32, 0))) == #ok false;
    assert Ed25519.verify(v.publicKey, v.message, v.signature) == #ok true;
  };
  public func aliasesAndImmutability() {
    let v = Vectors.vectors[1];
    let seed = Blob.fromArray(v.seed.toArray());
    let key = Blob.fromArray(v.publicKey.toArray());
    let message = Blob.fromArray(v.message.toArray());
    let signature = Blob.fromArray(v.signature.toArray());
    let derive = Ed25519.derivePublicKey;
    assert derive(seed) == #ok key;
    func wrapped(seed : Blob, message : Blob) : Ed25519.Result<Blob> { Ed25519.sign(seed, message) };
    let callbacks = [wrapped];
    assert callbacks[0](seed, message) == #ok signature;
    let saved = Ed25519.sign(seed, message);
    assert Ed25519.verify(key, message, signature) == #ok true;
    ignore Ed25519.sign(Vectors.vectors[2].seed, "other message");
    assert Ed25519.verify(key, message, "") == #err(#invalidSignature);
    assert saved == #ok signature;
    assert seed == v.seed and key == v.publicKey and message == v.message and signature == v.signature;
    // Pure Ed25519 over these 64 digest bytes is NOT Ed25519ph.
    let digestVector = Vectors.vectors[4];
    assert Ed25519.sign(digestVector.seed, digestVector.message) == #ok (digestVector.signature);
    assert Ed25519.verify(digestVector.publicKey, "abc", digestVector.signature) == #ok false;
  };
}
