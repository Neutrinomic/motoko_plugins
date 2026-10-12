import Test "mo:test";
import Bech32 "mo:fast/Bech32";
import Segwit "mo:fast/Segwit";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Text "mo:core/Text";

persistent actor {
  // Fixed vectors from BIP173 and BIP350 (BSD-2-Clause):
  // https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki#test-vectors
  // https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki#test-vectors
  // BIP350 supersedes the old v1+ Bech32 address examples in BIP173.
  func checkGenericVectors() {
    let vectors : [(Bech32.Encoding, [Text])] = [
      (#bech32, [
        "A12UEL5L",
        "a12uel5l",
        "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
        "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
        "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
        "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
        "?1ezyfcl",
      ]),
      (#bech32m, [
        "A1LQFN3A",
        "a1lqfn3a",
        "an83characterlonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11sg7hg6",
        "abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx",
        "11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8",
        "split1checkupstagehandshakeupstreamerranterredcaperredlc445v",
        "?1v759aa",
      ]),
    ];
    for ((encoding, examples) in vectors.values()) {
      for (example in examples.values()) {
        switch (Bech32.decode(example)) {
          case (#ok(decoded)) {
            assert decoded.encoding == encoding;
            assert decoded.hrp == Text.toLower(decoded.hrp);
            assert Bech32.encode(decoded.hrp, decoded.data, encoding) == #ok(Text.toLower(example));
            assert Bech32.decode(Text.toUpper(example)) == #ok(decoded);
          };
          case (#err(_)) assert false;
        };
      };
    };
    assert Bech32.decode("A12UEL5L") == #ok({ hrp = "a"; data = "" : Blob; encoding = #bech32 });
    assert Bech32.decode("A1LQFN3A") == #ok({ hrp = "a"; data = "" : Blob; encoding = #bech32m });
    assert Bech32.decode("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw") == #ok({
      hrp = "abcdef";
      data = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(i) }));
      encoding = #bech32;
    });
    assert Bech32.decode("abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx") == #ok({
      hrp = "abcdef";
      data = Blob.fromArray(Array.tabulate<Nat8>(32, func(i) { Nat8.fromNat(31 - i) }));
      encoding = #bech32m;
    });
  };

  func checkGenericInvalid() {
    // The 0x80 and 0xFF byte vectors are represented by their Unicode code points:
    // Motoko Text is valid UTF-8, so raw invalid UTF-8 cannot be a Text argument.
    let invalid : [Text] = [
      " 1nwldj5", "\7f1axkwrx", "\u{80}1eym55h",
      "an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx",
      "pzry9x0s0muk", "1pzry9x0s0muk", "x1b4n0q5v", "li1dgmt3",
      "de1lg7wt\u{ff}", "A1G7SGD8", "10a06t8", "1qzzfhee",
      " 1xj0phk", "\7f1g6xzxy", "\u{80}1vctc34",
      "an84characterslonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11d6pts4",
      "qyrz8wqd2c9m", "1qyrz8wqd2c9m", "y1b0jsk6g", "lt1igcx5c0",
      "in1muywd", "mm1crxm3i", "au1s5cgom", "M1VUXWEZ", "16plkw9", "1p2gdwpf",
      "", "a", "a1", "a12uel5L", "a1LQFN3A", "\00a12uel5l", "é1ezyfcl", "😀1ezyfcl",
    ];
    for (example in invalid.values()) {
      switch (Bech32.decode(example)) { case (#err(_)) {}; case (#ok(_)) assert false };
    };
    assert Bech32.decode("a12uel5L") == #err(#mixedCase);
    assert Bech32.decode("x1b4n0q5v") == #err(#invalidCharacter);
    assert Bech32.decode("a12uel5q") == #err(#invalidChecksum);
  };

  func repeated(text : Text, count : Nat) : Text {
    var value = "";
    var i = 0;
    while (i < count) { value #= text; i += 1 };
    value
  };

  func checkEncodeBounds() {
    assert Bech32.encode("A", "", #bech32) == #ok("a12uel5l");
    assert Bech32.encode("A", "", #bech32m) == #ok("a1lqfn3a");
    for (hrp in ["", " ", "a b", "\00", "\7f", "é", "😀"].values()) {
      switch (Bech32.encode(hrp, "", #bech32)) { case (#err(_)) {}; case (#ok(_)) assert false };
    };
    assert Bech32.encode("aA", "", #bech32) == #err(#mixedCase);
    assert Bech32.encode("a", "\20", #bech32) == #err(#invalidData);
    assert Bech32.encode("a", "\ff", #bech32m) == #err(#invalidData);
    for (encoding in [#bech32, #bech32m].values()) {
      let hrp = repeated("a", 83);
      switch (Bech32.encode(hrp, "", encoding)) {
        case (#ok(encoded)) { assert encoded.size() == 90; assert Bech32.decode(encoded) == #ok({ hrp; data = "" : Blob; encoding }) };
        case (#err(_)) assert false;
      };
      assert Bech32.encode(hrp, "\00", encoding) == #err(#invalidLength);
      switch (Bech32.encode(repeated("a", 84), "", encoding)) { case (#err(_)) {}; case (#ok(_)) assert false };
      let data = Blob.fromArray(Array.repeat<Nat8>(31, 82));
      switch (Bech32.encode("a", data, encoding)) {
        case (#ok(encoded)) { assert encoded.size() == 90; assert Bech32.decode(encoded) == #ok({ hrp = "a"; data; encoding }) };
        case (#err(_)) assert false;
      };
      assert Bech32.encode("a", Blob.fromArray(Array.repeat<Nat8>(0, 83)), encoding) == #err(#invalidLength);
      // Every printable ASCII HRP byte, including the separator, is permitted.
      let printable = Text.fromIter(Array.tabulate<Char>(94, func(i) { Char.fromNat32(Nat32.fromNat(i + 33)) }).values());
      for (c in printable.chars()) {
        let one = Text.fromChar(c);
        switch (Bech32.encode(one, "\00\1f", encoding)) {
          case (#ok(encoded)) { assert Bech32.decode(encoded) == #ok({ hrp = Text.toLower(one); data = "\00\1f" : Blob; encoding }) };
          case (#err(_)) assert false;
        };
      };
    };
  };

  func checkConvertBits() {
    // Hand-derived MSB-first grouping, independent of the native implementation.
    assert Bech32.convertBits("", 8, 5, true) == #ok("" : Blob);
    assert Bech32.convertBits("\ff", 8, 5, true) == #ok("\1f\1c" : Blob);
    assert Bech32.convertBits("\1f\1c", 5, 8, false) == #ok("\ff" : Blob);
    assert Bech32.convertBits("\00\ff", 8, 5, true) == #ok("\00\03\1f\10" : Blob);
    assert Bech32.convertBits("\00\03\1f\10", 5, 8, false) == #ok("\00\ff" : Blob);
    assert Bech32.convertBits("\00\00", 5, 8, false) == #ok("\00" : Blob);
    assert Bech32.convertBits("\ff\00", 8, 4, false) == #ok("\0f\0f\00\00" : Blob);
    assert Bech32.convertBits("\01\00\01\00\01\00\01\00", 1, 8, false) == #ok("\aa" : Blob);
    assert Bech32.convertBits("\00\01\02\03", 2, 8, false) == #ok("\1b" : Blob);
    assert Bech32.convertBits("\00", 8, 5, false) == #ok("\00" : Blob);
    assert Bech32.convertBits("\1f\1c", 5, 8, true) == #ok("\ff\00" : Blob);
    assert Bech32.convertBits("\07\07\07\07\07", 3, 5, false) == #ok("\1f\1f\1f" : Blob);
    assert Bech32.convertBits("\07\00", 3, 5, false) == #ok("\1c" : Blob);
    assert Bech32.convertBits("\07\01", 3, 5, false) == #err(#invalidPadding);
    assert Bech32.convertBits("\7f", 7, 3, true) == #ok("\07\07\04" : Blob);
    assert Bech32.convertBits("\7e", 7, 3, false) == #ok("\07\07" : Blob);
    assert Bech32.convertBits("\00", 5, 8, false) == #err(#invalidPadding);
    assert Bech32.convertBits("\00\01", 5, 8, false) == #err(#invalidPadding);
    assert Bech32.convertBits("\1f\1d", 5, 8, false) == #err(#invalidPadding);
    assert Bech32.convertBits("\ff", 8, 5, false) == #err(#invalidPadding);
    assert Bech32.convertBits("\f8", 8, 5, false) == #ok("\1f" : Blob);
    assert Bech32.convertBits("\20", 5, 8, true) == #err(#invalidData);
    assert Bech32.convertBits("\02", 1, 8, true) == #err(#invalidData);
    for (width in ([0, 9, 255] : [Nat8]).values()) {
      assert Bech32.convertBits("", width, 8, true) == #err(#invalidBitWidth);
      assert Bech32.convertBits("", 8, width, false) == #err(#invalidBitWidth);
    };
    // A multiple of target-width input symbols gives exact grouping in both
    // directions for every pair of widths, without ambiguous zero padding.
    var source : Nat8 = 1;
    while (source <= 8) {
      var target : Nat8 = 1;
      while (target <= 8) {
        assert Bech32.convertBits("", source, target, true) == #ok("" : Blob);
        assert Bech32.convertBits("", source, target, false) == #ok("" : Blob);
        let modulus = 2 ** Nat8.toNat(source);
        if (source < 8) {
          assert Bech32.convertBits(Blob.fromArray([0, Nat8.fromNat(modulus)]), source, target, true) == #err(#invalidData);
        };
        let input = Blob.fromArray(Array.tabulate<Nat8>(Nat8.toNat(target) * 8, func(i) { Nat8.fromNat((i * 131 + 17) % modulus) }));
        switch (Bech32.convertBits(input, source, target, true)) {
          case (#ok(converted)) {
            switch (Bech32.convertBits(converted, target, source, false)) {
              case (#ok(restored)) assert restored == input;
              case (#err(_)) assert false;
            };
          };
          case (#err(_)) assert false;
        };
        target += 1;
      };
      source += 1;
    };
  };

  func checkSegwitVectors() {
    let vectors : [(Text, Text, Nat8, Blob)] = [
      ("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4", "bc", 0, "\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23\f1\43\3b\d6"),
      ("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7", "tb", 0, "\18\63\14\3c\14\c5\16\68\04\bd\19\20\33\56\da\13\6c\98\56\78\cd\4d\27\a1\b8\c6\32\96\04\90\32\62"),
      ("bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kt5nd6y", "bc", 1, "\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23\f1\43\3b\d6\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23\f1\43\3b\d6"),
      ("BC1SW50QGDZ25J", "bc", 16, "\75\1e"),
      ("bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs", "bc", 2, "\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23"),
      ("tb1qqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesrxh6hy", "tb", 0, "\00\00\00\c4\a5\ca\d4\62\21\b2\a1\87\90\5e\52\66\36\2b\99\d5\e9\1c\6c\e2\4d\16\5d\ab\93\e8\64\33"),
      ("tb1pqqqqp399et2xygdj5xreqhjjvcmzhxw4aywxecjdzew6hylgvsesf3hn0c", "tb", 1, "\00\00\00\c4\a5\ca\d4\62\21\b2\a1\87\90\5e\52\66\36\2b\99\d5\e9\1c\6c\e2\4d\16\5d\ab\93\e8\64\33"),
      ("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0", "bc", 1, "\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98"),
    ];
    for ((address, hrp, version, program) in vectors.values()) {
      assert Segwit.decode(address) == #ok({ hrp; version; program });
      assert Segwit.decode(Text.toUpper(address)) == #ok({ hrp; version; program });
      assert Segwit.encode(hrp, version, program) == #ok(Text.toLower(address));
      assert Segwit.encode(Text.toUpper(hrp), version, program) == #ok(Text.toLower(address));
    };
    // HRP selection is the application's responsibility. The generic Segwit
    // module deliberately accepts the BIP network-mismatch examples as "tc".
    assert Segwit.decode("tc1qw508d6qejxtdg4y5r3zarvary0c5xw7kg3g4ty") == #ok({
      hrp = "tc"; version = 0 : Nat8; program = "\75\1e\76\e8\19\91\96\d4\54\94\1c\45\d1\b3\a3\23\f1\43\3b\d6" : Blob;
    });
    assert Segwit.decode("tc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq5zuyut") == #ok({
      hrp = "tc"; version = 1 : Nat8; program = "\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98" : Blob;
    });
  };

  func checkSegwitInvalid() {
    let wrongEncoding = [
      "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqh2y7hd",
      "tb1z0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqglt7rf",
      "BC1S0XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ54WELL",
      "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kemeawh",
      "tb1q0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq24jc47",
      // Superseded BIP173 v1+ examples must now be rejected.
      "bc1pw508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7k7grplx",
      "BC1SW50QA3JX3S", "bc1zw508d6qejxtdg4y5r3zarvaryvg6kdaj",
    ];
    for (address in wrongEncoding.values()) {
      assert Segwit.decode(address) == #err(#wrongEncoding);
    };
    let invalid : [(Text, Segwit.Error)] = [
      ("bc1p38j9r5y49hruaue7wxjce0updqjuyyx0kh56v8s25huc6995vvpql3jow4", #invalidCharacter),
      ("BC130XLXVLHEMJA6C4DQV22UAPCTQUPFHLXM9H8Z3K2E72Q4K9HCZ7VQ7ZWS8R", #invalidWitnessVersion),
      ("bc1pw5dgrnzv", #invalidWitnessProgram),
      ("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v8n0nx0muaewav253zgeav", #invalidWitnessProgram),
      ("BC1QR508D6QEJXTDG4Y5R3ZARVARYV98GJ9P", #invalidWitnessProgram),
      ("tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vq47Zagq", #mixedCase),
      ("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7v07qwwzcrf", #invalidPadding),
      ("tb1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vpggkg4j", #invalidPadding),
      ("bc1gmk9yu", #invalidWitnessVersion),
      ("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5", #invalidChecksum),
      ("BC13W508D6QEJXTDG4Y5R3ZARVARY0C5XW7KN40WF2", #invalidWitnessVersion),
      ("bc1rw5uspcuh", #invalidWitnessProgram),
      ("bc10w508d6qejxtdg4y5r3zarvary0c5xw7kw508d6qejxtdg4y5r3zarvary0c5xw7kw5rljs90", #invalidWitnessProgram),
      ("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sL5k7", #mixedCase),
      ("bc1zw508d6qejxtdg4y5r3zarvaryvqyzf3du", #invalidPadding),
      ("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3pjxtptv", #invalidPadding),
    ];
    for ((address, error) in invalid.values()) { assert Segwit.decode(address) == #err(error) };
  };

  func checkSegwitBounds() {
    let sizes = [0, 1, 2, 19, 20, 21, 31, 32, 33, 39, 40, 41];
    var version : Nat8 = 0;
    while (version <= 16) {
      for (size in sizes.values()) {
        let program = Blob.fromArray(Array.tabulate<Nat8>(size, func(i) { Nat8.fromNat((i * 131 + 17) % 256) }));
        let valid = size >= 2 and size <= 40 and (version != 0 or size == 20 or size == 32);
        switch (Segwit.encode("bcrt", version, program)) {
          case (#ok(address)) {
            assert valid;
            assert Segwit.decode(address) == #ok({ hrp = "bcrt"; version; program });
            switch (Bech32.decode(address)) {
              case (#ok(decoded)) assert decoded.encoding == (if (version == 0) #bech32 else #bech32m);
              case (#err(_)) assert false;
            };
          };
          case (#err(error)) { assert not valid; assert error == #invalidWitnessProgram };
        };
      };
      version += 1;
    };
    // Exact generic-HRP total-size bounds (90 accepted, 91 rejected).
    for ((size, hrpLength) in ([(40, 18), (2, 78)] : [(Nat, Nat)]).values()) {
      let program = Blob.fromArray(Array.repeat<Nat8>(0, size));
      let hrp = repeated("a", hrpLength);
      switch (Segwit.encode(hrp, 1, program)) {
        case (#ok(address)) {
          assert address.size() == 90;
          assert Segwit.decode(address) == #ok({ hrp; version = 1 : Nat8; program });
        };
        case (#err(_)) assert false;
      };
      assert Segwit.encode(hrp # "a", 1, program) == #err(#invalidLength);
    };
    for (invalid in ([17, 31, 32, 255] : [Nat8]).values()) {
      assert Segwit.encode("bc", invalid, "\00\00") == #err(#invalidWitnessVersion);
    };
  };

  func checkCallbacksAndRetention() {
    let encode = Bech32.encode;
    let decode = Bech32.decode;
    let encoders = [encode];
    let decoders = [decode];
    assert encoders[0]("a", "", #bech32) == #ok("a12uel5l");
    assert decoders[0]("a1lqfn3a") == #ok({ hrp = "a"; data = "" : Blob; encoding = #bech32m });
    var order = "";
    assert (do { order #= "callee;"; Bech32.encode })(
      do { order #= "hrp;"; "a" },
      do { order #= "data;"; "" : Blob },
      do { order #= "encoding;"; #bech32 }
    ) == #ok("a12uel5l");
    assert order == "callee;hrp;data;encoding;";
    let saved = Bech32.decode("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw");
    var i = 0;
    while (i < 128) {
      let bytes = Blob.fromArray(Array.repeat<Nat8>(Nat8.fromNat(i), 32));
      switch (Segwit.encode("bc", 1, bytes)) {
        case (#ok(address)) assert Segwit.decode(address) == #ok({ hrp = "bc"; version = 1 : Nat8; program = bytes });
        case (#err(_)) assert false;
      };
      assert saved == Bech32.decode("abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw");
      i += 1;
    };
  };

  public func test_generic_bip173_bip350_vectors() : async Test.Metrics {
    Test.test(checkGenericVectors)
  };

  public func test_generic_invalid_vectors() : async Test.Metrics {
    Test.test(checkGenericInvalid)
  };

  public func test_encode_hrp_and_length_bounds() : async Test.Metrics {
    Test.test(checkEncodeBounds)
  };

  public func test_convert_bits_values_widths_and_padding() : async Test.Metrics {
    Test.test(checkConvertBits)
  };

  public func test_segwit_bip350_vectors() : async Test.Metrics {
    Test.test(checkSegwitVectors)
  };

  public func test_segwit_invalid_vectors_and_checksum_rules() : async Test.Metrics {
    Test.test(checkSegwitInvalid)
  };

  public func test_segwit_versions_and_program_bounds() : async Test.Metrics {
    Test.test(checkSegwitBounds)
  };

  public func test_callbacks_evaluation_and_retained_results() : async Test.Metrics {
    Test.test(checkCallbacksAndRetention)
  };

}
