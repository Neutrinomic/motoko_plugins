import Test "mo:test";
import Cases "../lib/Secp256k1Tests";
import Secp "mo:fast/Secp256k1";
import Prim "mo:⛔";

persistent actor {
  type Retained = {
    secret : Blob;
    schnorrSecret : Blob;
    digest : Blob;
    auxiliary : Blob;
    key : Blob;
    uncompressedKey : Blob;
    signature : Blob;
    der : Blob;
    schnorr : Blob;
    xOnly : Blob;
    tweaked : Blob;
    tweakedSecret : Blob;
  };
  var persisted : ?Retained = null;
  transient var transientSaved : ?Retained = null;

  func ok<T>(result : Secp.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected secp256k1 error") }
  };

  public func test_sec2_points_and_tweaks() : async Test.Metrics { Test.test(Cases.pointVectors) };
  public func test_scalar_boundaries_and_invalid_sec1() : async Test.Metrics { Test.test(Cases.scalarAndPointErrors) };
  public func test_rfc6979_signatures_and_high_s() : async Test.Metrics { Test.test(Cases.ecdsaKnownAnswers) };
  public func test_ecdsa_validation_and_strict_der() : async Test.Metrics { Test.test(Cases.ecdsaAndDerErrors) };
  public func test_all_bip340_vectors() : async Test.Metrics { Test.test(Cases.schnorrKnownAnswers) };
  public func test_schnorr_input_validation() : async Test.Metrics { Test.test(Cases.schnorrErrors) };
  public func test_evaluation_order_and_aliases() : async Test.Metrics { Test.test(Cases.evaluationAndAliases) };
  public func test_retained_results_after_allocations() : async Test.Metrics { Test.test(Cases.retainedResults) };

  public func test_outputs_and_inputs_survive_actor_frame_gc() : async Test.Metrics {
    let one : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
    let three : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03";
    let expectedDigest : Blob = "\af\2b\db\e1\aa\9b\6e\c1\e2\ad\e1\d6\94\f4\1f\c7\1a\83\1d\02\68\e9\89\15\62\11\3d\8a\62\ad\d1\bf";
    let expectedKey : Blob = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98";
    let expectedUncompressed : Blob = "\04\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98\48\3a\da\77\26\a3\c4\65\5d\a4\fb\fc\0e\11\08\a8\fd\17\b4\48\a6\85\54\19\9c\47\d0\8f\fb\10\d4\b8";
    let expectedSignature : Blob = "\58\db\65\7b\cd\63\10\38\be\a0\7b\49\41\17\2f\01\67\ac\a9\8f\12\b5\5e\31\76\bd\1c\35\43\5d\65\01\3a\78\e7\3d\8f\f8\ab\55\4e\13\c1\0f\63\90\d8\1a\88\2f\91\94\5d\62\75\49\38\82\67\61\70\b5\3a\57";
    let expectedDer : Blob = "\30\44\02\20\58\db\65\7b\cd\63\10\38\be\a0\7b\49\41\17\2f\01\67\ac\a9\8f\12\b5\5e\31\76\bd\1c\35\43\5d\65\01\02\20\3a\78\e7\3d\8f\f8\ab\55\4e\13\c1\0f\63\90\d8\1a\88\2f\91\94\5d\62\75\49\38\82\67\61\70\b5\3a\57";
    let expectedSchnorr : Blob = "\e9\07\83\1f\80\84\8d\10\69\a5\37\1b\40\24\10\36\4b\df\1c\5f\83\07\b0\08\4c\55\f1\ce\2d\ca\82\15\25\f6\6a\4a\85\ea\8b\71\e4\82\a7\4f\38\2d\2c\e5\eb\ee\e8\fd\b2\17\2f\47\7d\f4\90\0d\31\05\36\c0";
    let expectedXOnly : Blob = "\f9\30\8a\01\92\58\c3\10\49\34\4f\85\f8\9d\52\29\b5\31\c8\45\83\6f\99\b0\86\01\f1\13\bc\e0\36\f9";
    let expectedTweaked : Blob = "\03\ff\f9\7b\d5\75\5e\ee\a4\20\45\3a\14\35\52\35\d3\82\f6\47\2f\85\68\a1\8b\2f\05\7a\14\60\29\75\56";
    // Input Blobs are allocated dynamically, so the test retains managed input
    // references as well as native outputs. Constants alone would not exercise
    // heap forwarding of secret/digest inputs.
    // Dead blocks precede and separate the retained Blobs as well as the large
    // live arrays below, so these small results also occupy sparse heap regions.
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let secret = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(32, func(i) { one[i] }));
    let schnorrSecret = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(32, func(i) { three[i] }));
    let digest = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(32, func(i) { expectedDigest[i] }));
    let auxiliary = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(32, func(_) { 0 }));
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let key = ok(Secp.derivePublicKey(secret));
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let signature = ok(Secp.signPrehash(secret, digest));
    let xOnly = ok(Secp.xOnlyPublicKey(ok(Secp.derivePublicKey(schnorrSecret))));
    let retained : Retained = {
      secret; schnorrSecret; digest; auxiliary; key; signature; xOnly;
      uncompressedKey = ok(Secp.decompressPublicKey(key));
      der = ok(Secp.signatureToDer(signature));
      schnorr = ok(Secp.schnorrSign(schnorrSecret, auxiliary, auxiliary));
      tweaked = ok(Secp.tweakXOnlyPublicKey(xOnly, schnorrSecret));
      tweakedSecret = ok(Secp.tweakXOnlySecretKey(schnorrSecret, schnorrSecret));
    };
    persisted := ?retained;
    transientSaved := ?retained;

    func verify() {
      // Three roots reach the same managed values: persistent actor state,
      // transient actor state, and this closure in the suspended async frame.
      switch (persisted, transientSaved) {
        case (?durable, ?temporary) {
          assert durable == retained;
          assert temporary == retained;
        };
        case _ assert false;
      };
      assert retained.secret == one and retained.schnorrSecret == three;
      assert retained.digest == expectedDigest;
      assert retained.auxiliary.size() == 32;
      assert retained.auxiliary[0] == 0 and retained.auxiliary[31] == 0;
      assert retained.key == expectedKey;
      assert retained.uncompressedKey == expectedUncompressed;
      assert retained.signature == expectedSignature;
      assert retained.der == expectedDer;
      assert retained.schnorr == expectedSchnorr;
      assert retained.xOnly == expectedXOnly;
      assert retained.tweaked == expectedTweaked;
      assert retained.tweakedSecret == "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06";
      // Reuse forwarded inputs and outputs at the native boundary, including
      // outputs used as inputs to later conversion and verification calls.
      assert ok(Secp.derivePublicKey(retained.secret)) == retained.key;
      assert ok(Secp.signPrehash(retained.secret, retained.digest)) == retained.signature;
      assert ok(Secp.verifyPrehash(retained.uncompressedKey, retained.digest, retained.signature));
      assert ok(Secp.signatureFromDer(retained.der)) == retained.signature;
      assert ok(Secp.schnorrVerify(retained.xOnly, retained.auxiliary, retained.schnorr));
      assert ok(Secp.tweakXOnlyPublicKey(retained.xOnly, retained.schnorrSecret)) == retained.tweaked;
      assert ok(Secp.derivePublicKey(retained.tweakedSecret)) == retained.tweaked;
      let tweakedSignature = ok(Secp.schnorrSign(retained.tweakedSecret, retained.digest, retained.auxiliary));
      assert ok(Secp.schnorrVerify(ok(Secp.xOnlyPublicKey(retained.tweaked)), retained.digest, tweakedSignature));
    };
    verify();
    let reclaimedBefore = Prim.rts_reclaimed();
    // Keep 64 MiB alive between 64 MiB of dead arrays, creating holes that
    // force evacuation rather than just dropping a dead suffix. This exceeds
    // the normal GC threshold without requiring --force-gc on the whole suite.
    let live = Prim.Array_tabulateVar<[var Nat]>(128, func(n) {
      ignore Prim.Array_init<Nat>(64 * 1024, 0);
      Prim.Array_init<Nat>(64 * 1024, n)
    });
    await async {};
    var round = 0;
    while (round < 16) {
      assert live[0][65535] == 0 and live[127][65535] == 127;
      verify();
      ignore Prim.Array_init<Nat>(128 * 1024, round);
      round += 1;
      await async {};
    };
    // A test that merely awaited without collecting cannot satisfy this check.
    assert Prim.rts_reclaimed() > reclaimedBefore + 16 * 1024 * 1024;
    return Test.test(func() {
      assert live[0][65535] == 0 and live[127][65535] == 127;
      verify();
      persisted := null;
      transientSaved := null;
    })
  };
}
