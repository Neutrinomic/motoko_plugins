import Test "mo:test";
import P256 "mo:fast/P256";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Prim "mo:⛔";
import EncodingTests "../lib/P256EncodingTests";

// RFC 6979 A.2.5 and pinned C2SP Wycheproof vectors; see coverage/P256.md.
// SHA-256 digests are fixed independent answers, so this suite loads only P256.
persistent actor {
  public func test_der_all_lengths_and_padding_boundaries() : async Test.Metrics {
    Test.test(EncodingTests.derLengthsAndPadding)
  };

  public func test_sec1_canonical_coordinate_boundaries() : async Test.Metrics {
    Test.test(EncodingTests.sec1CanonicalCoordinates)
  };

  public func test_sec1_all_tags_and_truncations() : async Test.Metrics {
    Test.test(EncodingTests.sec1TagsAndLengths)
  };

  func concat(a : Blob, b : Blob) : Blob { Blob.fromArray(a.toArray().concat(b.toArray())) };
  type RetainedPrepared = { key : P256.PreparedPublicKey; aliases : [P256.PreparedPublicKey] };
  transient var retainedPrepared : ?RetainedPrepared = null;
  func prepared(key : Blob) : P256.PreparedPublicKey {
    switch (P256.preparePublicKey(key)) {
      case (#ok value) value;
      case (#err _) Prim.trap("unexpected prepared public key error");
    }
  };
  let secret : Blob = "\c9\af\a9\d8\45\ba\75\16\6b\5c\21\57\67\b1\d6\93\4e\50\c3\db\36\e8\9b\12\7b\8a\62\2b\12\0f\67\21";
  let publicCompressed : Blob = "\03\60\fe\d4\ba\25\5a\9d\31\c9\61\eb\74\c6\35\6d\68\c0\49\b8\92\3b\61\fa\6c\e6\69\62\2e\60\f2\9f\b6";
  let publicUncompressed : Blob = "\04\60\fe\d4\ba\25\5a\9d\31\c9\61\eb\74\c6\35\6d\68\c0\49\b8\92\3b\61\fa\6c\e6\69\62\2e\60\f2\9f\b6\79\03\fe\10\08\b8\bc\99\a4\1a\e9\e9\56\28\bc\64\f2\f1\b2\0c\2d\7e\9f\51\77\a3\c2\94\d4\46\22\99";
  let sampleHash : Blob = "\af\2b\db\e1\aa\9b\6e\c1\e2\ad\e1\d6\94\f4\1f\c7\1a\83\1d\02\68\e9\89\15\62\11\3d\8a\62\ad\d1\bf";
  let testHash : Blob = "\9f\86\d0\81\88\4c\7d\65\9a\2f\ea\a0\c5\5a\d0\15\a3\bf\4f\1b\2b\0b\82\2c\d1\5d\6c\15\b0\f0\0a\08";
  let sampleSignature : Blob = "\ef\d4\8b\2a\ac\b6\a8\fd\11\40\dd\9c\d4\5e\81\d6\9d\2c\87\7b\56\aa\f9\91\c3\4d\0e\a8\4e\af\37\16\f7\cb\1c\94\2d\65\7c\41\d4\36\c7\a1\b6\e2\9f\65\f3\e9\00\db\b9\af\f4\06\4d\c4\ab\2f\84\3a\cd\a8";
  let testSignature : Blob = "\f1\ab\b0\23\51\83\51\cd\71\d8\81\56\7b\1e\a6\63\ed\3e\fc\f6\c5\13\2b\35\4f\28\d3\b0\b7\d3\83\67\01\9f\41\13\74\2a\2b\14\bd\25\92\6b\49\c6\49\15\5f\26\7e\60\d3\81\4b\4c\0c\c8\42\50\e4\6f\00\83";
  let sampleLowSignature : Blob = "\ef\d4\8b\2a\ac\b6\a8\fd\11\40\dd\9c\d4\5e\81\d6\9d\2c\87\7b\56\aa\f9\91\c3\4d\0e\a8\4e\af\37\16\08\34\e3\6a\d2\9a\83\bf\2b\c9\38\5e\49\1d\60\99\c8\fd\f9\d1\ed\67\aa\7e\a5\f5\1f\93\78\28\57\a9";
  let sampleDer : Blob = "\30\46\02\21\00\ef\d4\8b\2a\ac\b6\a8\fd\11\40\dd\9c\d4\5e\81\d6\9d\2c\87\7b\56\aa\f9\91\c3\4d\0e\a8\4e\af\37\16\02\21\00\f7\cb\1c\94\2d\65\7c\41\d4\36\c7\a1\b6\e2\9f\65\f3\e9\00\db\b9\af\f4\06\4d\c4\ab\2f\84\3a\cd\a8";
  let one : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
  let zero : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
  let order : Blob = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51";
  let maxScalar : Blob = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50";
  let allOnes : Blob = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff";
  let generatorCompressed : Blob = "\03\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96";
  let negativeGeneratorCompressed : Blob = "\02\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96";

  public func test_rfc6979_key_derivation_and_sec1_conversion() : async Test.Metrics {
    Test.test(func() {
      assert P256.publicKey(secret, true) == #ok publicCompressed;
      assert P256.derivePublicKey(secret) == #ok publicCompressed;
      assert P256.publicKey(secret, false) == #ok publicUncompressed;
      assert P256.convertPublicKey(publicCompressed, false) == #ok publicUncompressed;
      assert P256.convertPublicKey(publicUncompressed, true) == #ok publicCompressed;
      assert P256.convertPublicKey(publicCompressed, true) == #ok publicCompressed;
      assert P256.convertPublicKey(publicUncompressed, false) == #ok publicUncompressed;
      assert P256.publicKey(one, true) == #ok generatorCompressed;
      assert P256.publicKey(maxScalar, true) == #ok negativeGeneratorCompressed;
    })
  };

  public func test_rfc6979_sha256_signatures_and_high_s_verification() : async Test.Metrics {
    Test.test(func() {
      // RFC 6979 A.2.5 signatures retain the specified s, including high s.
      assert P256.signPrehash(secret, sampleHash) == #ok sampleSignature;
      assert P256.signPrehash(secret, testHash) == #ok testSignature;
      assert P256.verifyPrehash(publicCompressed, sampleHash, sampleSignature) == #ok true;
      assert P256.verifyPrehash(publicUncompressed, testHash, testSignature) == #ok true;
      assert P256.verifyPrehash(publicCompressed, sampleHash, sampleLowSignature) == #ok true;
      assert P256.verifyPrehash(publicCompressed, testHash, sampleSignature) == #ok false;
      assert P256.verifyPrehash(generatorCompressed, sampleHash, sampleSignature) == #ok false;
    })
  };

  public func test_der_conversion_and_explicit_normalization() : async Test.Metrics {
    Test.test(func() {
      assert P256.signatureToDer(sampleSignature) == #ok sampleDer;
      assert P256.signatureFromDer(sampleDer) == #ok sampleSignature;
      assert P256.normalizeSignature(sampleSignature) == #ok sampleLowSignature;
      assert P256.normalizeSignature(sampleLowSignature) == #ok sampleLowSignature;
      assert P256.normalizeSignature(testSignature) == #ok testSignature;
      // Positive INTEGER padding and minimal one-byte scalars.
      let minimal = "\30\06\02\01\01\02\01\01" : Blob;
      assert P256.signatureToDer(concat(one, one)) == #ok minimal;
      assert P256.signatureFromDer(minimal) == #ok (concat(one, one));
      assert P256.normalizeSignature(concat(one, maxScalar)) == #ok (concat(one, one));
      assert P256.normalizeSignature(concat(maxScalar, one)) == #ok (concat(maxScalar, one));
    })
  };

  public func test_prepared_rfc6979_aliases_and_evaluation_order() : async Test.Metrics {
    Test.test(func() {
      func identity<T>(value : T) : T { value };
      let prepare = P256.preparePublicKey;
      let verify = P256.verifyPrehashPrepared;
      let key = prepared(publicCompressed);
      let uncompressed = switch (prepare(publicUncompressed)) {
        case (#ok value) value;
        case (#err _) Prim.trap("unexpected uncompressed prepared key error");
      };
      let record = { key = identity(key); aliases = [key, uncompressed] };
      func verifyWrapped(key : P256.PreparedPublicKey, digest : Blob, signature : Blob) : P256.Result<Bool> {
        P256.verifyPrehashPrepared(key, digest, signature)
      };
      let callbacks : [(P256.PreparedPublicKey, Blob, Blob) -> P256.Result<Bool>] = [verifyWrapped];
      assert callbacks[0](record.key, sampleHash, sampleSignature) == #ok true;
      assert verify(record.aliases[0], sampleHash, sampleLowSignature) == #ok true;
      assert verify(record.aliases[1], testHash, testSignature) == #ok true;
      assert verify(record.key, testHash, sampleSignature) == #ok false;
      assert verify(prepared(generatorCompressed), sampleHash, sampleSignature) == #ok false;
      var order = 0;
      func keyArgument() : P256.PreparedPublicKey { assert order == 0; order += 1; record.key };
      func digestArgument() : Blob { assert order == 1; order += 1; sampleHash };
      func signatureArgument() : Blob { assert order == 2; order += 1; sampleSignature };
      assert verify(keyArgument(), digestArgument(), signatureArgument()) == #ok true;
      assert order == 3;
      // Later preparations and invalid operations cannot overwrite an earlier key.
      ignore prepared(negativeGeneratorCompressed);
      assert verify(record.key, "", "") == #err(#invalidDigest);
      assert verify(record.aliases[1], sampleHash, sampleSignature) == #ok true;
    })
  };

  public func test_prepared_digest_signature_errors_and_precedence() : async Test.Metrics {
    Test.test(func() {
      let key = prepared(publicCompressed);
      let shortHash = Blob.fromArray(Array.repeat<Nat8>(0, 31));
      for (hash in (["", shortHash, concat(sampleHash, "\00")] : [Blob]).values()) {
        // Both malformed arguments still report the digest first.
        assert P256.verifyPrehashPrepared(key, hash, "") == #err(#invalidDigest);
        assert P256.verifyPrehashPrepared(key, hash, sampleSignature) == #err(#invalidDigest);
      };
      let bad : [Blob] = ["", "\01", concat(sampleSignature, "\00"), concat(zero, one), concat(one, zero), concat(order, one), concat(one, order), concat(allOnes, one), concat(one, allOnes)];
      for (signature in bad.values()) {
        assert P256.verifyPrehashPrepared(key, sampleHash, signature) == #err(#invalidSignature);
      };
      assert P256.verifyPrehashPrepared(key, sampleHash, concat(one, one)) == #ok false;
      assert P256.verifyPrehashPrepared(key, sampleHash, sampleSignature) == #ok true;
    })
  };

  public func test_secret_key_ranges_and_digest_lengths() : async Test.Metrics {
    Test.test(func() {
      let invalidKeys : [Blob] = ["", zero, order, allOnes, concat(one, "\00"), "\01"];
      for (key in invalidKeys.values()) {
        assert P256.publicKey(key, true) == #err(#invalidSecretKey);
        assert P256.publicKey(key, false) == #err(#invalidSecretKey);
        assert P256.signPrehash(key, sampleHash) == #err(#invalidSecretKey);
      };
      let shortHash = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00" : Blob;
      for (hash in (["", shortHash, concat(sampleHash, "\00")] : [Blob]).values()) {
        assert P256.signPrehash(secret, hash) == #err(#invalidDigest);
        assert P256.verifyPrehash(publicCompressed, hash, sampleSignature) == #err(#invalidDigest);
      };
      // Digests are full 256-bit strings, not restricted to scalar range.
      for (hash in ([zero, order, allOnes] : [Blob]).values()) {
        switch (P256.signPrehash(secret, hash)) {
          case (#ok signature) assert P256.verifyPrehash(publicCompressed, hash, signature) == #ok true;
          case (#err _) assert false;
        };
      };
    })
  };

  public func test_strict_sec1_rejects_invalid_points() : async Test.Metrics {
    Test.test(func() {
      let bad : [Blob] = [
        "", "\00", "\02", concat(publicCompressed, "\00"), concat(publicUncompressed, "\00"),
        // Wrong tags, hybrid encoding, off-curve point, x >= field modulus.
        concat("\04", zero), concat(concat("\06", zero), zero), concat(concat("\07", zero), zero),
        concat(concat("\04", zero), zero),
        "\02\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff",
        concat("\03", allOnes),
      ];
      for (key in bad.values()) {
        assert P256.convertPublicKey(key, true) == #err(#invalidPublicKey);
        assert P256.convertPublicKey(key, false) == #err(#invalidPublicKey);
        assert P256.verifyPrehash(key, sampleHash, sampleSignature) == #err(#invalidPublicKey);
        switch (P256.preparePublicKey(key)) {
          case (#err(#invalidPublicKey)) {};
          case _ Prim.trap("malformed SEC1 accepted by preparePublicKey");
        };
      };
      // A correctly sized hybrid encoding of an otherwise valid point is rejected.
      let hybrid = "\07\60\fe\d4\ba\25\5a\9d\31\c9\61\eb\74\c6\35\6d\68\c0\49\b8\92\3b\61\fa\6c\e6\69\62\2e\60\f2\9f\b6\79\03\fe\10\08\b8\bc\99\a4\1a\e9\e9\56\28\bc\64\f2\f1\b2\0c\2d\7e\9f\51\77\a3\c2\94\d4\46\22\99" : Blob;
      assert P256.convertPublicKey(hybrid, true) == #err(#invalidPublicKey);
      switch (P256.preparePublicKey(hybrid)) {
        case (#err(#invalidPublicKey)) {};
        case _ Prim.trap("hybrid SEC1 accepted by preparePublicKey");
      };
    })
  };

  public func test_signature_scalar_ranges_and_error_precedence() : async Test.Metrics {
    Test.test(func() {
      let bad : [Blob] = ["", "\01", concat(sampleSignature, "\00"), concat(zero, one), concat(one, zero), concat(order, one), concat(one, order), concat(allOnes, one), concat(one, allOnes)];
      for (signature in bad.values()) {
        assert P256.signatureToDer(signature) == #err(#invalidSignature);
        assert P256.normalizeSignature(signature) == #err(#invalidSignature);
        assert P256.verifyPrehash(publicCompressed, sampleHash, signature) == #err(#invalidSignature);
      };
      assert P256.signPrehash("", "") == #err(#invalidSecretKey);
      assert P256.verifyPrehash("", "", "") == #err(#invalidPublicKey);
      assert P256.verifyPrehash(publicCompressed, "", "") == #err(#invalidDigest);
      assert P256.verifyPrehash(publicCompressed, sampleHash, "") == #err(#invalidSignature);
      assert P256.verifyPrehash(publicCompressed, sampleHash, concat(one, one)) == #ok false;
      assert P256.signPrehash(secret, sampleHash) == #ok sampleSignature;
    })
  };

  public func test_strict_der_rejects_nonminimal_and_malformed_values() : async Test.Metrics {
    Test.test(func() {
      let invalid : [Blob] = [
        "", "\30", "\30\00", "\30\06\02\01\00\02\01\01",
        "\30\06\02\01\01\02\01\00",
        "\30\06\02\01\80\02\01\01", // Negative integer.
        "\30\07\02\02\00\01\02\01\01", // Redundant positive padding.
        "\30\05\02\00\02\01\01", // Empty integer.
        "\30\06\02\01\01\02\01\01\00", // Trailing byte.
        "\30\81\06\02\01\01\02\01\01", // Nonminimal sequence length.
        "\30\07\02\81\01\01\02\01\01", // Nonminimal integer length.
        "\30\80\02\01\01\02\01\01\00\00", // Indefinite length.
        "\31\06\02\01\01\02\01\01", // Wrong sequence tag.
        "\30\06\03\01\01\02\01\01", // Wrong integer tag.
        "\30\09\02\01\01\02\01\01\02\01\01", // Third integer.
        "\30\06\02\01\01\02\01", // Truncated input.
      ];
      for (input in invalid.values()) {
        assert P256.signatureFromDer(input) == #err(#invalidSignature);
      };
      assert P256.signatureFromDer(sampleDer) == #ok sampleSignature;
    })
  };

  public func test_aliases_evaluation_order_and_retained_outputs() : async Test.Metrics {
    Test.test(func() {
      let derive = P256.publicKey;
      func identity<T>(value : T) : T = value;
      let aliases = [derive, identity(derive)];
      assert aliases[0](secret, true) == #ok publicCompressed;
      assert aliases[1](secret, false) == #ok publicUncompressed;
      func verify(key : Blob, digest : Blob, signature : Blob) : P256.Result<Bool> { P256.verifyPrehash(key, digest, signature) };
      let callback : (Blob, Blob, Blob) -> P256.Result<Bool> = verify;
      assert callback(publicCompressed, sampleHash, sampleSignature) == #ok true;
      var order = "";
      let result = (do { order #= "callee;"; P256.signPrehash })(
        do { order #= "secret;"; secret },
        do { order #= "digest;"; sampleHash }
      );
      assert order == "callee;secret;digest;";
      assert result == #ok sampleSignature;
      let saved = P256.signatureToDer(sampleSignature);
      var i = 0;
      while (i < 16) {
        assert P256.convertPublicKey(publicCompressed, false) == #ok publicUncompressed;
        assert P256.signatureToDer(concat(one, one)) == #ok "\30\06\02\01\01\02\01\01";
        assert saved == #ok sampleDer;
        i += 1;
      };
      assert result == #ok sampleSignature;
      assert P256.signPrehash(secret, sampleHash) == result;
    })
  };

  public func test_rfc6979_digest_reduction_boundaries() : async Test.Metrics {
    Test.test(func() {
      // Independent RFC6979 + OpenSSL vectors. RFC6979 bits2octets reduces the
      // prehash modulo n before nonce generation; digest n must sign identically to 0.
      let boundaryVectors : [(Blob, Blob)] = [
        // zero
        ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", "\68\89\7a\78\df\51\05\8b\49\0c\60\12\25\1c\95\92\1a\bb\a9\6e\2e\48\8c\8c\c9\98\94\2e\44\0d\b9\b7\80\58\7f\b3\87\36\3a\1d\f2\c9\e8\3c\00\f8\ca\99\0f\c0\a5\5b\5e\47\09\46\49\9b\82\ca\3b\55\2a\87"),
        // n_minus_one
        ("\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50", "\c6\75\c4\3e\82\9a\5e\83\8b\e6\01\45\15\bc\c7\d8\2f\b8\d3\05\3c\77\0d\32\d3\22\a9\e9\e3\55\30\e7\49\99\6e\b9\5b\9f\44\71\48\4b\96\cd\60\fe\f8\0a\14\f6\50\4e\d7\27\9e\13\34\04\a6\1e\1a\b8\ae\e5"),
        // n
        ("\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51", "\68\89\7a\78\df\51\05\8b\49\0c\60\12\25\1c\95\92\1a\bb\a9\6e\2e\48\8c\8c\c9\98\94\2e\44\0d\b9\b7\80\58\7f\b3\87\36\3a\1d\f2\c9\e8\3c\00\f8\ca\99\0f\c0\a5\5b\5e\47\09\46\49\9b\82\ca\3b\55\2a\87"),
        // all_ff
        ("\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff", "\1f\2a\db\c5\4b\88\76\4c\27\9f\68\9f\c9\50\59\59\fc\9e\73\e8\0d\c2\08\89\a4\e0\be\91\86\5d\e7\5b\9d\10\9b\65\e2\fb\fc\0a\e4\2b\a0\b2\e5\f0\36\70\cd\45\8c\ff\48\82\df\67\83\f3\d9\3d\60\7d\17\55"),
      ];
      let key = prepared(publicCompressed);
      for ((digest, expected) in boundaryVectors.values()) {
        assert P256.signPrehash(secret, digest) == #ok expected;
        assert P256.verifyPrehash(publicCompressed, digest, expected) == #ok true;
        assert P256.verifyPrehashPrepared(key, digest, expected) == #ok true;
      };
      assert P256.signPrehash(secret, order) == P256.signPrehash(secret, zero);
    })
  };

  public func test_der72_retained_across_await_and_forced_gc() : async Test.Metrics {
    // Both RFC6979 sample scalars require DER sign padding, yielding exactly
    // 72 bytes. This exercises returning the complete managed output buffer.
    let saved = switch (P256.signatureToDer(sampleSignature)) {
      case (#ok bytes) bytes;
      case (#err _) Prim.trap("unexpected DER conversion error");
    };
    let aliases = [saved, saved];
    func verifySaved() {
      assert saved.size() == 72 and saved == sampleDer;
      assert aliases[0] == sampleDer and aliases[1] == sampleDer;
      assert P256.signatureFromDer(saved) == #ok sampleSignature;
    };
    verifySaved();
    let different72 = concat(maxScalar, maxScalar);
    let minimal = concat(one, one);
    let reclaimedBefore = Prim.rts_reclaimed();
    var round = 0;
    while (round < 9) {
      // Distinct full-capacity outputs, short outputs and error paths must
      // never overwrite the retained buffer. The GC skips its active 64-MiB
      // allocation partition; nine 8-MiB batches make the partition holding
      // saved eligible for evacuation, without retaining the pressure data.
      switch (P256.signatureToDer(different72)) {
        case (#ok bytes) assert bytes.size() == 72 and bytes != saved;
        case (#err _) assert false;
      };
      assert P256.signatureToDer(minimal) == #ok "\30\06\02\01\01\02\01\01";
      assert P256.signatureToDer("") == #err(#invalidSignature);
      var pressure = 0;
      while (pressure < 8) {
        ignore Prim.Array_init<Nat>(131_072, round + pressure);
        pressure += 1;
      };
      await async {};
      verifySaved();
      round += 1;
    };
    var settle = 0;
    while (settle < 4) {
      await async {};
      verifySaved();
      settle += 1;
    };
    // This confirms collection occurred while the managed Blob survived in
    // continuation locals and aliases, rather than merely testing allocation.
    assert Prim.rts_reclaimed() > reclaimedBefore + 4 * 1024 * 1024;
    Test.test(verifySaved)
  };

  public func test_prepared_keys_survive_gc_drop_and_reprepare() : async Test.Metrics {
    func retainAcrossCollection() : async () {
      // Allocate the key between discarded data so it belongs to a sparse,
      // movable heap region. Its payload must be borrowed afresh after each GC.
      ignore Prim.Array_init<Nat>(131_072, 0);
      let source = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(publicCompressed.size(), func(i) { publicCompressed[i] }));
      let key = prepared(source);
      let saved : RetainedPrepared = { key; aliases = [key, key] };
      retainedPrepared := ?saved;
      func checkSaved() {
        assert P256.verifyPrehashPrepared(saved.aliases[0], sampleHash, sampleSignature) == #ok true;
        switch retainedPrepared {
          case (?root) {
            assert P256.verifyPrehashPrepared(root.key, sampleHash, sampleLowSignature) == #ok true;
            assert P256.verifyPrehashPrepared(root.aliases[1], testHash, testSignature) == #ok true;
          };
          case null Prim.trap("prepared actor root lost across await");
        };
      };
      checkSaved();
      let reclaimedBefore = Prim.rts_reclaimed();
      var round = 0;
      while (round < 9) {
        // Temporary prepared keys exercise fresh outputs and later discard;
        // they must not overwrite any alias of the retained public key.
        let other = prepared(generatorCompressed);
        assert P256.verifyPrehashPrepared(other, sampleHash, sampleSignature) == #ok false;
        assert P256.verifyPrehashPrepared(key, "", "") == #err(#invalidDigest);
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
      assert Prim.rts_reclaimed() > reclaimedBefore + 4 * 1024 * 1024;
      retainedPrepared := null;
      // Returning also drops the continuation-local key and record/array roots.
    };
    await retainAcrossCollection();
    switch retainedPrepared { case null {}; case (?_) Prim.trap("prepared root not dropped") };
    let reclaimedAfterDrop = Prim.rts_reclaimed();
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
    assert Prim.rts_reclaimed() > reclaimedAfterDrop + 4 * 1024 * 1024;
    Test.test(func() {
      let key = prepared(publicUncompressed);
      assert P256.verifyPrehashPrepared(key, sampleHash, sampleSignature) == #ok true;
      assert P256.verifyPrehashPrepared(key, sampleHash, sampleLowSignature) == #ok true;
      assert P256.verifyPrehashPrepared(key, testHash, sampleSignature) == #ok false;
    })
  };

  public func test_projective_verification_boundaries() : async Test.Metrics {
    Test.test(func() {
      // Independent Python affine ECDSA constructions: Q = r^-1 R, digest = 0, s = 1.
      // benchmarks/crypto/round4/p256/projective-check/vectors.json
      // SHA-256: d1e2824284d92f29cb86346b9059d1eabae67bffeb1349b2be775504befa1a62
      // Well-formed scalar/point encodings must return #ok(false) for the wrap cases.
      let vectors : [{ name : Text; publicKey : Blob; digest : Blob; signature : Blob; valid : Bool }] = [
        // Valid x = n + 3 requires the rare second ECDSA representative.
        {
          name = "rare_n_plus_3";
          publicKey = "\02\02\bc\84\7e\19\eb\be\40\a3\67\ce\d6\48\06\85\11\bb\c2\4d\ba\56\32\2f\d5\28\85\60\4e\dd\c0\9e\af";
          digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
          signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
          valid = true;
        },
        // Valid x = p - 3 remains a canonical field coordinate above n.
        {
          name = "near_p_minus_3";
          publicKey = "\02\f7\e9\89\e3\80\02\37\42\31\cd\08\0c\e6\65\66\f5\ef\ab\d1\e5\13\3f\3f\7c\ef\d2\98\36\a0\38\9a\ea";
          digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
          signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\43\19\05\53\58\e8\61\7b\0c\46\35\3d\03\9c\da\ab\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
          valid = true;
        },
        // Invalid r + n = p must not wrap to the actual x = 0 in the field.
        {
          name = "reject_field_wrap";
          publicKey = "\02\4b\31\d6\2f\d9\e3\33\41\46\b7\e2\06\f7\f4\ba\35\20\dd\84\94\be\e0\6d\5c\94\6a\e5\f7\47\5f\9d\8a";
          digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
          signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\43\19\05\53\58\e8\61\7b\0c\46\35\3d\03\9c\da\ae\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
          valid = false;
        },
        // Invalid r + n = 2^256 must not wrap to the actual x = 0 in limbs.
        {
          name = "reject_limb_wrap";
          publicKey = "\02\b2\6c\57\6d\4e\7d\55\2d\06\02\b3\ed\f2\84\be\43\a2\86\d8\5a\47\64\4c\69\46\6d\ef\fb\79\74\8e\46";
          digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
          signature = "\00\00\00\00\ff\ff\ff\ff\00\00\00\00\00\00\00\00\43\19\05\52\58\e8\61\7b\0c\46\35\3d\03\9c\da\af\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
          valid = false;
        },
      ];
      for (vector in vectors.values()) {
        assert P256.verifyPrehash(vector.publicKey, vector.digest, vector.signature) == #ok(vector.valid);
        let key = switch (P256.preparePublicKey(vector.publicKey)) {
          case (#ok value) value;
          case (#err _) Prim.trap("projective fixture preparation failed: " # vector.name);
        };
        assert P256.verifyPrehashPrepared(key, vector.digest, vector.signature) == #ok(vector.valid);
      };
    })
  };

  type Vector = { id : Nat; publicKey : Blob; digest : Blob; der : Blob; compact : ?Blob; valid : Bool };
  func checkVector(v : Vector) {
    switch (v.compact) {
      case null { assert not v.valid; assert P256.signatureFromDer(v.der) == #err(#invalidSignature) };
      case (?expected) {
        assert P256.signatureFromDer(v.der) == #ok expected;
        assert P256.signatureToDer(expected) == #ok(v.der);
        assert P256.verifyPrehash(v.publicKey, v.digest, expected) == #ok(v.valid);
        assert P256.verifyPrehashPrepared(prepared(v.publicKey), v.digest, expected) == #ok(v.valid);
      };
    };
  };

  public func test_wycheproof_1() : async Test.Metrics {
    Test.test(func() {
      let vectors : [Vector] = [
        // tcId 1: pseudorandom signature (ValidSignature).
        { id = 1; publicKey = "\04\04\aa\ec\73\63\57\26\f2\13\fb\8a\9e\64\da\3b\86\32\e4\14\95\a9\44\d0\04\5b\52\2e\ba\72\40\fa\d5\87\d9\31\57\98\aa\a3\a5\ba\01\77\57\87\ce\d0\5e\aa\f7\b4\e0\9f\c8\1d\6d\1a\a5\46\e8\36\5d\52\5d"; digest = "\e3\b0\c4\42\98\fc\1c\14\9a\fb\f4\c8\99\6f\b9\24\27\ae\41\e4\64\9b\93\4c\a4\95\99\1b\78\52\b8\55"; der = "\30\45\02\21\00\b2\92\a6\19\33\9f\6e\56\7a\30\5c\95\1c\0d\cb\cc\42\d1\6e\47\f2\19\f9\e9\8e\76\e0\9d\87\70\b3\4a\02\20\01\77\e6\04\92\c5\a8\24\2f\76\f0\7b\fe\36\61\bd\e5\9e\c2\a1\7c\e5\bd\2d\ab\2a\be\bd\f8\9a\62\e2"; compact = ?"\b2\92\a6\19\33\9f\6e\56\7a\30\5c\95\1c\0d\cb\cc\42\d1\6e\47\f2\19\f9\e9\8e\76\e0\9d\87\70\b3\4a\01\77\e6\04\92\c5\a8\24\2f\76\f0\7b\fe\36\61\bd\e5\9e\c2\a1\7c\e5\bd\2d\ab\2a\be\bd\f8\9a\62\e2"; valid = true },
        // tcId 2: pseudorandom signature (ValidSignature).
        { id = 2; publicKey = "\04\04\aa\ec\73\63\57\26\f2\13\fb\8a\9e\64\da\3b\86\32\e4\14\95\a9\44\d0\04\5b\52\2e\ba\72\40\fa\d5\87\d9\31\57\98\aa\a3\a5\ba\01\77\57\87\ce\d0\5e\aa\f7\b4\e0\9f\c8\1d\6d\1a\a5\46\e8\36\5d\52\5d"; digest = "\dc\19\21\94\6f\4a\f9\6a\28\56\e7\be\39\90\07\c9\e8\07\bd\f4\c5\33\2f\19\f5\9e\c9\dd\1b\b8\c7\b3"; der = "\30\45\02\20\53\0b\d6\b0\c9\af\2d\69\ba\89\7f\6b\5f\b5\96\95\cf\bf\33\af\e6\6d\ba\dc\f5\b8\d2\a2\a6\53\8e\23\02\21\00\d8\5e\48\9c\b7\a1\61\fd\55\ed\ed\ce\db\f4\cc\0c\09\87\e3\e3\f0\f2\42\ca\e9\34\c7\2c\aa\3f\43\e9"; compact = ?"\53\0b\d6\b0\c9\af\2d\69\ba\89\7f\6b\5f\b5\96\95\cf\bf\33\af\e6\6d\ba\dc\f5\b8\d2\a2\a6\53\8e\23\d8\5e\48\9c\b7\a1\61\fd\55\ed\ed\ce\db\f4\cc\0c\09\87\e3\e3\f0\f2\42\ca\e9\34\c7\2c\aa\3f\43\e9"; valid = true },
        // tcId 5: signature malleability (ValidSignature).
        { id = 5; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\20\4c\d6\0b\85\5d\44\2f\5b\3c\7b\11\eb\6c\4e\0a\e7\52\5f\e7\10\fa\b9\aa\7c\77\a6\7f\79\e6\fa\dd\76"; compact = ?"\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\4c\d6\0b\85\5d\44\2f\5b\3c\7b\11\eb\6c\4e\0a\e7\52\5f\e7\10\fa\b9\aa\7c\77\a6\7f\79\e6\fa\dd\76"; valid = true },
        // tcId 6: Legacy: ASN encoding of s misses leading 0 (MissingZero).
        { id = 6; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\20\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 7: valid (ValidSignature).
        { id = 7; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\45\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = ?"\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; valid = true },
        // tcId 8: length of sequence [r, s] uses long form encoding (BerEncodedSignature).
        { id = 8; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\81\45\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 9: length of sequence [r, s] contains a leading 0 (BerEncodedSignature).
        { id = 9; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\82\00\45\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 10: length of sequence [r, s] uses 70 instead of 69 (InvalidEncoding).
        { id = 10; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\46\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 12: uint32 overflow in length of sequence [r, s] (InvalidEncoding).
        { id = 12; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\85\01\00\00\00\45\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 13: uint64 overflow in length of sequence [r, s] (InvalidEncoding).
        { id = 13; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\89\01\00\00\00\00\00\00\00\45\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 23: appending 0's to sequence [r, s] (ModifiedSignature).
        { id = 23; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\47\02\20\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db\00\00"; compact = null; valid = false },
        // tcId 152: replaced r by r + n (RangeCheck).
        { id = 152; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\46\02\21\01\2b\a3\a8\bd\6b\94\d5\ed\80\a6\d9\d1\19\0a\43\6e\bc\cc\08\33\49\06\86\de\ac\86\35\bc\b9\bf\53\69\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 155: replaced r by -r (ModifiedInteger).
        { id = 155; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\45\02\20\d4\5c\57\41\94\6b\2a\13\7f\59\26\2e\e6\f5\bc\91\00\1a\f2\7a\5e\11\17\a6\47\33\95\06\42\a3\d1\e8\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
      ];
      for (vector in vectors.values()) { checkVector(vector) };
    })
  };

  public func test_wycheproof_2() : async Test.Metrics {
    Test.test(func() {
      let vectors : [Vector] = [
        // tcId 158: replaced r by r + 2**256 (IntegerOverflow).
        { id = 158; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\46\02\21\01\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 159: replaced r by r + 2**320 (IntegerOverflow).
        { id = 159; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\4e\02\29\01\00\00\00\00\00\00\00\00\2b\a3\a8\be\6b\94\d5\ec\80\a6\d9\d1\19\0a\43\6e\ff\e5\0d\85\a1\ee\e8\59\b8\cc\6a\f9\bd\5c\2e\18\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 160: replaced s by s + n (RangeCheck).
        { id = 160; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\46\02\21\01\b3\29\f4\78\a2\bb\d0\a6\c3\84\ee\14\93\b1\f5\18\27\6e\0e\4a\53\75\92\8d\6f\cd\16\0c\11\cb\6d\2c\02\21\00\b3\29\f4\79\a2\bb\d0\a5\c3\84\ee\14\93\b1\f5\18\6a\87\13\9c\ac\5d\f4\08\7c\13\4b\49\15\68\47\db"; compact = null; valid = false },
        // tcId 168: Signature with special case values r=0 and s=0 (InvalidSignature).
        { id = 168; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\06\02\01\00\02\01\00"; compact = null; valid = false },
        // tcId 170: Signature with special case values r=0 and s=-1 (InvalidSignature).
        { id = 170; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\06\02\01\00\02\01\ff"; compact = null; valid = false },
        // tcId 204: Signature with special case values r=n - 1 and s=n - 1 (InvalidSignature).
        { id = 204; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\46\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; compact = ?"\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; valid = false },
        // tcId 232: Signature encoding contains incorrect types: r=0, s=0.25 (InvalidTypesInSignature).
        { id = 232; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\08\02\01\00\09\03\80\fe\01"; compact = null; valid = false },
        // tcId 295: Edge case for Shamir multiplication (EdgeCaseShamirMultiplication).
        { id = 295; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\70\23\9d\d8\77\f7\c9\44\c4\22\f4\4d\ea\4e\d1\a5\2f\26\27\41\6f\af\2f\07\2f\a5\0c\77\2e\d6\f8\07"; der = "\30\44\02\20\64\a1\aa\b5\00\0d\0e\80\4f\3e\2f\c0\2b\de\e9\be\8f\f3\12\33\4e\2b\a1\6d\11\54\7c\97\71\1c\89\8e\02\20\6a\f0\15\97\1c\c3\0b\e6\d1\a2\06\d4\e0\13\e0\99\77\72\a2\f9\1d\73\28\6f\fd\68\3b\9b\b2\cf\4f\1b"; compact = ?"\64\a1\aa\b5\00\0d\0e\80\4f\3e\2f\c0\2b\de\e9\be\8f\f3\12\33\4e\2b\a1\6d\11\54\7c\97\71\1c\89\8e\6a\f0\15\97\1c\c3\0b\e6\d1\a2\06\d4\e0\13\e0\99\77\72\a2\f9\1d\73\28\6f\fd\68\3b\9b\b2\cf\4f\1b"; valid = true },
        // tcId 296: special case hash (SpecialCaseHash).
        { id = 296; publicKey = "\04\29\27\b1\05\12\ba\e3\ed\dc\fe\46\78\28\12\8b\ad\29\03\26\99\19\f7\08\60\69\c8\c4\df\6c\73\28\38\c7\78\79\64\ea\ac\00\e5\92\1f\b1\49\8a\60\f4\60\67\66\b3\d9\68\50\01\55\8d\1a\97\4e\73\41\51\3e"; digest = "\00\00\00\00\69\0e\d4\26\cc\f1\78\03\eb\e2\bd\08\84\bc\d5\8a\1b\b5\e7\47\7e\ad\36\45\f3\56\e7\a9"; der = "\30\44\02\20\16\ae\a9\64\a2\f6\50\6d\6f\78\c8\1c\91\fc\7e\8b\de\d7\d3\97\73\84\48\de\1e\19\a0\ec\58\0b\f2\66\02\20\25\2c\d7\62\13\0c\66\67\cf\e8\b7\bc\47\d2\7d\78\39\1e\8e\80\c5\78\d1\cd\38\c3\ff\03\3b\e9\28\e9"; compact = ?"\16\ae\a9\64\a2\f6\50\6d\6f\78\c8\1c\91\fc\7e\8b\de\d7\d3\97\73\84\48\de\1e\19\a0\ec\58\0b\f2\66\25\2c\d7\62\13\0c\66\67\cf\e8\b7\bc\47\d2\7d\78\39\1e\8e\80\c5\78\d1\cd\38\c3\ff\03\3b\e9\28\e9"; valid = true },
        // tcId 350: k*G has a large x-coordinate (ArithmeticError).
        { id = 350; publicKey = "\04\0a\d9\95\00\28\8d\46\69\40\03\1d\72\a9\f5\44\5a\4d\43\78\46\40\85\5b\f0\a6\98\74\d2\de\5f\e1\03\c5\01\1e\6e\f2\c4\2d\cd\50\d5\d3\d2\9f\99\ae\6e\ba\2c\80\c9\24\4f\4c\54\22\f0\97\9f\f0\c3\ba\5e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\35\02\10\43\19\05\53\58\e8\61\7b\0c\46\35\3d\03\9c\da\ab\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\43\19\05\53\58\e8\61\7b\0c\46\35\3d\03\9c\da\ab\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = true },
        // tcId 351: r too large (ArithmeticError).
        { id = 351; publicKey = "\04\0a\d9\95\00\28\8d\46\69\40\03\1d\72\a9\f5\44\5a\4d\43\78\46\40\85\5b\f0\a6\98\74\d2\de\5f\e1\03\c5\01\1e\6e\f2\c4\2d\cd\50\d5\d3\d2\9f\99\ae\6e\ba\2c\80\c9\24\4f\4c\54\22\f0\97\9f\f0\c3\ba\5e"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\46\02\21\00\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fc\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = null; valid = false },
        // tcId 352: r,s are large (ArithmeticError).
        { id = 352; publicKey = "\04\ab\05\fd\9d\0d\e2\6b\9c\e6\f4\81\96\52\d9\fc\69\19\3d\0a\a3\98\f0\fb\a8\01\3e\09\c5\82\20\45\54\19\23\52\71\22\8c\78\67\59\09\5d\12\b7\5a\f0\69\2d\d4\10\3f\19\f6\a8\c3\2f\49\43\5a\1e\9b\8d\45"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\46\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4f\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4f\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = true },
        // tcId 355: small r and s (SmallRandS, ArithmeticError).
        { id = 355; publicKey = "\04\a7\1a\f6\4d\e5\12\6a\4a\4e\02\b7\92\2d\66\ce\94\15\ce\88\a4\c9\d2\55\14\d9\10\82\c8\72\5a\c9\57\5d\47\72\3c\8f\be\58\0b\b3\69\fe\c9\c2\66\5d\8e\30\a4\35\b9\93\26\45\48\2e\7c\9f\11\e8\72\29\6b"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\06\02\01\05\02\01\01"; compact = ?"\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\05\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; valid = true },
      ];
      for (vector in vectors.values()) { checkVector(vector) };
    })
  };

  public func test_wycheproof_3() : async Test.Metrics {
    Test.test(func() {
      let vectors : [Vector] = [
        // tcId 363: r is larger than n (ArithmeticError).
        { id = 363; publicKey = "\04\d0\3e\b0\99\13\cc\20\c6\a8\d0\07\0f\0d\8d\2a\7f\63\52\7f\af\a4\41\17\fc\e6\bd\1e\f2\aa\4a\e3\c4\6d\5d\f3\f4\5a\c5\8f\a3\34\c6\d1\02\38\1b\31\20\b7\a2\45\56\00\dc\af\f3\d1\a8\45\51\4f\12\bf\46"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\26\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\57\02\01\07"; compact = null; valid = false },
        // tcId 364: s is larger than n (ArithmeticError).
        { id = 364; publicKey = "\04\3a\72\47\62\91\57\11\93\b4\d1\09\b2\c3\7b\59\f2\80\7e\8f\e9\cf\fd\80\4e\ac\de\d9\03\e7\7c\a0\da\59\2d\bc\74\fe\e0\ca\75\08\cc\7b\c2\82\b0\c5\1a\14\32\86\ff\53\c6\01\31\66\8e\7a\09\29\e4\ed\04"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\26\02\01\06\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\75\fb\d8"; compact = null; valid = false },
        // tcId 375: s == 1 (ArithmeticError).
        { id = 375; publicKey = "\04\8a\eb\36\8a\70\27\a4\d6\4a\bd\ea\37\39\0c\0c\1d\6a\26\f3\99\e2\d9\73\4d\e1\eb\3d\0e\19\37\38\74\05\bd\13\83\47\15\e1\db\ae\9b\87\5c\f0\7b\d5\5e\1b\66\91\c7\f7\53\6a\ef\3b\19\bf\7a\4a\df\57\6d"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\25\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\01\01"; compact = ?"\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; valid = true },
        // tcId 376: s == 0 (ArithmeticError).
        { id = 376; publicKey = "\04\8a\eb\36\8a\70\27\a4\d6\4a\bd\ea\37\39\0c\0c\1d\6a\26\f3\99\e2\d9\73\4d\e1\eb\3d\0e\19\37\38\74\05\bd\13\83\47\15\e1\db\ae\9b\87\5c\f0\7b\d5\5e\1b\66\91\c7\f7\53\6a\ef\3b\19\bf\7a\4a\df\57\6d"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\25\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\01\00"; compact = null; valid = false },
        // tcId 377: edge case modular inverse (ModularInverse, ArithmeticError).
        { id = 377; publicKey = "\04\61\72\2e\ab\a7\31\c6\97\c7\a9\ba\4d\0a\fd\bb\57\13\d8\aa\12\b0\ea\b6\01\bb\33\db\af\79\2c\5a\dc\27\2c\d9\93\b2\b6\63\ab\a5\b3\a2\6c\10\11\82\ff\17\86\84\94\5e\83\87\9e\71\59\8b\95\fe\64\7d\fc"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\20\02\f6\76\96\9f\45\1a\8c\ca\fa\4c\4f\09\79\18\10\e6\d6\32\db\d6\0b\1d\55\40\f3\28\4f\be\18\89\b0"; compact = ?"\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\f6\76\96\9f\45\1a\8c\ca\fa\4c\4f\09\79\18\10\e6\d6\32\db\d6\0b\1d\55\40\f3\28\4f\be\18\89\b0"; valid = true },
        // tcId 392: point at infinity during verify (PointDuplication, ArithmeticError).
        { id = 392; publicKey = "\04\b5\33\d4\69\5d\d5\b8\c5\e0\77\57\e5\5e\6e\51\6f\7e\2c\88\fa\02\39\e2\3f\60\e8\ec\07\dd\70\f2\87\1b\13\4e\e5\8c\c5\83\27\84\56\86\3f\33\c3\a8\5d\88\1f\7d\4a\39\85\01\43\e2\9d\4e\af\00\9a\fe\47"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a8\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70"; compact = ?"\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a8\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70"; valid = false },
        // tcId 393: edge case for signature malleability (ArithmeticError).
        { id = 393; publicKey = "\04\f5\0d\37\1b\91\bf\b1\d7\d1\4e\13\23\52\3b\c3\aa\8c\bf\2c\57\f9\e2\84\de\62\8c\8b\45\36\78\7b\86\f9\4a\d8\87\ac\94\d5\27\24\7c\d2\e7\d0\c8\b1\29\1c\55\3c\97\30\40\53\80\b1\4c\bb\20\9f\5f\a2\dd"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a9\02\20\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a8"; compact = ?"\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a9\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a8"; valid = true },
        // tcId 394: edge case for signature malleability (ArithmeticError).
        { id = 394; publicKey = "\04\68\ec\6e\29\8e\af\e1\65\39\15\6c\e5\7a\14\b0\4a\70\47\c2\21\ba\fc\3a\58\2e\ae\b0\d8\57\c4\d9\46\97\be\d1\af\17\85\01\17\fd\b3\9b\23\24\f2\20\a5\69\8e\d1\6c\42\6a\27\33\5b\b3\85\ac\8c\a6\fb\30"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a9\02\20\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a9"; compact = ?"\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a9\7f\ff\ff\ff\80\00\00\00\7f\ff\ff\ff\ff\ff\ff\ff\de\73\7d\56\d3\8b\cf\42\79\dc\e5\61\7e\31\92\a9"; valid = true },
        // tcId 395: u1 == 1 (ArithmeticError).
        { id = 395; publicKey = "\04\69\da\03\64\73\4d\2e\53\0f\ec\e9\40\19\26\5f\ef\b7\81\a0\f1\b0\8f\6c\88\97\bd\f6\55\79\27\c8\b8\66\d2\d3\c7\dc\d5\18\b2\3d\72\69\60\f0\69\ad\71\a9\33\d8\6e\f8\ab\bc\ce\8b\20\f7\1e\2a\84\70\02"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\45\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\21\00\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; compact = ?"\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; valid = true },
        // tcId 396: u1 == n - 1 (ArithmeticError).
        { id = 396; publicKey = "\04\d8\ad\c0\00\23\a8\ed\c0\25\76\e2\b6\3e\3e\30\62\1a\47\1e\2b\23\20\62\01\87\bf\06\7a\1a\c1\ff\32\33\e2\b5\0e\c0\98\07\ac\cb\36\13\1f\ff\95\ed\12\a0\9a\86\b4\ea\96\90\aa\32\86\15\76\ba\23\62\e1"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\20\44\a5\ad\0a\d0\63\6d\9f\12\bc\9e\0a\6b\dd\5e\1c\bc\b0\12\ea\7b\f0\91\fc\ec\15\b0\c4\32\02\d5\2e"; compact = ?"\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\44\a5\ad\0a\d0\63\6d\9f\12\bc\9e\0a\6b\dd\5e\1c\bc\b0\12\ea\7b\f0\91\fc\ec\15\b0\c4\32\02\d5\2e"; valid = true },
        // tcId 397: u2 == 1 (ArithmeticError).
        { id = 397; publicKey = "\04\36\23\ac\97\3c\ed\0a\56\fa\6d\88\2f\03\a7\d5\c7\ed\ca\02\cf\c7\b2\40\1f\ab\36\90\db\e7\5a\b7\85\8d\b0\69\08\e6\4b\28\61\3d\a7\25\7e\73\7f\39\79\3d\a8\e7\13\ba\06\43\b9\2e\9b\b3\25\2b\e7\f8\fe"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70"; compact = ?"\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70"; valid = true },
        // tcId 398: u2 == n - 1 (ArithmeticError).
        { id = 398; publicKey = "\04\cf\04\ea\77\e9\62\25\23\d8\94\b9\3f\f5\2d\c3\02\7b\31\95\95\03\b6\fa\38\90\e5\e0\42\63\f9\22\f1\e8\52\8f\b7\c0\06\b3\98\3c\8b\84\00\e5\7b\4e\d7\17\40\c2\f3\97\54\38\82\11\99\be\de\ae\ca\b2\e9"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\45\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\21\00\aa\aa\aa\aa\00\00\00\00\aa\aa\aa\aa\aa\aa\aa\aa\7d\ef\51\c9\1a\0f\bf\03\4d\26\87\2c\a8\42\18\e1"; compact = ?"\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\aa\aa\aa\aa\00\00\00\00\aa\aa\aa\aa\aa\aa\aa\aa\7d\ef\51\c9\1a\0f\bf\03\4d\26\87\2c\a8\42\18\e1"; valid = true },
        // tcId 427: point duplication during verification (PointDuplication).
        { id = 427; publicKey = "\04\5b\81\2f\d5\21\aa\fa\69\83\5a\84\9c\ce\6f\bd\eb\69\83\b4\42\d2\44\4f\e7\0e\13\4c\02\7f\c4\69\63\83\8a\40\f2\a3\60\92\e9\00\4e\92\d8\d9\40\cf\56\38\55\0c\e6\72\ce\8b\8d\4e\15\eb\a5\49\92\49\e9"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\45\02\20\6f\23\47\ca\b7\dd\76\85\8f\e0\55\5a\c3\bc\99\04\8c\4a\ac\af\df\b6\bc\be\05\ea\6c\42\c4\93\45\69\02\21\00\bb\72\66\60\23\57\93\aa\99\57\a6\1e\76\e0\0c\2c\43\51\09\cf\9a\15\dd\62\4d\53\f4\30\10\47\85\6b"; compact = ?"\6f\23\47\ca\b7\dd\76\85\8f\e0\55\5a\c3\bc\99\04\8c\4a\ac\af\df\b6\bc\be\05\ea\6c\42\c4\93\45\69\bb\72\66\60\23\57\93\aa\99\57\a6\1e\76\e0\0c\2c\43\51\09\cf\9a\15\dd\62\4d\53\f4\30\10\47\85\6b"; valid = true },
      ];
      for (vector in vectors.values()) { checkVector(vector) };
    })
  };

  public func test_wycheproof_4() : async Test.Metrics {
    Test.test(func() {
      let vectors : [Vector] = [
        // tcId 428: duplication bug (PointDuplication).
        { id = 428; publicKey = "\04\5b\81\2f\d5\21\aa\fa\69\83\5a\84\9c\ce\6f\bd\eb\69\83\b4\42\d2\44\4f\e7\0e\13\4c\02\7f\c4\69\63\7c\75\bf\0c\5c\9f\6d\17\ff\b1\6d\27\26\bf\30\a9\c7\aa\f3\1a\8d\31\74\72\b1\ea\14\5a\b6\6d\b6\16"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\45\02\20\6f\23\47\ca\b7\dd\76\85\8f\e0\55\5a\c3\bc\99\04\8c\4a\ac\af\df\b6\bc\be\05\ea\6c\42\c4\93\45\69\02\21\00\bb\72\66\60\23\57\93\aa\99\57\a6\1e\76\e0\0c\2c\43\51\09\cf\9a\15\dd\62\4d\53\f4\30\10\47\85\6b"; compact = ?"\6f\23\47\ca\b7\dd\76\85\8f\e0\55\5a\c3\bc\99\04\8c\4a\ac\af\df\b6\bc\be\05\ea\6c\42\c4\93\45\69\bb\72\66\60\23\57\93\aa\99\57\a6\1e\76\e0\0c\2c\43\51\09\cf\9a\15\dd\62\4d\53\f4\30\10\47\85\6b"; valid = false },
        // tcId 429: point with x-coordinate 0 (ArithmeticError).
        { id = 429; publicKey = "\04\6a\dd\a8\2b\90\26\1b\0f\31\9f\aa\0d\87\86\65\a6\b6\da\49\7f\09\c9\03\17\62\22\c3\4a\cf\ef\72\a6\47\e6\f5\0d\cc\40\ad\5d\9b\59\f7\60\2b\b2\22\fa\d7\1a\41\bf\5e\1f\9d\f4\95\9a\36\4c\62\e4\88\d9"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\25\02\01\01\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70"; compact = ?"\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70"; valid = false },
        // tcId 430: point with x-coordinate 0 (ArithmeticError).
        { id = 430; publicKey = "\04\2f\ca\0d\0a\47\91\4d\e7\7e\d5\6e\7e\cc\c3\27\6a\60\11\20\c6\df\00\69\c8\25\c8\f6\a0\1c\9f\38\20\65\f3\45\0a\1d\17\c6\b2\49\89\a3\9b\eb\1c\7d\ec\fc\a8\38\4f\bd\c2\94\41\8e\5d\80\7b\3c\6e\d7\de"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\45\02\21\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02\20\33\33\33\33\00\00\00\00\33\33\33\33\33\33\33\33\25\c7\cb\bc\54\9e\52\e7\63\f1\f5\5a\32\7a\3a\a9"; compact = null; valid = false },
        // tcId 431: comparison with point at infinity  (ArithmeticError).
        { id = 431; publicKey = "\04\dd\86\d3\b5\f4\a1\3e\85\11\08\3b\78\00\20\81\c5\3f\f4\67\f1\1e\bd\98\a5\1a\63\3d\b7\66\65\d2\50\45\d5\c8\20\0c\89\f2\fa\10\d8\49\34\92\26\d2\1d\8d\fa\ed\6f\f8\d5\cb\3e\1b\7e\17\47\4e\bc\18\f7"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\44\02\20\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\02\20\33\33\33\33\00\00\00\00\33\33\33\33\33\33\33\33\25\c7\cb\bc\54\9e\52\e7\63\f1\f5\5a\32\7a\3a\a9"; compact = ?"\55\55\55\55\00\00\00\00\55\55\55\55\55\55\55\55\3e\f7\a8\e4\8d\07\df\81\a6\93\43\96\54\21\0c\70\33\33\33\33\00\00\00\00\33\33\33\33\33\33\33\33\25\c7\cb\bc\54\9e\52\e7\63\f1\f5\5a\32\7a\3a\a9"; valid = false },
        // tcId 444: public key shares x-coordinate with generator (PointDuplication).
        { id = 444; publicKey = "\04\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\4f\e3\42\e2\fe\1a\7f\9b\8e\e7\eb\4a\7c\0f\9e\16\2b\ce\33\57\6b\31\5e\ce\cb\b6\40\68\37\bf\51\f5"; digest = "\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23"; der = "\30\45\02\21\00\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23\02\20\24\92\49\24\6d\b6\db\6d\db\6d\b6\db\6d\b6\db\6d\ad\45\91\86\85\95\a8\ee\6b\f5\f8\64\ff\7b\e0\c2"; compact = ?"\bb\5a\52\f4\2f\9c\92\61\ed\43\61\f5\94\22\a1\e3\00\36\e7\c3\2b\27\0c\88\07\a4\19\fe\ca\60\50\23\24\92\49\24\6d\b6\db\6d\db\6d\b6\db\6d\b6\db\6d\ad\45\91\86\85\95\a8\ee\6b\f5\f8\64\ff\7b\e0\c2"; valid = false },
        // tcId 448: x-coordinate of the public key has many trailing 0's (EdgeCasePublicKey).
        { id = 448; publicKey = "\04\4f\33\7c\cf\d6\77\26\a8\05\e4\f1\60\0a\e2\84\9d\f3\80\7e\ca\11\73\80\23\9f\bd\81\69\00\00\00\00\ed\9d\ea\12\4c\c8\c3\96\41\64\11\e9\88\c3\0f\42\7e\b5\04\af\43\a3\14\6c\d5\df\7e\a6\06\66\d6\85"; digest = "\2f\77\66\8a\9d\fb\f8\d5\84\8b\9e\eb\4a\71\45\ca\94\c6\ed\92\36\e4\a7\73\f6\dc\af\a5\13\2b\2f\91"; der = "\30\46\02\21\00\d4\34\e2\62\a4\9e\ab\77\81\e3\53\a3\56\5e\48\25\50\dd\0f\d5\de\fa\01\3c\7f\29\74\5e\ff\35\69\f1\02\21\00\9b\0c\0a\93\f2\67\fb\60\52\fd\80\77\be\76\9c\2b\98\95\31\95\d7\bc\10\de\84\42\18\30\5c\6b\a1\7a"; compact = ?"\d4\34\e2\62\a4\9e\ab\77\81\e3\53\a3\56\5e\48\25\50\dd\0f\d5\de\fa\01\3c\7f\29\74\5e\ff\35\69\f1\9b\0c\0a\93\f2\67\fb\60\52\fd\80\77\be\76\9c\2b\98\95\31\95\d7\bc\10\de\84\42\18\30\5c\6b\a1\7a"; valid = true },
        // tcId 451: y-coordinate of the public key has many trailing 0's (EdgeCasePublicKey).
        { id = 451; publicKey = "\04\3c\f0\3d\61\4d\89\39\cf\d4\99\a0\78\73\fa\c2\81\61\8f\06\b8\ff\87\e8\01\5c\3f\49\72\65\00\49\35\84\fa\17\4d\79\1c\72\bf\2c\e3\88\0a\89\60\dd\2a\7c\7a\13\38\a8\2f\85\a9\e5\9c\db\de\80\00\00\00"; digest = "\2f\77\66\8a\9d\fb\f8\d5\84\8b\9e\eb\4a\71\45\ca\94\c6\ed\92\36\e4\a7\73\f6\dc\af\a5\13\2b\2f\91"; der = "\30\44\02\20\66\4e\b7\ee\6d\b8\4a\34\df\3c\86\ea\31\38\9a\54\05\ba\dd\5c\a9\92\31\ff\55\6d\3e\75\a2\33\e7\3a\02\20\59\f3\c7\52\e5\2e\ca\46\13\76\42\49\0a\51\56\0c\e0\ba\dc\67\87\54\b8\f7\2e\51\a2\90\14\26\a1\bd"; compact = ?"\66\4e\b7\ee\6d\b8\4a\34\df\3c\86\ea\31\38\9a\54\05\ba\dd\5c\a9\92\31\ff\55\6d\3e\75\a2\33\e7\3a\59\f3\c7\52\e5\2e\ca\46\13\76\42\49\0a\51\56\0c\e0\ba\dc\67\87\54\b8\f7\2e\51\a2\90\14\26\a1\bd"; valid = true },
        // tcId 454: y-coordinate of the public key has many trailing 1's (EdgeCasePublicKey).
        { id = 454; publicKey = "\04\3c\f0\3d\61\4d\89\39\cf\d4\99\a0\78\73\fa\c2\81\61\8f\06\b8\ff\87\e8\01\5c\3f\49\72\65\00\49\35\7b\05\e8\b1\86\e3\8d\41\d3\1c\77\f5\76\9f\22\d5\83\85\ec\c8\57\d0\7a\56\1a\63\24\21\7f\ff\ff\ff"; digest = "\2f\77\66\8a\9d\fb\f8\d5\84\8b\9e\eb\4a\71\45\ca\94\c6\ed\92\36\e4\a7\73\f6\dc\af\a5\13\2b\2f\91"; der = "\30\44\02\20\11\58\a0\8d\29\15\00\b4\ca\be\d3\34\6d\89\1e\ee\57\c1\76\35\6a\26\24\fb\01\1f\8f\bb\f3\46\68\30\02\20\22\8a\8c\48\6a\73\60\06\e0\82\32\5b\85\29\0c\5b\c9\1f\37\8b\75\d4\87\dd\a4\67\98\c1\8f\28\55\19"; compact = ?"\11\58\a0\8d\29\15\00\b4\ca\be\d3\34\6d\89\1e\ee\57\c1\76\35\6a\26\24\fb\01\1f\8f\bb\f3\46\68\30\22\8a\8c\48\6a\73\60\06\e0\82\32\5b\85\29\0c\5b\c9\1f\37\8b\75\d4\87\dd\a4\67\98\c1\8f\28\55\19"; valid = true },
        // tcId 457: x-coordinate of the public key has many trailing 1's (EdgeCasePublicKey).
        { id = 457; publicKey = "\04\28\29\c3\1f\aa\2e\40\0e\34\4e\d9\4b\ca\3f\cd\05\45\95\6e\bc\fe\8a\d0\f6\df\a5\ff\8e\ff\ff\ff\ff\a0\1a\af\af\00\0e\52\58\58\55\af\a7\67\6a\de\28\41\13\09\90\52\df\57\e7\eb\3b\d3\7e\be\b9\22\2e"; digest = "\2f\77\66\8a\9d\fb\f8\d5\84\8b\9e\eb\4a\71\45\ca\94\c6\ed\92\36\e4\a7\73\f6\dc\af\a5\13\2b\2f\91"; der = "\30\45\02\21\00\d8\2a\7c\27\17\26\11\87\c8\e0\0d\8d\f9\63\ff\35\d7\96\ed\ad\36\bc\6e\6b\d1\c9\1c\67\0d\91\05\b4\02\20\3d\ca\bd\da\f8\fc\aa\61\f4\60\3e\7c\ba\c0\f3\c0\35\1e\cd\59\88\ef\b2\3f\68\0d\07\de\bd\13\99\29"; compact = ?"\d8\2a\7c\27\17\26\11\87\c8\e0\0d\8d\f9\63\ff\35\d7\96\ed\ad\36\bc\6e\6b\d1\c9\1c\67\0d\91\05\b4\3d\ca\bd\da\f8\fc\aa\61\f4\60\3e\7c\ba\c0\f3\c0\35\1e\cd\59\88\ef\b2\3f\68\0d\07\de\bd\13\99\29"; valid = true },
        // tcId 460: x-coordinate of the public key is large (EdgeCasePublicKey).
        { id = 460; publicKey = "\04\ff\ff\ff\f9\48\08\1e\6a\04\58\dd\8f\9e\73\8f\26\65\ff\90\59\ad\6a\ac\07\08\31\8c\4c\a9\a7\a4\f5\5a\8a\bc\ba\2d\da\84\74\31\1e\e5\41\49\b9\73\ca\e0\c0\fb\89\55\7a\d0\bf\78\e6\52\9a\16\63\bd\73"; digest = "\2f\77\66\8a\9d\fb\f8\d5\84\8b\9e\eb\4a\71\45\ca\94\c6\ed\92\36\e4\a7\73\f6\dc\af\a5\13\2b\2f\91"; der = "\30\44\02\20\76\64\56\dc\e1\85\7c\90\6f\99\96\af\72\93\39\46\4d\27\e9\d9\8e\dc\2d\0e\3b\76\02\97\06\74\21\f6\02\20\40\23\85\ec\ad\ae\0d\80\81\dc\ca\f5\d1\90\37\ec\4e\55\37\6e\ce\d6\99\e9\36\46\bf\bb\f1\9d\0b\41"; compact = ?"\76\64\56\dc\e1\85\7c\90\6f\99\96\af\72\93\39\46\4d\27\e9\d9\8e\dc\2d\0e\3b\76\02\97\06\74\21\f6\40\23\85\ec\ad\ae\0d\80\81\dc\ca\f5\d1\90\37\ec\4e\55\37\6e\ce\d6\99\e9\36\46\bf\bb\f1\9d\0b\41"; valid = true },
        // tcId 463: x-coordinate of the public key is small (EdgeCasePublicKey).
        { id = 463; publicKey = "\04\00\00\00\03\fa\15\f9\63\94\9d\5f\03\a6\f5\c7\f8\6f\9e\00\15\ee\b2\3a\eb\bf\f1\17\39\37\ba\74\8e\10\99\87\20\70\e8\e8\7c\55\5f\a1\36\59\cc\a5\d7\fa\dc\fc\b0\02\3e\a8\89\54\8c\a4\8a\f2\ba\7e\71"; digest = "\2f\77\66\8a\9d\fb\f8\d5\84\8b\9e\eb\4a\71\45\ca\94\c6\ed\92\36\e4\a7\73\f6\dc\af\a5\13\2b\2f\91"; der = "\30\46\02\21\00\b7\c8\14\57\d4\ae\b6\aa\65\95\70\98\56\9f\04\79\71\0a\d7\f6\59\5d\58\74\c3\5a\93\d1\2a\5d\d4\c7\02\21\00\b7\96\1a\0b\65\28\78\c2\d5\68\06\9a\43\2c\a1\8a\1a\91\99\f2\ca\57\4d\ad\4b\9e\3a\05\c0\a1\cd\b3"; compact = ?"\b7\c8\14\57\d4\ae\b6\aa\65\95\70\98\56\9f\04\79\71\0a\d7\f6\59\5d\58\74\c3\5a\93\d1\2a\5d\d4\c7\b7\96\1a\0b\65\28\78\c2\d5\68\06\9a\43\2c\a1\8a\1a\91\99\f2\ca\57\4d\ad\4b\9e\3a\05\c0\a1\cd\b3"; valid = true },
        // tcId 466: y-coordinate of the public key is small (EdgeCasePublicKey).
        { id = 466; publicKey = "\04\bc\bb\29\14\c7\9f\04\5e\aa\6e\cb\bc\61\28\16\b3\be\5d\2d\67\96\70\7d\81\25\e9\f8\51\c1\8a\f0\15\00\00\00\00\13\52\bb\4a\0f\a2\ea\4c\ce\b9\ab\63\dd\68\4a\de\5a\11\27\bc\f3\00\a6\98\a7\19\3b\c2"; digest = "\2f\77\66\8a\9d\fb\f8\d5\84\8b\9e\eb\4a\71\45\ca\94\c6\ed\92\36\e4\a7\73\f6\dc\af\a5\13\2b\2f\91"; der = "\30\44\02\20\31\23\04\28\40\55\60\dc\b8\8f\b5\a6\46\83\6a\ea\9b\23\a2\3d\d9\73\dc\be\80\14\c8\7b\8b\20\eb\07\02\20\0f\93\44\d6\e8\12\ce\16\66\46\74\76\94\a4\1b\0a\af\97\37\4e\19\f3\c5\fb\8b\d7\ae\3d\9b\d0\be\ff"; compact = ?"\31\23\04\28\40\55\60\dc\b8\8f\b5\a6\46\83\6a\ea\9b\23\a2\3d\d9\73\dc\be\80\14\c8\7b\8b\20\eb\07\0f\93\44\d6\e8\12\ce\16\66\46\74\76\94\a4\1b\0a\af\97\37\4e\19\f3\c5\fb\8b\d7\ae\3d\9b\d0\be\ff"; valid = true },
        // tcId 469: y-coordinate of the public key is large (EdgeCasePublicKey).
        { id = 469; publicKey = "\04\bc\bb\29\14\c7\9f\04\5e\aa\6e\cb\bc\61\28\16\b3\be\5d\2d\67\96\70\7d\81\25\e9\f8\51\c1\8a\f0\15\ff\ff\ff\fe\ec\ad\44\b6\f0\5d\15\b3\31\46\54\9c\22\97\b5\22\a5\ee\d8\43\0c\ff\59\67\58\e6\c4\3d"; digest = "\2f\77\66\8a\9d\fb\f8\d5\84\8b\9e\eb\4a\71\45\ca\94\c6\ed\92\36\e4\a7\73\f6\dc\af\a5\13\2b\2f\91"; der = "\30\46\02\21\00\d7\d7\0c\58\1a\e9\e3\f6\6d\c6\a4\80\bf\03\7a\e2\3f\8a\1e\4a\21\36\fe\4b\03\aa\69\f0\ca\25\b3\56\02\21\00\89\c4\60\f8\a5\a5\c2\bb\ba\96\2c\8a\3e\e8\33\a4\13\e8\56\58\e6\2a\59\e2\af\41\d9\12\7c\c4\72\24"; compact = ?"\d7\d7\0c\58\1a\e9\e3\f6\6d\c6\a4\80\bf\03\7a\e2\3f\8a\1e\4a\21\36\fe\4b\03\aa\69\f0\ca\25\b3\56\89\c4\60\f8\a5\a5\c2\bb\ba\96\2c\8a\3e\e8\33\a4\13\e8\56\58\e6\2a\59\e2\af\41\d9\12\7c\c4\72\24"; valid = true },
      ];
      for (vector in vectors.values()) { checkVector(vector) };
    })
  };

  public func test_wycheproof_5() : async Test.Metrics {
    Test.test(func() {
      let vectors : [Vector] = [
        // tcId 472: signature with non-minimal SEQUENCE tag (InvalidEncoding).
        { id = 472; publicKey = "\04\04\aa\ec\73\63\57\26\f2\13\fb\8a\9e\64\da\3b\86\32\e4\14\95\a9\44\d0\04\5b\52\2e\ba\72\40\fa\d5\87\d9\31\57\98\aa\a3\a5\ba\01\77\57\87\ce\d0\5e\aa\f7\b4\e0\9f\c8\1d\6d\1a\a5\46\e8\36\5d\52\5d"; digest = "\e3\b0\c4\42\98\fc\1c\14\9a\fb\f4\c8\99\6f\b9\24\27\ae\41\e4\64\9b\93\4c\a4\95\99\1b\78\52\b8\55"; der = "\3f\10\45\02\21\00\b2\92\a6\19\33\9f\6e\56\7a\30\5c\95\1c\0d\cb\cc\42\d1\6e\47\f2\19\f9\e9\8e\76\e0\9d\87\70\b3\4a\02\20\01\77\e6\04\92\c5\a8\24\2f\76\f0\7b\fe\36\61\bd\e5\9e\c2\a1\7c\e5\bd\2d\ab\2a\be\bd\f8\9a\62\e2"; compact = null; valid = false },
        // tcId 473: signature with non-minimal INTEGER tag on r (InvalidEncoding).
        { id = 473; publicKey = "\04\04\aa\ec\73\63\57\26\f2\13\fb\8a\9e\64\da\3b\86\32\e4\14\95\a9\44\d0\04\5b\52\2e\ba\72\40\fa\d5\87\d9\31\57\98\aa\a3\a5\ba\01\77\57\87\ce\d0\5e\aa\f7\b4\e0\9f\c8\1d\6d\1a\a5\46\e8\36\5d\52\5d"; digest = "\e3\b0\c4\42\98\fc\1c\14\9a\fb\f4\c8\99\6f\b9\24\27\ae\41\e4\64\9b\93\4c\a4\95\99\1b\78\52\b8\55"; der = "\30\46\1f\02\21\00\b2\92\a6\19\33\9f\6e\56\7a\30\5c\95\1c\0d\cb\cc\42\d1\6e\47\f2\19\f9\e9\8e\76\e0\9d\87\70\b3\4a\02\20\01\77\e6\04\92\c5\a8\24\2f\76\f0\7b\fe\36\61\bd\e5\9e\c2\a1\7c\e5\bd\2d\ab\2a\be\bd\f8\9a\62\e2"; compact = null; valid = false },
        // tcId 474: signature with non-minimal INTEGER tag on s (InvalidEncoding).
        { id = 474; publicKey = "\04\04\aa\ec\73\63\57\26\f2\13\fb\8a\9e\64\da\3b\86\32\e4\14\95\a9\44\d0\04\5b\52\2e\ba\72\40\fa\d5\87\d9\31\57\98\aa\a3\a5\ba\01\77\57\87\ce\d0\5e\aa\f7\b4\e0\9f\c8\1d\6d\1a\a5\46\e8\36\5d\52\5d"; digest = "\e3\b0\c4\42\98\fc\1c\14\9a\fb\f4\c8\99\6f\b9\24\27\ae\41\e4\64\9b\93\4c\a4\95\99\1b\78\52\b8\55"; der = "\30\46\02\21\00\b2\92\a6\19\33\9f\6e\56\7a\30\5c\95\1c\0d\cb\cc\42\d1\6e\47\f2\19\f9\e9\8e\76\e0\9d\87\70\b3\4a\1f\02\20\01\77\e6\04\92\c5\a8\24\2f\76\f0\7b\fe\36\61\bd\e5\9e\c2\a1\7c\e5\bd\2d\ab\2a\be\bd\f8\9a\62\e2"; compact = null; valid = false },
        // tcId 475: r = 5, x = 5 is valid (ValidSignature).
        { id = 475; publicKey = "\04\26\4d\79\6a\0d\ab\9b\37\6d\34\ee\a6\fe\29\7d\de\1c\7b\73\e5\39\44\bc\96\c8\f1\e8\a6\85\0b\b6\c9\cf\53\08\02\0e\ed\46\0c\64\9d\da\e6\1d\4e\f8\bb\79\95\81\13\f1\06\be\fa\f4\f1\88\76\d1\2a\5e\64"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\26\02\01\05\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\05\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = true },
        // tcId 476: r = 6, x = 5 is invalid (ArithmeticError).
        { id = 476; publicKey = "\04\ad\d7\66\77\e5\4a\92\e7\9b\be\e3\6a\70\e1\75\48\38\27\3e\c4\b3\92\95\e4\01\8a\58\72\90\a7\fc\73\f2\40\d6\25\64\2c\94\3e\61\0d\80\d9\53\c5\c6\b8\a1\27\60\a6\24\ba\3b\90\a0\b7\90\27\55\e1\ae\79"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\26\02\01\06\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = false },
        // tcId 477: r = 5 + n, x = 5 is invalid; r was not reduced mod n (ArithmeticError).
        { id = 477; publicKey = "\04\26\4d\79\6a\0d\ab\9b\37\6d\34\ee\a6\fe\29\7d\de\1c\7b\73\e5\39\44\bc\96\c8\f1\e8\a6\85\0b\b6\c9\cf\53\08\02\0e\ed\46\0c\64\9d\da\e6\1d\4e\f8\bb\79\95\81\13\f1\06\be\fa\f4\f1\88\76\d1\2a\5e\64"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\46\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\56\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = null; valid = false },
        // tcId 478: r = n - 3, x = n - 2 is invalid (ArithmeticError).
        { id = 478; publicKey = "\04\e7\e4\9d\d8\28\12\43\27\44\fe\fe\72\3f\7f\69\66\32\14\ad\1b\85\c0\2b\26\50\b4\ca\03\54\74\3a\32\52\23\c5\1c\41\5f\45\7a\ec\69\cb\01\9b\be\3d\27\58\5b\38\f8\b7\9c\39\df\ea\6c\27\c2\f0\d8\14\6a"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\46\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = false },
        // tcId 479: r = 3, x = n + 3 is the smallest possible x with a reduction (ValidSignature).
        { id = 479; publicKey = "\04\ce\24\c9\90\32\d5\2a\c6\ea\d2\3c\0a\e3\ec\68\ef\41\e5\1a\28\1f\d4\57\80\8c\83\13\6d\7d\cc\e9\0e\8f\7a\15\4b\55\1e\9f\39\c5\92\79\35\7a\a4\91\b2\a6\2b\de\bc\2b\b7\86\13\88\3f\c7\29\36\c0\57\e0"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\26\02\01\03\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = true },
        // tcId 480: r = 4, x = n + 3 is invalid (ArithmeticError).
        { id = 480; publicKey = "\04\c9\81\c7\5d\df\d3\91\03\87\eb\14\70\98\fe\56\58\c4\3a\aa\a3\4c\68\1c\d6\d5\14\b6\ad\5b\6b\aa\6d\14\fb\dd\b5\3a\6e\6d\b1\8e\90\60\2b\c6\0f\2e\73\6d\62\57\65\f7\f2\cc\a4\be\76\f4\ee\cc\f1\2c\18"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\26\02\01\04\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\04\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = false },
        // tcId 481: r = p - n + 5, x = 5 is invalid; r is too large to compare r + n with x (ArithmeticError).
        { id = 481; publicKey = "\04\0e\c5\05\bc\19\b1\4a\43\e0\56\78\cc\cf\07\a4\43\d3\e8\71\a2\e1\9b\68\a4\da\91\85\9a\06\50\f3\24\77\30\0e\4f\64\e9\98\2d\94\df\f5\d2\94\42\8b\b3\7c\c9\be\66\11\7c\ae\9c\38\9d\2d\49\5f\68\b9\87"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\35\02\10\43\19\05\53\58\e8\61\7b\0c\46\35\3d\03\9c\da\b3\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\43\19\05\53\58\e8\61\7b\0c\46\35\3d\03\9c\da\b3\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = false },
        // tcId 482: r = 2^256 - n + 5, x = 5 is invalid; r + n is too large to compare r + n with x, and overflows 2^256 bits (ArithmeticError).
        { id = 482; publicKey = "\04\d4\2c\e2\1e\73\0f\3d\2a\84\e9\49\82\85\74\b4\dc\ee\b7\7d\4f\89\55\67\35\f3\4f\ba\03\02\8e\e3\ed\32\da\f8\bf\d3\f0\a7\a0\82\11\70\84\0f\4e\03\20\56\72\23\86\b3\5d\9b\dd\4f\4f\45\06\96\f4\fb\52"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\42\02\1d\00\ff\ff\ff\ff\00\00\00\00\00\00\00\00\43\19\05\52\58\e8\61\7b\0c\46\35\3d\03\9c\da\b4\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; compact = ?"\00\00\00\00\ff\ff\ff\ff\00\00\00\00\00\00\00\00\43\19\05\52\58\e8\61\7b\0c\46\35\3d\03\9c\da\b4\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4e"; valid = false },
        // tcId 483: s = 2^128 (ValidSignature).
        { id = 483; publicKey = "\04\69\55\a7\2c\0d\ad\4e\d6\03\56\f7\69\26\49\b9\51\fa\8e\a4\74\bf\1c\c9\54\9b\96\c6\8d\e4\78\2d\fa\e0\12\ff\c2\4e\92\c7\2b\e7\1f\f2\62\2e\e7\e5\49\dc\b5\9e\7b\70\8f\69\21\c4\d4\ea\29\51\2e\2a\ba"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\35\02\20\5f\6d\3a\a0\d3\27\c1\37\02\51\3d\42\99\f2\97\ab\18\2f\cf\67\0f\96\29\1f\ab\19\57\2e\7a\6e\01\c4\02\11\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; compact = ?"\5f\6d\3a\a0\d3\27\c1\37\02\51\3d\42\99\f2\97\ab\18\2f\cf\67\0f\96\29\1f\ab\19\57\2e\7a\6e\01\c4\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; valid = true },
        // tcId 484: s = n - 2^128 (ValidSignature).
        { id = 484; publicKey = "\04\69\55\a7\2c\0d\ad\4e\d6\03\56\f7\69\26\49\b9\51\fa\8e\a4\74\bf\1c\c9\54\9b\96\c6\8d\e4\78\2d\fa\e0\12\ff\c2\4e\92\c7\2b\e7\1f\f2\62\2e\e7\e5\49\dc\b5\9e\7b\70\8f\69\21\c4\d4\ea\29\51\2e\2a\ba"; digest = "\09\ca\7e\4e\aa\6e\8a\e9\c7\d2\61\16\71\29\18\48\83\64\4d\07\df\ba\7c\bf\bc\4c\8a\2e\08\36\0d\5b"; der = "\30\45\02\20\5f\6d\3a\a0\d3\27\c1\37\02\51\3d\42\99\f2\97\ab\18\2f\cf\67\0f\96\29\1f\ab\19\57\2e\7a\6e\01\c4\02\21\00\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\fe\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; compact = ?"\5f\6d\3a\a0\d3\27\c1\37\02\51\3d\42\99\f2\97\ab\18\2f\cf\67\0f\96\29\1f\ab\19\57\2e\7a\6e\01\c4\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\fe\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; valid = true },
      ];
      for (vector in vectors.values()) { checkVector(vector) };
    })
  };
}
