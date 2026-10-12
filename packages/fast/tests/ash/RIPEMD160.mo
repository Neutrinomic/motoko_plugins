import Test "mo:test";
import Hash "mo:fast/RIPEMD160";
import Prim "mo:⛔";

persistent actor {
  func bytes(n : Nat) : Blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(n, func(i) {
    Prim.natToNat8((i * 131 + 17) % 256)
  }));
  func slice(a : [Nat8], start : Nat, size : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) { a[start + i] }))
  };
  func must(v : ?Blob) : Blob = switch v {
    case (?b) b;
    case null Prim.trap("expected valid state");
  };

  public func test_independent_binary_vectors_and_streaming() : async Test.Metrics {
    Test.test(func() {
      // Fixed Python hashlib/OpenSSL answers for byte[i]=(i*131+17)%256.
      let vectors : [(Nat, Blob)] = [
      (0, "\9c\11\85\a5\c5\e9\fc\54\61\28\08\97\7e\e8\f5\48\b2\25\8d\31"),
      (1, "\dd\60\98\c3\16\99\36\85\cf\24\4f\6f\93\27\04\e8\63\fd\df\fc"),
      (2, "\ac\29\20\23\e7\c6\78\d0\1b\be\d0\01\ed\48\33\2d\31\0b\30\19"),
      (31, "\3e\4c\65\e1\e1\4f\63\35\15\16\fc\0e\b7\89\5c\59\54\7b\65\f7"),
      (32, "\6e\15\5d\f0\e6\ad\32\f6\47\dc\17\89\d6\e1\bf\4c\9c\eb\e2\73"),
      (33, "\32\b4\de\73\2e\15\1d\4f\de\cf\b1\4b\bc\af\58\13\10\97\99\eb"),
      (54, "\b9\90\ab\6f\e3\bc\16\ce\69\01\60\0a\ca\a8\4e\cb\f1\5b\ea\65"),
      (55, "\bc\83\80\5c\e4\ab\83\ba\49\dd\28\a2\a1\1a\e3\b3\1c\ef\a5\81"),
      (56, "\19\4a\11\d6\cc\36\da\ad\d3\0c\1f\42\96\b9\b2\98\db\a4\8a\28"),
      (57, "\86\5a\58\4c\3b\0a\1f\41\80\f4\b4\a8\e2\b3\57\01\c3\01\8c\2d"),
      (63, "\90\f8\a7\c9\f4\c0\af\c8\0c\41\58\9f\26\d1\5c\c5\3e\12\9a\47"),
      (64, "\6a\33\4a\da\e0\9c\cc\00\29\fb\1a\95\de\03\ad\8b\3b\61\ef\0e"),
      (65, "\dd\54\36\82\40\23\72\fb\64\e9\0d\0a\0b\76\6e\8d\4e\0e\4f\8e"),
      (119, "\c5\6b\c4\f0\a7\9b\0a\9f\a8\32\3c\7c\f0\d8\77\cd\39\2d\82\a0"),
      (120, "\d8\0a\7c\35\4a\e0\95\36\ac\e7\5d\69\7d\ac\6a\36\a9\e0\98\19"),
      (127, "\82\8f\60\e3\be\e5\67\38\19\0d\fe\7a\8a\86\b6\6f\87\bc\4a\61"),
      (128, "\5d\50\e4\1e\7a\85\66\51\8b\e2\0d\9e\52\8b\79\1f\9c\fa\84\ba"),
      (129, "\26\9d\c1\84\3a\99\af\b6\f6\83\b4\14\e1\f4\d1\c7\8a\9e\d3\ac"),
      (255, "\55\b1\9c\7f\d0\4b\b4\3d\43\bd\c5\ad\8e\7b\3a\5a\34\cd\ff\fa"),
      (256, "\df\1d\ea\a7\0c\17\a9\0b\5e\ec\6d\d0\b8\ff\e4\de\9c\2e\08\cb"),
      (257, "\ac\fb\a4\9b\2d\c7\8d\b8\42\fd\63\6e\cb\8f\b4\88\e2\82\6f\42"),
      (1023, "\db\e8\43\7e\5e\5c\06\50\05\c3\18\70\b4\80\47\6c\db\56\30\44"),
      (1024, "\35\a6\0c\3f\56\5b\c6\d7\f8\08\b5\8b\39\ef\ec\28\e6\03\f5\e4"),
      (1025, "\26\9b\75\ed\5f\f0\e9\98\0e\a1\80\59\f4\24\f9\3e\f0\6f\80\a9"),
      (4096, "\d0\35\99\ed\12\c0\5e\64\3c\a5\52\f2\4a\e8\e3\75\01\5a\2b\60"),
      (65537, "\56\60\6e\b7\7b\22\ee\49\a1\6b\2a\83\04\c7\6d\39\a1\a3\cf\df"),
      ];
      for ((size, expected) in vectors.values()) {
        let input = bytes(size);
        let inputArray = Prim.blobToArray(input);
        assert Hash.digest(input) == expected;
        assert expected.size() == 20;
        let original = Hash.init();
        let canonical = must(Hash.update(original, input));
        var state = original;
        var start = 0;
        while (start < size) {
          let count = if (size - start < 61) size - start else 61;
          state := must(Hash.update(state, slice(inputArray, start, count)));
          start += count;
        };
        assert state == canonical;
        assert Hash.finalize(state) == ?expected;
        assert Hash.finalize(state) == ?expected;
        assert Hash.update(state, "") == ?state;
        assert Hash.finalize(original) == ?Hash.digest("");
        assert input == bytes(size);
      };
    })
  };

  public query func test_forking_and_class_api() : async Test.Metrics {
    Test.test(func() {
      let empty = Hash.init();
      let a = must(Hash.update(empty, "a"));
      assert Hash.finalize(must(Hash.update(a, "bc"))) == ?Hash.digest("abc");
      assert Hash.finalize(must(Hash.update(a, "def"))) == ?Hash.digest("adef");
      assert Hash.finalize(a) == ?Hash.digest("a");
      assert Hash.finalize(empty) == ?Hash.digest("");
      let stream = Hash.Digest();
      assert stream.write("ab");
      assert stream.sum() == Hash.digest("ab");
      assert stream.write("c");
      assert stream.sum() == Hash.digest("abc");
      stream.reset();
      assert stream.sum() == Hash.digest("");
      var order = "";
      ignore (do { order #= "callee;"; Hash.update })(
        do { order #= "state;"; empty }, do { order #= "input;"; "abc" : Blob }
      );
      assert order == "callee;state;input;";
    })
  };

  public query func test_malformed_states() : async Test.Metrics {
    Test.test(func() {
      let initial = Hash.init();
      let original = Prim.blobToArray(initial);
      for (length in [0, 1, 20, 64, 103, 105].values()) {
        assert Hash.update(bytes(length), "abc") == null;
        assert Hash.finalize(bytes(length)) == null;
      };
      for (offset in [0, 3, 4, 7, 15, 16, 35, 36, 39, 40, 103].values()) {
        let invalid = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(104, func(i) {
          if (i == offset) 255 else original[i]
        }));
        assert Hash.update(invalid, "") == null;
        assert Hash.finalize(invalid) == null;
      };
      let limit = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(104, func(i) {
        if (i >= 8 and i < 15) 255 else if (i == 15) 31 else original[i]
      }));
      assert Hash.finalize(limit) != null;
      assert Hash.update(limit, "") == ?limit;
      assert Hash.update(limit, "a") == null;
    })
  };

  public func test_million_a_and_retained_results() : async Test.Metrics {
    Test.test(func() {
      let saved = Hash.digest("abc");
      let million = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1_000_000, func(_) { 97 }));
      // Official RIPEMD-160 authors' million-a known answer.
      assert Hash.digest(million) == "\52\78\32\43\c1\69\7b\db\e1\6d\37\f9\7f\68\f0\83\25\dc\15\28";
      let stream = Hash.Digest();
      let chunk = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1_000, func(_) { 97 }));
      var i = 0;
      while (i < 1_000) { assert stream.write(chunk); i += 1 };
      assert stream.sum() == Hash.digest(million);
      assert saved == Hash.digest("abc");
    })
  };
}
