import Ed25519 "mo:fast/Ed25519";
import Blob "mo:core/Blob";
import Prim "mo:⛔";
import Suite "Suite";
import Vectors "Vectors";

module {
  public func must<T>(result : Ed25519.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected Ed25519 error") }
  };
  public func vectors(from : Nat, end : Nat) {
    var index = from;
    while (index < end) {
      let v = Vectors.vectors[index];
      let secret = must(Ed25519.prepareSecretKey(v.seed));
      let publicKey = must(Ed25519.preparePublicKey(v.publicKey));
      assert Ed25519.signPrepared(secret, v.message) == v.signature;
      assert Ed25519.verifyPrepared(publicKey, v.message, v.signature) == #ok true;
      assert Ed25519.verifyPrepared(publicKey, Suite.concat(v.message, "\00"), v.signature) == #ok false;
      assert Ed25519.verifyPrepared(publicKey, v.message, "") == #err(#invalidSignature);
      assert Ed25519.signPrepared(secret, v.message) == v.signature;
      index += 1;
    }
  };
  public func malformed() {
    for (n in [0, 1, 31, 33, 64, 96, 1056].values()) {
      switch (Ed25519.prepareSecretKey(Suite.fill(n, 0))) {
        case (#err(#invalidSecretKey)) {};
        case _ Prim.trap("invalid seed accepted");
      };
      switch (Ed25519.preparePublicKey(Suite.fill(n, 0))) {
        case (#err(#invalidPublicKey)) {};
        case _ Prim.trap("invalid key accepted");
      };
    };
    for (key in [Suite.fill(32, 0), Suite.concat("\01", Suite.fill(31, 0)), Suite.fill(32, 255)].values()) {
      switch (Ed25519.preparePublicKey(key)) {
        case (#err(#invalidPublicKey)) {};
        case _ Prim.trap("noncanonical or small-order key accepted");
      }
    };
    for (seed in [Suite.fill(32, 0), Suite.fill(32, 255)].values()) {
      let key = must(Ed25519.derivePublicKey(seed));
      let prepared = must(Ed25519.prepareSecretKey(seed));
      let publicKey = must(Ed25519.preparePublicKey(key));
      let sig = Ed25519.signPrepared(prepared, "boundary seed");
      assert Ed25519.sign(seed, "boundary seed") == #ok sig;
      assert Ed25519.verifyPrepared(publicKey, "boundary seed", sig) == #ok true;
    };
    vectors(0, 1);
  };
  public func aliasesAndImmutability() {
    let v = Vectors.vectors[1];
    let seed = Blob.fromArray(v.seed.toArray());
    let key = Blob.fromArray(v.publicKey.toArray());
    let message = Blob.fromArray(v.message.toArray());
    let signature = Blob.fromArray(v.signature.toArray());
    let prepare = Ed25519.prepareSecretKey;
    let secret = must(prepare(seed));
    let publicKey = must(Ed25519.preparePublicKey(key));
    let records = [{ secret; publicKey }, { secret; publicKey }];
    let sign = Ed25519.signPrepared;
    func wrapped(key : Ed25519.PreparedSecretKey, message : Blob) : Blob { sign(key, message) };
    let verify = Ed25519.verifyPrepared;
    let calls = [wrapped];
    assert calls[0](records[1].secret, message) == signature;
    assert verify(records[0].publicKey, message, signature) == #ok true;
    ignore Ed25519.signPrepared(must(prepare(Vectors.vectors[2].seed)), "another key");
    assert verify(publicKey, message, "") == #err(#invalidSignature);
    assert sign(secret, message) == signature;
    assert verify(publicKey, message, signature) == #ok true;
    assert seed == v.seed and key == v.publicKey and message == v.message and signature == v.signature;
  };
}
