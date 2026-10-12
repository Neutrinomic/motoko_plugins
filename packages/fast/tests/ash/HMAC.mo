import Test "mo:test";
import HMAC "mo:fast/HMAC";
import Prim "mo:⛔";

persistent actor {
  func pattern(size : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) {
      Prim.natToNat8((i * 131 + 17) % 256)
    }))
  };

  func slice(input : Blob, start : Nat, size : Nat) : Blob {
    let bytes = Prim.blobToArray(input);
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) { bytes[start + i] }))
  };

  func check(actual : Blob, expected : Blob, truncated : Bool) {
    assert (if (truncated) slice(actual, 0, 16) else actual) == expected;
  };

  public func test_rfc4231_all_seven_cases() : async Test.Metrics {
    Test.test(func() {
      // RFC 4231 sections 4.2–4.8, independently cross-checked with Python hmac.
      // https://www.rfc-editor.org/rfc/rfc4231.html
      // Case 5 specifies only the first 16 output bytes; this API returns full MACs.
      let vectors : [(Blob, Blob, Blob, Blob, Bool)] = [
        ("\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b\0b", "\48\69\20\54\68\65\72\65", "\b0\34\4c\61\d8\db\38\53\5c\a8\af\ce\af\0b\f1\2b\88\1d\c2\00\c9\83\3d\a7\26\e9\37\6c\2e\32\cf\f7", "\87\aa\7c\de\a5\ef\61\9d\4f\f0\b4\24\1a\1d\6c\b0\23\79\f4\e2\ce\4e\c2\78\7a\d0\b3\05\45\e1\7c\de\da\a8\33\b7\d6\b8\a7\02\03\8b\27\4e\ae\a3\f4\e4\be\9d\91\4e\eb\61\f1\70\2e\69\6c\20\3a\12\68\54", false),
        ("\4a\65\66\65", "\77\68\61\74\20\64\6f\20\79\61\20\77\61\6e\74\20\66\6f\72\20\6e\6f\74\68\69\6e\67\3f", "\5b\dc\c1\46\bf\60\75\4e\6a\04\24\26\08\95\75\c7\5a\00\3f\08\9d\27\39\83\9d\ec\58\b9\64\ec\38\43", "\16\4b\7a\7b\fc\f8\19\e2\e3\95\fb\e7\3b\56\e0\a3\87\bd\64\22\2e\83\1f\d6\10\27\0c\d7\ea\25\05\54\97\58\bf\75\c0\5a\99\4a\6d\03\4f\65\f8\f0\e6\fd\ca\ea\b1\a3\4d\4a\6b\4b\63\6e\07\0a\38\bc\e7\37", false),
        ("\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa", "\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd\dd", "\77\3e\a9\1e\36\80\0e\46\85\4d\b8\eb\d0\91\81\a7\29\59\09\8b\3e\f8\c1\22\d9\63\55\14\ce\d5\65\fe", "\fa\73\b0\08\9d\56\a2\84\ef\b0\f0\75\6c\89\0b\e9\b1\b5\db\dd\8e\e8\1a\36\55\f8\3e\33\b2\27\9d\39\bf\3e\84\82\79\a7\22\c8\06\b4\85\a4\7e\67\c8\07\b9\46\a3\37\be\e8\94\26\74\27\88\59\e1\32\92\fb", false),
        ("\01\02\03\04\05\06\07\08\09\0a\0b\0c\0d\0e\0f\10\11\12\13\14\15\16\17\18\19", "\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd\cd", "\82\55\8a\38\9a\44\3c\0e\a4\cc\81\98\99\f2\08\3a\85\f0\fa\a3\e5\78\f8\07\7a\2e\3f\f4\67\29\66\5b", "\b0\ba\46\56\37\45\8c\69\90\e5\a8\c5\f6\1d\4a\f7\e5\76\d9\7f\f9\4b\87\2d\e7\6f\80\50\36\1e\e3\db\a9\1c\a5\c1\1a\a2\5e\b4\d6\79\27\5c\c5\78\80\63\a5\f1\97\41\12\0c\4f\2d\e2\ad\eb\eb\10\a2\98\dd", false),
        ("\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c\0c", "\54\65\73\74\20\57\69\74\68\20\54\72\75\6e\63\61\74\69\6f\6e", "\a3\b6\16\74\73\10\0e\e0\6e\0c\79\6c\29\55\55\2b", "\41\5f\ad\62\71\58\0a\53\1d\41\79\bc\89\1d\87\a6", true),
        ("\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa", "\54\65\73\74\20\55\73\69\6e\67\20\4c\61\72\67\65\72\20\54\68\61\6e\20\42\6c\6f\63\6b\2d\53\69\7a\65\20\4b\65\79\20\2d\20\48\61\73\68\20\4b\65\79\20\46\69\72\73\74", "\60\e4\31\59\1e\e0\b6\7f\0d\8a\26\aa\cb\f5\b7\7f\8e\0b\c6\21\37\28\c5\14\05\46\04\0f\0e\e3\7f\54", "\80\b2\42\63\c7\c1\a3\eb\b7\14\93\c1\dd\7b\e8\b4\9b\46\d1\f4\1b\4a\ee\c1\12\1b\01\37\83\f8\f3\52\6b\56\d0\37\e0\5f\25\98\bd\0f\d2\21\5d\6a\1e\52\95\e6\4f\73\f6\3f\0a\ec\8b\91\5a\98\5d\78\65\98", false),
        ("\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa", "\54\68\69\73\20\69\73\20\61\20\74\65\73\74\20\75\73\69\6e\67\20\61\20\6c\61\72\67\65\72\20\74\68\61\6e\20\62\6c\6f\63\6b\2d\73\69\7a\65\20\6b\65\79\20\61\6e\64\20\61\20\6c\61\72\67\65\72\20\74\68\61\6e\20\62\6c\6f\63\6b\2d\73\69\7a\65\20\64\61\74\61\2e\20\54\68\65\20\6b\65\79\20\6e\65\65\64\73\20\74\6f\20\62\65\20\68\61\73\68\65\64\20\62\65\66\6f\72\65\20\62\65\69\6e\67\20\75\73\65\64\20\62\79\20\74\68\65\20\48\4d\41\43\20\61\6c\67\6f\72\69\74\68\6d\2e", "\9b\09\ff\a7\1b\94\2f\cb\27\63\5f\bc\d5\b0\e9\44\bf\dc\63\64\4f\07\13\93\8a\7f\51\53\5c\3a\35\e2", "\e3\7b\6a\77\5d\c8\7d\ba\a4\df\a9\f9\6e\5e\3f\fd\de\bd\71\f8\86\72\89\86\5d\f5\a3\2d\20\cd\c9\44\b6\02\2c\ac\3c\49\82\b1\0d\5e\eb\55\c3\e4\de\15\13\46\76\fb\6d\e0\44\60\65\c9\74\40\fa\8c\6a\58", false),
      ];
      for ((key, message, expected256, expected512, truncated) in vectors.values()) {
        let mac256 = HMAC.sha256(key, message);
        let mac512 = HMAC.sha512(key, message);
        assert mac256.size() == 32;
        assert mac512.size() == 64;
        check(mac256, expected256, truncated);
        check(mac512, expected512, truncated);
        check(HMAC.prepareSha256(key).digest(message), expected256, truncated);
        check(HMAC.prepareSha512(key).digest(message), expected512, truncated);
        let stream256 = HMAC.SHA256(key);
        let stream512 = HMAC.SHA512(key);
        let cut = message.size() / 2;
        stream256.write(slice(message, 0, cut));
        stream512.write(slice(message, 0, cut));
        stream256.write("");
        stream512.write("");
        stream256.write(slice(message, cut, message.size() - cut));
        stream512.write(slice(message, cut, message.size() - cut));
        check(stream256.sum(), expected256, truncated);
        check(stream512.sum(), expected512, truncated);
      };
    })
  };

  public func test_empty_binary_padding_and_key_boundaries() : async Test.Metrics {
    Test.test(func() {
      // Fixed independent Python hmac answers. Covers hash padding transitions,
      // both sides of the 64/128-byte HMAC key-normalization boundary and long keys.
      let vectors : [(Nat, Nat, Blob, Blob)] = [
        (0, 0, "\b6\13\67\9a\08\14\d9\ec\77\2f\95\d7\78\c3\5f\c5\ff\16\97\c4\93\71\56\53\c6\c7\12\14\42\92\c5\ad", "\b9\36\ce\e8\6c\9f\87\aa\5d\3c\6f\2e\84\cb\5a\42\39\a5\fe\50\48\0a\6e\c6\6b\70\ab\5b\1f\4a\c6\73\0c\6c\51\54\21\b3\27\ec\1d\69\40\2e\53\df\b4\9a\d7\38\1e\b0\67\b3\38\fd\7b\0c\b2\22\47\22\5d\47"),
        (0, 1, "\14\fb\a0\52\cd\99\bc\6a\d1\8d\b4\70\45\49\f6\8d\a9\75\ec\a7\1d\76\d4\4f\88\d2\f4\58\f9\c8\14\ae", "\6b\a8\80\a7\d3\b3\aa\ae\4f\2a\d1\7d\92\ce\81\14\5d\1e\dc\9f\ac\61\33\22\ad\c8\c1\7f\e7\a1\ff\67\c5\23\55\fb\4a\22\26\6b\03\32\48\09\ba\29\42\ed\f3\39\fa\8e\fb\9b\b5\96\0b\92\9d\be\98\30\7e\35"),
        (1, 0, "\83\46\cb\db\67\9d\19\fc\35\c0\8d\5a\97\5a\3a\e9\65\27\e7\cd\a0\41\52\2f\9e\19\f8\a8\29\2b\41\ff", "\2e\b2\35\cf\a1\a1\5f\38\a0\ba\ed\33\56\35\ff\a9\2e\4b\2d\23\26\ad\0e\0e\ff\46\8a\e0\7a\ed\be\7f\dc\bd\e8\ea\a3\80\1e\5c\c6\c2\78\1f\b6\17\e9\bc\ea\5c\23\1c\07\23\8b\d4\6e\21\8d\21\47\51\c8\2f"),
        (1, 1, "\e2\1c\b3\72\ad\07\fe\b7\87\4c\29\bf\5e\c4\53\bd\0f\cc\5a\4c\5c\32\dc\0e\13\f5\e3\8b\c5\03\8f\79", "\9b\33\f4\d1\6c\f4\a3\d3\24\0b\cc\05\cb\b6\94\d4\33\97\0d\2c\ba\03\c6\53\05\9f\6b\6d\f2\8d\61\95\b6\fc\9c\62\66\80\0e\ea\5f\53\a9\ed\f3\40\4c\eb\42\67\b2\71\76\ce\1a\da\f4\60\6d\ad\f1\58\fd\42"),
        (63, 55, "\b6\c1\c4\90\fa\1f\5a\62\43\b5\a7\61\b8\41\69\5e\11\ea\01\40\17\a6\fb\fc\b9\21\ba\da\9e\e1\1b\9d", "\e7\7b\89\47\8b\03\68\78\da\1e\bb\a4\75\48\d6\92\d1\57\1b\5f\39\f5\3d\25\0f\e7\fa\34\e5\66\f4\92\dd\a8\62\5a\c9\08\17\29\39\14\2e\88\2b\f9\5d\bd\fd\1b\33\47\de\c0\97\43\86\e9\1b\ba\c7\5c\8a\74"),
        (63, 56, "\ae\37\55\db\5d\e4\e6\a4\2d\c0\27\ae\47\d3\9e\a3\39\91\bf\03\cc\a2\29\2d\98\fc\4c\19\fd\94\08\1d", "\1d\05\7d\2b\49\a7\61\1a\7a\fa\e6\44\0c\5c\f5\97\93\f1\9d\2d\32\2c\d0\e7\9c\2b\dd\af\56\e3\89\d0\4c\d8\19\0a\ba\64\1c\39\c7\98\85\52\ae\8b\24\f2\8c\34\c5\6b\15\7a\8d\1f\02\bc\0d\70\50\49\4f\f5"),
        (64, 63, "\29\3c\f6\df\0b\53\2b\86\00\c3\a0\a4\f2\10\78\ca\bc\f0\5f\dd\bc\91\0b\6a\8c\7c\16\fe\ab\77\ce\b9", "\01\b6\89\6b\4e\76\44\61\a7\9b\39\02\1e\4b\f4\d5\f1\75\7e\4d\be\63\ee\04\89\43\37\39\c9\70\50\c9\23\2d\fa\0e\82\a5\06\45\f0\bf\53\11\96\7b\0f\84\71\44\cd\ac\b9\35\da\61\91\b6\ea\b3\b3\44\0a\b5"),
        (64, 64, "\6c\1e\a9\b8\2d\94\9b\b5\75\b8\07\43\15\5b\1e\64\01\6b\9b\ef\78\1b\34\17\0c\b1\0a\94\77\5e\08\2f", "\c2\53\ed\f4\cb\15\83\6f\05\97\bb\1f\ed\ba\71\97\f9\d0\4a\c9\00\54\e8\77\bf\cf\20\e6\46\50\90\5e\4a\38\05\84\1b\b6\41\db\84\17\af\e9\be\51\d1\0c\ce\6d\ec\d6\3e\c3\53\75\f5\6d\64\7d\ee\c2\0f\27"),
        (64, 65, "\c1\69\36\b8\07\d7\40\a9\99\fd\f1\00\32\6b\ce\c0\da\c9\c2\c2\9c\0a\28\2a\f5\0e\85\48\8e\83\61\e9", "\60\05\1b\9f\e9\c1\78\d5\a3\f2\98\70\86\bf\1c\71\cb\c0\3f\0e\7a\a9\37\37\c6\e4\91\e0\98\d9\78\f6\5f\12\01\2c\c1\49\7f\46\a3\a7\7b\89\11\61\de\5e\15\15\44\a1\e9\a0\1a\a5\4e\86\56\12\1a\11\b0\36"),
        (65, 55, "\50\ad\b8\ae\26\1c\a8\d5\1d\f5\56\9d\cb\73\ac\29\fb\ff\06\0c\06\e0\f4\07\52\93\99\59\5e\fa\b2\77", "\df\e2\b4\f9\22\66\26\16\a7\d1\ab\f2\cf\25\50\84\a6\a3\0f\bc\be\52\bf\23\03\ce\42\6b\c5\82\b1\9c\30\c3\dc\06\7c\26\1a\8e\e2\24\39\78\13\d5\b9\94\ab\4b\20\a5\5b\86\b8\66\f0\7c\08\d4\1c\a0\ca\fc"),
        (65, 56, "\ac\0f\bb\b9\78\1d\8c\aa\45\54\e5\c4\8c\42\0d\de\90\12\62\30\3e\41\2b\9d\76\ff\20\ff\0f\8a\b1\1d", "\bd\f3\4b\7b\87\f8\2c\cc\e7\31\37\6d\ff\b1\1b\1c\0e\bf\0f\e2\3e\cb\d7\b9\0a\e0\1a\d9\cb\e0\74\2d\86\dd\ae\bb\d9\56\b4\4c\7f\ad\9f\34\25\9c\0a\8e\c6\ac\8c\3f\9e\02\92\cc\ab\42\38\cd\50\20\72\b4"),
        (65, 64, "\14\d8\8f\95\99\8d\fb\7c\3f\f7\62\c7\e8\82\79\a2\69\87\34\27\79\cf\40\90\44\06\c8\6d\04\f8\f8\3c", "\3d\89\e8\da\5b\29\ce\5e\55\bb\7a\03\c9\65\45\47\96\3c\5a\10\3a\17\13\d5\35\2f\7e\0f\3f\e9\0c\31\c7\ed\27\5b\34\fc\6c\61\bf\f7\cb\a0\81\0f\48\80\dd\3f\5c\a8\e9\b4\c0\b4\b5\b6\37\bf\36\f8\2a\f1"),
        (65, 65, "\64\a6\36\62\54\99\aa\65\b2\d8\fc\d3\e8\a8\c5\db\a7\36\43\00\f4\ea\df\0e\44\cf\65\c7\93\f7\11\76", "\06\23\7d\ef\24\af\46\4a\be\e0\d7\b2\f5\de\a9\a5\ba\a5\f7\b9\bb\43\30\44\f2\f7\25\1f\64\35\84\04\8f\4c\20\c4\79\fa\12\55\d1\a7\08\96\68\91\e3\38\b0\26\44\51\d1\73\78\b6\ce\b7\a3\bc\16\ff\a5\68"),
        (127, 111, "\9e\8c\b2\0b\c0\8c\cd\13\d7\7a\c2\7c\fa\c2\ac\6e\d9\78\8f\07\54\9d\00\bc\f7\43\93\48\64\0d\de\0f", "\a3\67\be\df\b8\c1\82\df\1e\77\57\d7\b7\2c\94\43\b9\02\77\0a\ee\40\d8\f8\ff\9f\54\bf\a2\b3\0b\88\6d\55\e3\66\9d\02\88\4e\ae\09\67\36\93\c2\5c\93\30\3d\e4\ce\27\23\0c\e8\a9\34\18\94\44\29\28\cf"),
        (127, 112, "\87\6e\c7\5f\7f\b2\04\df\6e\54\d4\1a\7e\a0\6a\35\b4\db\ca\f3\c7\c5\39\ff\dc\8c\7e\78\a0\68\eb\73", "\69\aa\fd\df\dd\10\5a\98\47\ea\b2\e9\72\d2\d7\da\26\ff\4e\24\97\97\08\95\75\7c\5e\dd\67\8e\87\fb\14\3f\48\91\6e\cf\74\13\27\8a\2a\90\9e\85\16\88\5b\e4\98\bd\f0\8b\a5\6e\a4\d9\04\4e\2c\c7\b9\bd"),
        (128, 127, "\50\3e\d0\0c\3a\9b\8f\d1\c2\bd\e8\53\3c\11\52\61\b8\66\22\17\89\b8\06\b8\70\17\45\13\73\cd\03\ca", "\be\10\ff\93\c2\f1\6f\c5\d2\6e\e1\8b\10\d7\9b\65\db\26\c8\dc\53\03\9c\b9\7d\95\ef\38\b9\a4\30\94\68\aa\cc\c6\60\78\16\8d\bb\93\92\ec\8f\f0\ee\6b\2b\8b\d5\61\af\a4\3a\23\db\28\91\41\16\52\73\2e"),
        (128, 128, "\62\4d\48\5f\54\8f\a6\b8\89\4c\96\2c\47\ba\31\1c\18\5f\b6\1d\34\eb\df\15\ae\79\9d\68\b1\fa\82\cc", "\72\ac\41\62\78\68\78\ea\30\5c\e4\b4\4a\30\3e\c6\64\c5\58\2a\8d\1f\5a\c7\5e\6c\e0\76\dc\78\84\b0\f4\a8\38\ba\7b\38\b9\b7\d4\d4\a0\72\23\b3\44\c4\0e\e6\a3\28\d8\da\56\89\c2\48\ee\95\e4\60\bc\b8"),
        (128, 129, "\2e\03\98\c8\d6\cf\b1\0c\a0\bd\d4\3f\6c\35\32\85\d1\4e\84\b9\85\7e\bc\ea\d3\1d\81\56\3f\4f\49\92", "\b5\2a\90\19\f6\16\f5\98\97\a8\b9\26\b0\7d\98\16\cc\7f\bc\a9\41\83\c1\ae\1d\0d\4b\ac\82\be\cc\a1\2d\3c\00\54\e9\6e\01\58\a8\8e\7d\fd\8f\3f\2b\4d\24\a4\63\70\8b\ef\be\b3\69\1e\86\66\63\0b\41\e2"),
        (129, 111, "\11\c6\e4\df\83\6c\68\0f\b5\c8\61\04\18\b8\c8\0a\59\45\26\57\db\17\5c\6b\90\18\ef\09\76\cf\32\65", "\ab\1e\95\1c\11\b8\53\cd\21\94\1c\3a\fc\a0\f9\9d\fc\45\9f\78\06\3a\23\ef\91\ca\09\3d\ca\c4\7a\41\61\cc\2f\4a\1a\22\5a\88\e5\b0\b1\5f\93\e9\ab\01\6a\95\9d\90\3b\ff\27\f3\b4\73\3f\9d\55\af\b0\c6"),
        (129, 112, "\97\f2\2c\45\26\22\20\a6\9b\d0\c6\6f\20\64\2e\67\22\74\dd\3b\ac\5a\cd\3f\0d\44\7a\cf\c7\54\37\1f", "\f1\e6\f8\36\b1\8b\29\7e\7c\47\98\b2\51\b2\1a\55\3c\f3\ec\62\d6\44\43\60\b9\fe\f5\ce\d4\1d\25\6b\fe\15\9c\d6\9d\2d\0d\03\5d\91\8a\51\58\c8\aa\4a\3c\4a\77\0b\19\1e\53\d2\5e\27\f1\98\30\cb\29\a4"),
        (129, 128, "\26\cb\e0\64\bf\f6\98\ec\e7\e3\4e\1f\bf\4c\7f\3e\c8\bf\7a\64\63\9e\6f\71\9b\db\98\4b\2c\4a\e4\84", "\12\84\ab\17\a6\41\3f\00\19\91\41\68\4b\f1\57\6d\ec\78\27\a8\97\5a\58\c1\4c\97\90\11\71\74\cd\01\7b\40\c4\13\32\d9\ba\26\e1\9d\38\fd\f9\42\eb\45\35\03\f0\42\41\91\64\4e\72\36\cf\9a\7a\10\6d\c6"),
        (129, 129, "\72\7b\c9\32\8a\66\6f\e1\56\2c\9f\cd\25\f2\b0\bc\78\fc\ee\91\27\80\bb\7e\86\ed\b0\ec\86\5c\a3\d9", "\3c\0e\3b\58\33\b0\52\15\8d\93\76\cc\7a\11\81\e7\81\a7\75\5a\d1\f7\39\0e\85\e7\5a\2c\af\5f\02\af\12\04\54\6e\e1\4e\28\23\cf\87\35\fe\12\8c\45\1e\4e\cd\c9\5a\99\3e\fd\c2\d7\1c\05\6d\60\b6\8c\65"),
        (131, 255, "\d0\af\ed\4c\94\59\e5\d0\81\76\cc\9b\2a\01\79\74\de\c2\d7\56\19\3f\c9\4f\ec\0b\62\3e\25\ac\b0\ec", "\55\5c\14\9e\a7\c5\04\d1\e8\7c\de\ca\97\27\09\82\5a\3a\2a\82\ad\91\00\05\38\38\69\cd\54\fb\74\24\72\7f\b0\56\7c\5e\f8\4c\f2\0a\f0\35\78\c7\28\7b\b7\a8\ca\46\b9\c4\2e\54\b9\78\f7\b3\f0\f5\2d\5c"),
        (131, 256, "\6e\28\90\1b\6a\e9\ca\f1\7f\f3\82\ac\ac\cc\2a\35\5f\d6\82\38\6b\1e\bf\85\45\c9\90\14\71\93\9b\5c", "\77\cc\dd\32\5e\7f\07\a9\03\72\5d\c0\71\61\5f\09\f5\a8\29\fa\73\3a\4c\5d\cf\eb\f3\13\22\63\83\6c\54\1c\58\d9\96\0f\4b\b9\2e\b8\9c\da\f1\15\2b\8e\e7\6b\7f\71\6a\ca\67\8c\9a\e1\97\ee\6b\5c\bb\ce"),
        (131, 257, "\a0\ee\fd\4f\26\0d\57\3b\16\40\30\d8\6e\4b\b9\c2\47\6c\19\d7\a1\16\91\4c\af\7c\17\9f\83\01\26\95", "\aa\9b\2a\c0\8a\75\a6\a5\63\65\79\a5\80\58\ac\9d\2e\1f\3a\60\ad\0b\fd\54\63\12\37\5f\2c\aa\0c\04\1a\6a\2a\17\97\cf\e9\f6\34\c4\58\7a\99\55\18\62\e2\a1\74\fd\37\5f\49\08\3a\6a\66\4a\6f\5a\09\73"),
        (1024, 4096, "\b6\c3\69\4d\44\92\ff\72\be\0b\7a\af\15\a2\fb\f0\96\ae\13\bb\0a\2a\95\d6\fc\9d\12\82\14\29\bd\79", "\31\c0\2b\3c\4e\68\a2\b7\f3\c8\0c\ee\b5\f7\e9\48\5c\04\f4\34\91\5e\18\91\58\3e\64\29\80\37\11\2b\8a\fa\ec\f3\83\00\3d\08\8b\27\85\b7\6c\cb\a5\b6\d3\0e\e5\ea\a8\55\6d\fa\e3\85\46\25\2f\83\76\29"),
        (1024, 4097, "\5f\8a\9d\aa\a6\aa\f3\55\92\7e\b5\b2\e3\69\2d\21\60\ea\09\d0\66\c0\e9\fb\2d\33\79\5c\c6\62\aa\7c", "\0d\40\64\1a\91\ff\42\73\58\72\27\d7\fe\b5\9e\7b\4b\fd\1d\af\09\98\58\af\56\69\7b\05\43\2f\13\7e\2e\06\f3\a2\68\26\b8\70\25\d7\d6\16\d3\60\71\c8\9b\a7\da\62\20\33\75\73\77\cd\5b\ba\41\92\9c\04"),
      ];
      for ((keySize, messageSize, expected256, expected512) in vectors.values()) {
        let key = pattern(keySize);
        let message = pattern(messageSize);
        assert HMAC.sha256(key, message) == expected256;
        assert HMAC.sha512(key, message) == expected512;
        let prepared256 = HMAC.prepareSha256(key);
        let prepared512 = HMAC.prepareSha512(key);
        assert prepared256.digest(message) == expected256;
        assert prepared512.digest(message) == expected512;
        let stream256 = prepared256.stream();
        let stream512 = prepared512.stream();
        var pos = 0;
        // 63-byte chunks repeatedly straddle both hash block sizes.
        while (pos < messageSize) {
          let remaining : Nat = messageSize - pos;
          let count = if (remaining < 63) remaining else 63;
          let chunk = slice(message, pos, count);
          stream256.write(chunk);
          stream512.write(chunk);
          pos += count;
        };
        assert stream256.sum() == expected256;
        assert stream512.sum() == expected512;
        assert stream256.sum() == expected256;
        assert stream512.sum() == expected512;
        assert key == pattern(keySize);
        assert message == pattern(messageSize);
      };
    })
  };

  public func test_stream_lifecycle_and_prepared_key_isolation() : async Test.Metrics {
    Test.test(func() {
      let key : Blob = "Jefe";
      let message : Blob = "what do ya want for nothing?";
      // Each expected output is independently fixed by RFC 4231 or Python hmac.
      let variants : [(HMAC.PreparedKey, HMAC.Digest, Blob, Blob, Blob)] = [
        (HMAC.prepareSha256(key), HMAC.SHA256(key), "\92\35\98\ca\6d\64\af\2a\5d\ba\79\dc\d0\21\a8\a0\fe\5c\5f\55\75\19\ad\aa\f0\ad\53\2d\45\06\dd\30", "\b4\f9\01\c9\68\04\e2\2a\9b\5e\2e\9d\94\5c\65\5c\01\d5\98\71\21\ce\c6\f5\5f\f5\f5\be\ae\d2\2e\4f", "\5b\dc\c1\46\bf\60\75\4e\6a\04\24\26\08\95\75\c7\5a\00\3f\08\9d\27\39\83\9d\ec\58\b9\64\ec\38\43"),
        (HMAC.prepareSha512(key), HMAC.SHA512(key), "\b9\d1\4c\51\a6\d4\dd\41\60\4e\b0\6c\9c\24\0f\1f\64\f1\43\b5\cf\de\a3\71\29\b2\8b\b7\5d\13\71\d3\26\fc\21\92\16\17\12\61\a8\4e\6c\05\70\7c\d3\be\0f\61\e0\a9\73\a3\3f\70\6d\19\0d\b9\ac\ff\c6\8f", "\31\53\c1\65\95\be\ea\9c\55\6b\4a\87\e7\d8\d4\13\ad\0b\95\dd\59\ad\52\81\56\94\36\33\e1\0d\0c\7e\ca\b1\18\ed\b4\1e\85\3e\d3\f5\72\32\2a\41\d2\e0\29\87\ef\18\a2\8c\cb\96\96\a5\4f\3c\29\06\93\b7", "\16\4b\7a\7b\fc\f8\19\e2\e3\95\fb\e7\3b\56\e0\a3\87\bd\64\22\2e\83\1f\d6\10\27\0c\d7\ea\25\05\54\97\58\bf\75\c0\5a\99\4a\6d\03\4f\65\f8\f0\e6\fd\ca\ea\b1\a3\4d\4a\6b\4b\63\6e\07\0a\38\bc\e7\37"),
      ];
      for ((prepared, stream, empty, prefix, complete) in variants.values()) {
        assert stream.sum() == empty;
        stream.write("");
        assert stream.sum() == empty;
        stream.write("what do ya want ");
        let saved = stream.sum();
        assert saved == prefix;
        assert stream.sum() == prefix;
        stream.write("for nothing?");
        assert stream.sum() == complete;
        assert saved == prefix;
        stream.reset();
        assert stream.sum() == empty;
        stream.write(message);
        assert stream.sum() == complete;
        stream.reset();
        stream.reset();
        assert stream.sum() == empty;
        let left = prepared.stream();
        let right = prepared.stream();
        left.write("what do ya want ");
        right.write(message);
        assert left.sum() == prefix;
        assert right.sum() == complete;
        assert prepared.digest(message) == complete;
        assert prepared.digest("") == empty;
        left.write("for nothing?");
        assert left.sum() == complete;
        right.reset();
        assert right.sum() == empty;
        assert left.sum() == complete;
        assert prepared.stream().sum() == empty;
      };
    })
  };

  public func test_aliases_callbacks_and_argument_evaluation() : async Test.Metrics {
    Test.test(func() {
      var order = "";
      let actual256 = (do { order #= "callee;"; HMAC.sha256 })(
        do { order #= "key;"; "Jefe" : Blob },
        do { order #= "message;"; "what do ya want for nothing?" : Blob }
      );
      assert order == "callee;key;message;";
      order := "";
      let actual512 = (do { order #= "callee;"; HMAC.sha512 })(
        do { order #= "key;"; "Jefe" : Blob },
        do { order #= "message;"; "what do ya want for nothing?" : Blob }
      );
      assert order == "callee;key;message;";
      let expected256 = HMAC.sha256("Jefe", "what do ya want for nothing?");
      let expected512 = HMAC.sha512("Jefe", "what do ya want for nothing?");
      assert actual256 == expected256;
      assert actual512 == expected512;
      let direct = HMAC.sha256;
      let record = { direct };
      func identity<T>(value : T) : T = value;
      let alias = identity(direct);
      let aliases = [direct, alias];
      assert record.direct("Jefe", "what do ya want for nothing?") == expected256;
      assert aliases[0]("Jefe", "what do ya want for nothing?") == expected256;
      assert aliases[1]("Jefe", "what do ya want for nothing?") == expected256;
      func callback256(key : Blob, message : Blob) : Blob { HMAC.sha256(key, message) };
      func callback512(key : Blob, message : Blob) : Blob { HMAC.sha512(key, message) };
      let callbacks : [(Blob, Blob) -> Blob] = [callback256, callback512];
      assert callbacks[0]("Jefe", "what do ya want for nothing?") == expected256;
      assert callbacks[1]("Jefe", "what do ya want for nothing?") == expected512;
      var keyCalls = 0;
      func getKey() : Blob { keyCalls += 1; "Jefe" };
      let prepared = HMAC.prepareSha256(getKey());
      assert keyCalls == 1;
      assert prepared.digest("what do ya want for nothing?") == expected256;
      assert prepared.digest("what do ya want for nothing?") == expected256;
      let stream = HMAC.SHA512(getKey());
      assert keyCalls == 2;
      stream.write("what do ya want for nothing?");
      assert stream.sum() == expected512;
      stream.reset();
      assert keyCalls == 2;
    })
  };

}
