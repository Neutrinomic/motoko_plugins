import P256 "mo:fast/P256";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Prim "mo:⛔";
import Vectors "P256EncodingVectors";

module {
  func concat(a : Blob, b : Blob) : Blob = Blob.fromArray(a.toArray().concat(b.toArray()));
  func prefix(bytes : Blob, size : Nat) : Blob = Blob.fromArray(Array.tabulate<Nat8>(size, func(i) { bytes[i] }));
  func withTag(bytes : Blob, tag : Nat8) : Blob = Blob.fromArray(Array.tabulate<Nat8>(bytes.size(), func(i) { if (i == 0) tag else bytes[i] }));
  func invalidKey(key : Blob) {
    assert P256.convertPublicKey(key, true) == #err(#invalidPublicKey);
    assert P256.convertPublicKey(key, false) == #err(#invalidPublicKey);
    assert P256.verifyPrehash(key, "", "") == #err(#invalidPublicKey);
    switch (P256.preparePublicKey(key)) {
      case (#err(#invalidPublicKey)) {};
      case _ Prim.trap("invalid SEC1 accepted by preparation");
    };
  };

  public func derLengthsAndPadding() {
    // OpenSSL ASN.1 generation supplies exact independent encodings for all
    // lengths 8..72, every scalar byte-width sign threshold, and n/2 boundaries.
    let (longCompact, longDer, _) = Vectors.der[64];
    for ((compact, der, normalized) in Vectors.der.values()) {
      let encoded = P256.signatureToDer(compact);
      assert encoded == #ok der;
      assert P256.signatureFromDer(der) == #ok compact;
      assert P256.normalizeSignature(compact) == #ok normalized;
      assert P256.normalizeSignature(normalized) == #ok normalized;
      assert P256.signatureFromDer(concat(der, "\00")) == #err(#invalidSignature);
      assert P256.signatureFromDer(prefix(der, der.size() - 1)) == #err(#invalidSignature);
      // An intervening exact-capacity result cannot overwrite a short result.
      assert P256.signatureToDer(longCompact) == #ok longDer;
      assert encoded == #ok der;
    };
  };

  public func sec1CanonicalCoordinates() {
    // OpenSSL's decoder supplies Y and membership answers, including both
    // roots for x=0 and values next to n and p. No plugin computes the oracle.
    for ((compressed, expected) in Vectors.sec1.values()) {
      switch expected {
        case null invalidKey(compressed);
        case (?uncompressed) {
          assert P256.convertPublicKey(compressed, false) == #ok uncompressed;
          assert P256.convertPublicKey(uncompressed, true) == #ok compressed;
          assert P256.convertPublicKey(compressed, true) == #ok compressed;
          assert P256.convertPublicKey(uncompressed, false) == #ok uncompressed;
          for (key in [compressed, uncompressed].values()) {
            switch (P256.preparePublicKey(key)) {
              case (#ok prepared) {
                assert P256.verifyPrehashPrepared(prepared, "", "") == #err(#invalidDigest);
              };
              case (#err _) Prim.trap("valid SEC1 rejected by preparation");
            };
            // Valid keys move validation to the digest in either SEC1 form.
            assert P256.verifyPrehash(key, "", "") == #err(#invalidDigest);
          };
        };
      };
    };
  };

  public func sec1TagsAndLengths() {
    let (compressed, expected) = Vectors.sec1[0];
    let uncompressed = switch expected {
      case (?bytes) bytes;
      case null Prim.trap("missing OpenSSL x=0 point");
    };
    var tag = 0;
    while (tag < 256) {
      if (tag != 2 and tag != 3) invalidKey(withTag(compressed, Nat8.fromNat(tag)));
      if (tag != 4) invalidKey(withTag(uncompressed, Nat8.fromNat(tag)));
      tag += 1;
    };
    for (key in [compressed, uncompressed].values()) {
      var size = 0;
      while (size < key.size()) {
        invalidKey(prefix(key, size));
        size += 1;
      };
      invalidKey(concat(key, "\00"));
    };
    // Canonical uncompressed x=0 with y replaced by 0, p, or p+1.
    let field : Blob = "\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff";
    let fieldPlusOne : Blob = "\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00";
    for (y in [Blob.fromArray(Array.repeat<Nat8>(0, 32)), field, fieldPlusOne].values()) {
      invalidKey(concat(prefix(uncompressed, 33), y));
    };
  };
};
