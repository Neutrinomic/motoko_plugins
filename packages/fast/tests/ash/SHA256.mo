import Test "mo:test";
import SHA256 "mo:fast/SHA256";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";

persistent actor {
  func pattern(size : Nat) : Blob {
    Blob.fromArray(Array.tabulate<Nat8>(size, func(i) {
      Nat8.fromNat((i * 131 + 17) % 256)
    }))
  };
  func digest(bytes : Blob) : Blob = SHA256.digest(bytes);

  public query func test_nist_known_answers() : async Test.Metrics {
    Test.test(func() {
      assert digest("") == "\e3\b0\c4\42\98\fc\1c\14\9a\fb\f4\c8\99\6f\b9\24\27\ae\41\e4\64\9b\93\4c\a4\95\99\1b\78\52\b8\55";
      assert digest("abc") == "\ba\78\16\bf\8f\01\cf\ea\41\41\40\de\5d\ae\22\23\b0\03\61\a3\96\17\7a\9c\b4\10\ff\61\f2\00\15\ad";
      assert digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == "\24\8d\6a\61\d2\06\38\b8\e5\c0\26\93\0c\3e\60\39\a3\3c\e4\59\64\ff\21\67\f6\ec\ed\d4\19\db\06\c1";
    })
  };

  public func test_binary_padding_and_block_boundaries() : async Test.Metrics {
    Test.test(func() {
      // Fixed independent answers from Python hashlib.sha256, not this plugin.
      // Byte i = (i * 131 + 17) mod 256; includes NUL and every possible byte.
      let vectors : [(Nat, Blob)] = [
      (0, "\e3\b0\c4\42\98\fc\1c\14\9a\fb\f4\c8\99\6f\b9\24\27\ae\41\e4\64\9b\93\4c\a4\95\99\1b\78\52\b8\55"),
      (1, "\4a\64\a1\07\f0\cb\32\53\6e\5b\ce\6c\98\c3\93\db\21\cc\a7\f4\ea\18\7b\a8\c4\dc\a8\b5\1d\4e\a8\0a"),
      (2, "\b2\7f\c0\4e\05\a9\40\67\2b\77\fb\0d\1a\af\6a\1f\6e\36\75\60\3d\a7\8e\67\91\a6\6b\65\23\c4\6f\d4"),
      (3, "\ab\f0\f7\ab\42\23\b8\6b\ba\fb\06\e4\2d\0c\af\0e\88\9d\27\61\9b\94\6d\44\0a\12\8b\b4\05\b7\c5\a3"),
      (7, "\3e\e1\a2\30\6d\13\d6\99\7c\fc\2d\d5\22\77\bf\6e\77\4e\81\90\0c\a5\be\13\6a\1e\04\64\86\84\0a\a5"),
      (15, "\d9\1c\de\49\4d\51\b5\69\99\0c\2f\98\ee\65\c5\12\aa\5d\d8\dd\85\37\a5\cb\cb\17\8e\cc\f4\c6\eb\c3"),
      (16, "\c9\94\2f\16\0d\fb\01\c0\0e\46\72\a6\ee\96\d2\b0\f2\e2\10\b3\5d\12\00\1f\ac\79\cc\8a\45\19\af\da"),
      (31, "\6e\a6\88\5a\ff\3c\2e\1f\19\6a\b8\14\8e\50\e2\4b\02\62\bc\ab\af\ac\4c\84\d3\c6\4c\79\ee\cc\20\19"),
      (32, "\43\59\9e\f3\88\fd\e6\87\ef\93\76\c2\22\e2\71\b7\33\ef\b0\b6\98\2a\78\10\af\4a\0c\bd\5a\00\50\e3"),
      (33, "\49\44\29\bb\37\1f\5d\9f\bd\3d\20\a6\59\86\a8\27\a6\f0\05\9d\ee\b2\8b\15\7d\5a\42\b8\2d\2f\00\b4"),
      (54, "\06\2c\8c\bf\55\8e\f6\11\46\0f\93\7a\f8\cc\06\8e\ae\c0\95\59\9b\7a\b5\d1\af\6d\d4\0f\84\b3\56\cf"),
      (55, "\59\aa\ae\80\b8\e7\95\8f\57\57\b4\ac\92\74\f1\fd\57\ec\0d\c7\aa\83\49\31\91\02\31\67\81\b9\20\06"),
      (56, "\dc\a9\02\d3\14\87\ff\ab\35\7c\e3\6c\c5\ab\c6\94\7f\bb\69\12\7e\c0\4c\46\8b\a5\68\72\68\c4\bf\7c"),
      (57, "\ca\00\42\f1\f8\b6\a0\2b\a5\a3\0a\f1\21\a9\b6\9d\aa\34\b0\7b\b2\2b\2b\32\0c\05\ab\e2\1d\f8\75\a0"),
      (63, "\b8\e6\55\e9\e7\ad\41\3b\96\f0\a3\71\eb\1d\6d\b7\1d\cc\a2\7f\4e\ee\35\89\25\17\cb\e4\bf\aa\6f\9a"),
      (64, "\e5\14\6b\e6\2a\cc\c5\67\09\59\4c\b4\5c\65\1b\36\1d\f9\4f\62\2c\bb\09\b9\1e\a3\ca\7a\20\60\bd\53"),
      (65, "\4b\6c\67\74\f0\cb\cd\77\6a\90\e1\87\b9\49\4e\04\ca\88\0c\0a\fe\3e\a1\c5\ca\d5\1c\8b\bc\b4\1f\74"),
      (95, "\be\c9\3e\3f\ca\6c\43\8e\f3\b1\c6\e5\60\ac\31\44\3c\bc\2c\64\45\67\d0\d7\3e\fe\2b\6d\e6\3e\36\0b"),
      (96, "\21\a6\c2\3f\9d\88\eb\20\5c\f4\66\24\db\b5\f7\8a\39\d3\93\de\fb\7a\eb\84\58\bb\3f\8f\cc\91\5c\80"),
      (111, "\e1\09\96\bd\86\a0\24\f9\6e\eb\80\e4\88\17\68\a8\b1\34\19\68\9a\05\90\b8\3d\d8\55\73\80\ff\a5\13"),
      (112, "\fb\e7\81\43\ad\b8\f8\a8\9b\71\be\02\15\6e\5f\1d\8a\53\6d\03\8c\ef\5b\60\9c\de\6c\c7\93\0a\07\c7"),
      (113, "\e1\f8\b2\1e\1d\05\3d\bc\ce\44\15\a2\25\78\d1\fc\cd\5d\e5\9a\c7\e1\80\11\d8\a6\24\1b\99\7e\a6\31"),
      (127, "\b4\f5\39\8b\f6\18\d7\41\f2\ab\0f\6e\2f\cd\e0\6f\49\49\c2\0d\47\6b\5f\6e\1d\4b\f8\61\8b\c8\97\3a"),
      (128, "\ed\04\5c\7c\31\9e\0c\92\86\e1\de\a2\1c\80\bf\d4\a0\8e\ca\43\e0\2e\13\ee\8a\7a\2c\8b\4b\2b\ae\c9"),
      (129, "\d6\f2\fc\a0\40\7b\3f\98\c9\ce\29\ae\92\a6\cd\f4\89\50\64\50\fd\bb\29\17\2f\6b\18\98\7b\c6\85\db"),
      (255, "\2b\fa\e2\87\35\1d\36\c1\8a\ce\e2\35\5b\16\e4\10\65\e5\73\57\35\d0\19\cc\c8\23\ae\fc\b2\3e\67\d5"),
      (256, "\11\8b\38\10\1a\6d\90\a1\5b\ec\90\7a\04\ac\ac\42\e0\f2\13\be\5d\d3\f0\73\19\67\e0\34\9a\3d\2b\27"),
      (257, "\4c\3b\4c\ec\28\8f\9b\94\33\a4\04\11\c9\fd\1a\a6\09\b6\5c\73\6b\9e\85\f0\21\ad\29\a2\25\d1\99\9a"),
      (511, "\ea\0b\a6\70\98\f6\48\06\71\bd\fc\8e\1a\58\56\97\3b\7d\57\64\ee\17\a2\e5\ce\47\47\9c\7e\d6\e0\4b"),
      (512, "\2e\f0\2e\bd\b7\8d\c5\c7\af\2a\6e\09\ce\32\96\cc\75\a5\7c\a4\c8\80\dd\ed\ed\f4\cb\35\6e\5f\ea\82"),
      (513, "\f2\a4\a4\f8\14\52\39\35\6d\a9\46\6c\8b\e0\ef\3f\65\ce\61\13\47\3f\4f\55\d0\14\04\80\89\bd\54\05"),
      (1023, "\fe\c7\80\6f\55\96\be\60\cc\8d\7f\16\94\fe\c9\37\b3\d7\fe\b1\4c\cd\9b\e4\f6\c7\9f\21\8d\44\f9\41"),
      (1024, "\57\53\83\de\ff\07\75\79\7e\1f\f4\c8\2d\a0\69\14\19\37\c8\43\a8\1c\be\50\95\9a\96\bc\fa\88\14\0e"),
      (1025, "\b4\9a\26\68\49\88\5c\83\7e\42\95\d5\3d\91\dc\87\3f\bd\77\f7\6f\d0\c0\6b\12\ff\4d\a0\4f\e3\e3\c9"),
      (4095, "\d8\d5\da\a4\61\1f\92\af\f2\9d\03\2c\98\76\a1\20\ce\7a\4a\7d\19\e2\c4\98\6b\8c\3c\1a\f6\e8\5c\1a"),
      (4096, "\c7\41\ee\e9\35\80\a3\34\ba\e7\02\20\8e\5c\05\95\d8\e3\2e\b0\7d\56\2c\52\d5\6c\a5\f8\6e\78\f8\a8"),
      (4097, "\6b\82\8a\41\da\bc\57\04\9f\86\a8\a1\b0\ce\ac\3e\41\12\25\8b\23\6a\52\73\95\c8\11\6c\99\42\4f\fd"),
      (65535, "\c6\a1\a8\75\a5\61\60\be\ba\80\d5\23\3c\aa\f8\cc\45\32\78\0b\37\71\58\89\df\1a\dd\7f\c4\7c\82\82"),
      (65536, "\d8\f3\2a\3b\4c\19\5f\65\44\4e\34\2b\0c\61\bd\af\11\48\02\e8\4a\b7\82\1a\1f\88\e3\f6\6e\a1\51\00"),
      (65537, "\65\d8\0b\2b\0f\01\20\bd\a1\62\8b\37\49\98\20\90\e0\58\d2\d9\f4\a5\fa\d1\bc\70\25\0b\49\bc\4e\96"),
      ];
      for ((size, expected) in vectors.vals()) {
        let input = pattern(size);
        let actual = SHA256.digest(input);
        assert actual.size() == 32;
        assert actual == expected;
        assert input == pattern(size);
      };
    })
  };

  public query func test_aliases_and_concrete_callbacks() : async Test.Metrics {
    Test.test(func() {
      let hash = SHA256.digest;
      let operations = { hash };
      func identity<T>(value : T) : T = value;
      let genericAlias = identity(hash);
      let aliases = [hash, genericAlias];
      let input = pattern(32);
      let expected = digest(input);
      assert operations.hash(input) == expected;
      assert aliases[0](input) == expected;
      assert aliases[1](input) == expected;
      let callback : Blob -> Blob = digest;
      let callbacks : [Blob -> Blob] = [callback, func(bytes) { hash(bytes) }];
      assert callbacks[0](input) == expected;
      assert callbacks[1](input) == expected;
      let optionalHash = ?hash;
      switch optionalHash {
        case (?f) assert f(input) == expected;
        case null assert false;
      };
    })
  };

  public query func test_argument_and_callee_evaluated_once() : async Test.Metrics {
    Test.test(func() {
      var order = "";
      let actual = (do { order #= "callee;"; SHA256.digest })(
        do { order #= "argument;"; "abc" : Blob }
      );
      assert order == "callee;argument;";
      assert actual == digest("abc");
    })
  };

  public func test_retained_results_and_million_byte_vector() : async Test.Metrics {
    Test.test(func() {
      let saved = digest("abc");
      let million = Blob.fromArray(Array.repeat<Nat8>(97, 1_000_000));
      assert digest(million) == "\cd\c7\6e\5c\99\14\fb\92\81\a1\c7\e2\84\d7\3e\67\f1\80\9a\48\a4\97\20\0e\04\6d\39\cc\c7\11\2c\d0";
      var i = 0;
      while (i < 256) {
        let next = pattern(i);
        let first = digest(next);
        assert first == digest(next);
        assert saved == digest("abc");
        i += 1;
      };
      assert saved == digest("abc");
      assert million.size() == 1_000_000;
    })
  };
}
