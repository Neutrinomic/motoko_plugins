import Test "mo:test";
import Ed25519 "mo:fast/Ed25519";
import RSA "mo:fast/RSA";
import MLDSA "mo:fast/MLDSA";
import Secp256k1 "mo:fast/Secp256k1";
import P256 "mo:fast/P256";
import BLS "mo:fast/BLS12381";
import Map "mo:fast/Map";
import PureMap "mo:fast/pure/Map";
import Prim "mo:⛔";
import V "../fixtures/PreparedComposition";
import F "../fixtures/RSA";

persistent actor {
  // Ordinary application records contain nominal public and secret values.
  // Only the public ID is a map key; no opaque value is compared or serialized.
  type Credentials = {
    edPublic : Ed25519.PreparedPublicKey; edSecret : Ed25519.PreparedSecretKey;
    rsaPublic : RSA.PreparedPublicKey; rsaSecret : RSA.PreparedSecretKey;
    mlPublic : MLDSA.PreparedPublicKey; mlSecret : MLDSA.PreparedSecretKey;
    ecdsaPublic : Secp256k1.PreparedPublicKey;
    schnorrPublic : Secp256k1.PreparedSchnorrPublicKey;
    schnorrSecret : Secp256k1.PreparedSchnorrSecretKey;
    p256Public : P256.PreparedPublicKey;
    blsPublic : BLS.PreparedICPublicKey;
  };
  type Account = { id : Nat; accountName : Text; keys : Credentials; sign : Blob -> Blob };

  func ok<T, E>(result : { #ok : T; #err : E }) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected prepared composition error") }
  };
  func some<T>(value : ?T) : T {
    switch value { case (?item) item; case null Prim.trap("missing prepared composition value") }
  };
  func cmp(a : Nat, b : Nat) : Map.Order {
    if (a < b) #less else if (a == b) #equal else #greater
  };
  func copy(bytes : Blob) : Blob {
    let data = Prim.blobToArray(bytes);
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(data.size(), func(i) { data[i] }))
  };
  func prepare() : Credentials {
    // Dynamic source buffers are temporary. The prepared values own their data.
    {
      edPublic = ok(Ed25519.preparePublicKey(copy(V.edKey)));
      rsaSecret = ok(RSA.prepareSecretKey(copy(F.privateKey)));
      mlPublic = ok(MLDSA.preparePublicKey(copy(V.mlKey)));
      schnorrSecret = ok(Secp256k1.prepareSchnorrSecretKey(copy(V.schnorrSeed)));
      p256Public = ok(P256.preparePublicKey(copy(V.p256Key)));
      edSecret = ok(Ed25519.prepareSecretKey(copy(V.edSeed)));
      blsPublic = ok(BLS.prepareICPublicKey(copy(V.icKey0)));
      rsaPublic = ok(RSA.preparePublicKey(copy(F.publicKey)));
      schnorrPublic = ok(Secp256k1.prepareSchnorrPublicKey(copy(V.schnorrKey)));
      mlSecret = ok(MLDSA.prepareSecretKey(copy(V.mlSeed)));
      ecdsaPublic = ok(Secp256k1.preparePublicKey(copy(V.secpKey)));
    }
  };
  func record(id : Nat, keys : Credentials) : Account {
    // This callback captures a secret handle and survives as a generic payload.
    { id; accountName = "tenant"; keys; sign = func(message : Blob) : Blob {
      Ed25519.signPrepared(keys.edSecret, message)
    } }
  };
  func errors(keys : Credentials) {
    assert Ed25519.verifyPrepared(keys.edPublic, V.edMessage, "") == #err(#invalidSignature);
    assert RSA.signPrehashPrepared(keys.rsaSecret, "", F.salt) == #err(#invalidDigest);
    assert MLDSA.verifyPrepared(keys.mlPublic, V.mlMessage, "", V.mlContext) == #err(#invalidSignature);
    assert Secp256k1.schnorrSignPrepared(keys.schnorrSecret, V.zero32, "") == #err(#invalidAuxiliaryRandomness);
    assert P256.verifyPrehashPrepared(keys.p256Public, "", V.p256Signature) == #err(#invalidDigest);
    assert BLS.verifyICPrepared(keys.blsPublic, "alpha", "") == #err(#invalidLength);
    assert RSA.verifyPrehashPrepared(keys.rsaPublic, F.digest, "") == #err(#invalidSignature);
    assert Secp256k1.verifyPrehashPrepared(keys.ecdsaPublic, V.sampleHash, "") == #err(#invalidSignature);
  };
  func verify(keys : Credentials) {
    assert Ed25519.verifyPrepared(keys.edPublic, V.edMessage, V.edSignature) == #ok true;
    assert RSA.verifyPrehashPrepared(keys.rsaPublic, F.digest, F.signature) == #ok true;
    assert MLDSA.verifyPrepared(keys.mlPublic, V.mlMessage, V.mlSignature, V.mlContext) == #ok true;
    assert Secp256k1.verifyPrehashPrepared(keys.ecdsaPublic, V.sampleHash, V.secpSignature) == #ok true;
    assert P256.verifyPrehashPrepared(keys.p256Public, V.sampleHash, V.p256Signature) == #ok true;
    assert Secp256k1.schnorrVerifyPrepared(keys.schnorrPublic, V.zero32, V.schnorrSignature) == #ok true;
    assert BLS.verifyICPrepared(keys.blsPublic, "alpha", V.icSig0) == #ok true;
  };
  func sign(keys : Credentials) {
    // One exact known-answer call per secret scheme. Collection loops never sign.
    assert Ed25519.signPrepared(keys.edSecret, V.edMessage) == V.edSignature;
    assert RSA.signPrehashPrepared(keys.rsaSecret, F.digest, F.salt) == #ok(F.signature);
    assert MLDSA.signPrepared(keys.mlSecret, V.mlMessage, V.mlContext) == #ok(V.mlSignature);
    assert Secp256k1.schnorrSignPrepared(keys.schnorrSecret, V.zero32, V.zero32) == #ok(V.schnorrSignature);
  };
  func changedMessages(keys : Credentials) {
    assert Ed25519.verifyPrepared(keys.edPublic, "changed", V.edSignature) == #ok false;
    assert RSA.verifyPrepared(keys.rsaPublic, "changed", F.signature) == #ok false;
    assert MLDSA.verifyPrepared(keys.mlPublic, V.mlMessage, V.mlSignature, "changed") == #ok false;
    assert P256.verifyPrehashPrepared(keys.p256Public, V.zero32, V.p256Signature) == #ok false;
    assert Secp256k1.verifyPrehashPrepared(keys.ecdsaPublic, V.zero32, V.secpSignature) == #ok false;
    assert Secp256k1.schnorrVerifyPrepared(keys.schnorrPublic, "changed", V.schnorrSignature) == #ok false;
  };
  transient let accounts = Map.empty<Nat, Account>();
  transient var snapshot = PureMap.empty<Nat, Account>();
  transient var current = PureMap.empty<Nat, Account>();
  transient var aliases : [Account] = [];
  transient var callback : ?(() -> Credentials) = null;

  func install() {
    let keys = prepare();
    var id = 0;
    while (id < 96) {
      let account = record(id, keys);
      accounts.add(cmp, id, account);
      current := current.add(cmp, id, account);
      id += 1;
    };
    snapshot := current;
    aliases := [some(accounts.get(cmp, 0)), some(current.get(cmp, 95))];
    callback := ?(func() : Credentials { keys });
    id := 0;
    while (id < 64) {
      assert accounts.delete(cmp, id);
      current := current.remove(cmp, id);
      id += 1;
    };
    // A split mutable tree and two immutable versions share opaque payloads.
    assert accounts.size() == 32 and current.size() == 32;
    assert snapshot.size() == 96;
  };
  func checkMetadata() {
    var total = 0;
    for ((id, account) in accounts.entries()) {
      assert id >= 64 and account.id == id and account.accountName == "tenant";
      total += 1;
    };
    assert total == 32;
    total := 0;
    for ((id, account) in snapshot.entries()) {
      assert id == account.id and account.accountName == "tenant";
      total += 1;
    };
    assert total == 96;
    assert some(current.get(cmp, 95)).id == 95;
    assert not current.containsKey(cmp, 0);
    assert not accounts.containsKey(cmp, 0);
    assert aliases[0].id == 0 and aliases[1].id == 95;
  };
  func checkAll() {
    checkMetadata();
    // Distinct retrieval routes each consume native prepared values.
    errors(some(accounts.get(cmp, 64)).keys);
    verify(some(snapshot.get(cmp, 0)).keys);
    sign(some(current.get(cmp, 95)).keys);
    changedMessages((some(callback))());
    assert aliases[0].sign(V.edMessage) == V.edSignature;
    assert Ed25519.verifyPrepared(aliases[1].keys.edPublic, V.edMessage, V.edSignature) == #ok true;
  };
  func drop() {
    accounts.clear();
    snapshot := PureMap.empty();
    current := PureMap.empty();
    aliases := [];
    callback := null;
    assert accounts.isEmpty() and snapshot.isEmpty() and current.isEmpty();
  };

  func collect() : async () {
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
    while (settle < 4) { await async {}; settle += 1 };
  };
  public func test_prepared_business_records_survive_collection_and_release() : async Test.Metrics {
    install();
    checkMetadata();
    let before = Prim.rts_reclaimed();
    await collect();
    assert Prim.rts_reclaimed() > before + 4 * 1024 * 1024;
    // Every secret is used only after confirmed collection and message boundaries.
    // Local calls below return no handle; all their temporary aliases then die.
    checkAll();
    drop();
    let dropped = Prim.rts_reclaimed();
    await collect();
    assert Prim.rts_reclaimed() > dropped + 4 * 1024 * 1024;
    Test.test(func() {
      assert accounts.isEmpty() and snapshot.isEmpty() and current.isEmpty();
      assert aliases.size() == 0;
      switch callback { case null {}; case (?_) Prim.trap("prepared callback retained") };
      // Reclamation above proves collection ran after release, not exact live
      // bytes or secure secret erasure; the test deliberately claims neither.
    })
  };
}
