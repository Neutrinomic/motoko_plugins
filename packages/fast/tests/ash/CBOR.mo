import Test "mo:test";
import CBOR "mo:fast/CBOR";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Float32 "mo:core/Float32";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

persistent actor {
  func ok<T>(result : CBOR.Result<T>) : T {
    switch result {
      case (#ok value) value;
      case (#err error) Runtime.trap(debug_show error);
    }
  };

  func error<T>(result : CBOR.Result<T>) : CBOR.Error {
    switch result {
      case (#ok _) Runtime.trap("expected a CBOR error");
      case (#err value) {
        assert value.message.size() > 0;
        assert value.kind.size() > 0;
        value
      };
    }
  };

  func expect<T>(result : CBOR.Result<T>, kind : Text, path : Text, offset : Nat) {
    let e = error(result);
    assert (e.kind, e.path, Nat64.toNat(e.offset)) == (kind, path, offset);
  };

  // Independent RFC 8949 major-type-0/1 oracle. It never calls the codec.
  func integerWire(major : Nat, magnitude : Nat) : Blob {
    if (magnitude < 24) return Blob.fromArray([Nat8.fromNat(major * 32 + magnitude)]);
    let (additional, count) = if (magnitude <= 255) (24, 1)
      else if (magnitude <= 65535) (25, 2)
      else if (magnitude <= 4294967295) (26, 4) else (27, 8);
    Blob.fromArray(Array.tabulate<Nat8>(count + 1, func(i) {
      if (i == 0) Nat8.fromNat(major * 32 + additional)
      else Nat8.fromNat((magnitude / 256 ** (count - i)) % 256)
    }))
  };

  func append(a : Blob, b : Blob) : Blob {
    let aa = Blob.toArray(a);
    let bb = Blob.toArray(b);
    Blob.fromArray(Array.tabulate<Nat8>(aa.size() + bb.size(), func(i) {
      if (i < aa.size()) aa[i] else bb[i - aa.size()]
    }))
  };

  // Build a rope in O(log n) concatenations, keeping large limit probes cheap.
  func ascii(n : Nat) : Text {
    var remaining = n;
    var chunk = "a";
    var result = "";
    while (remaining > 0) {
      if (remaining % 2 == 1) result #= chunk;
      remaining /= 2;
      if (remaining > 0) chunk #= chunk;
    };
    result
  };

  type State = { #ready; #count : Nat; #bytes : Blob };
  type User = { id : Nat; name : Text; note : ?Text; flags : [Bool]; state : State };
  type Chain = ?{ value : Nat; next : Chain };

  public query func test_public_alias_and_result_types() : async Test.Metrics {
    Test.test(func() {
      let encode = CBOR.encode;
      let methods = { encode; decode = CBOR.decode };
      let result : CBOR.Result<Blob> = methods.encode((42 : Nat, "answer" : Text));
      let decoded : CBOR.Result<(Nat, Text)> = methods.decode<(Nat, Text)>(ok(result));
      assert decoded == #ok (42, "answer");
      let e : CBOR.Error = error(methods.decode<Nat>(""));
      assert e.kind == "syntax";
    })
  };

  public query func test_integer_wire_boundaries() : async Test.Metrics {
    Test.test(func() {
      let boundaries : [Nat] = [0, 1, 22, 23, 24, 25, 127, 128, 254, 255, 256,
        257, 65534, 65535, 65536, 65537, 4294967294, 4294967295, 4294967296,
        4294967297, 9223372036854775807, 9223372036854775808, 18446744073709551615];
      for (n in boundaries.vals()) {
        let positive = integerWire(0, n);
        assert CBOR.encode(n) == #ok positive;
        assert CBOR.decode<Nat>(positive) == #ok n;
        let signed : Int = -1 - n;
        let negative = integerWire(1, n);
        assert CBOR.encode(signed) == #ok negative;
        assert CBOR.decode<Int>(negative) == #ok signed;
      };
    })
  };

  public query func test_integer_deterministic_oracle_corpus() : async Test.Metrics {
    Test.test(func() {
      var state = 0x12345678 : Nat;
      var i = 0;
      while (i < 512) {
        state := (state * 6364136223846793005 + 1442695040888963407) % 18446744073709551616;
        let wire = integerWire(0, state);
        assert CBOR.encode(state) == #ok wire;
        assert CBOR.decode<Nat>(wire) == #ok state;
        let negative : Int = -1 - state;
        assert CBOR.encode(negative) == #ok (integerWire(1, state));
        assert CBOR.decode<Int>(integerWire(1, state)) == #ok negative;
        i += 1;
      };
    })
  };

  public query func test_fixed_width_integer_extrema() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.decode<Nat8>(ok(CBOR.encode(255 : Nat8))) == #ok (255 : Nat8);
      assert CBOR.decode<Nat16>(ok(CBOR.encode(65535 : Nat16))) == #ok (65535 : Nat16);
      assert CBOR.decode<Nat32>(ok(CBOR.encode(4294967295 : Nat32))) == #ok (4294967295 : Nat32);
      assert CBOR.decode<Nat64>(ok(CBOR.encode(18446744073709551615 : Nat64))) == #ok (18446744073709551615 : Nat64);
      assert CBOR.encode(-128 : Int8) == #ok ("\38\7f" : Blob);
      assert CBOR.encode(-32768 : Int16) == #ok ("\39\7f\ff" : Blob);
      assert CBOR.encode(-2147483648 : Int32) == #ok ("\3a\7f\ff\ff\ff" : Blob);
      assert CBOR.encode(-9223372036854775808 : Int64) == #ok ("\3b\7f\ff\ff\ff\ff\ff\ff\ff" : Blob);
      assert CBOR.decode<Int8>("\18\7f") == #ok (127 : Int8);
      assert CBOR.decode<Int16>("\39\7f\ff") == #ok (-32768 : Int16);
      assert CBOR.decode<Int32>("\1a\7f\ff\ff\ff") == #ok (2147483647 : Int32);
      assert CBOR.decode<Int64>("\3b\7f\ff\ff\ff\ff\ff\ff\ff") == #ok (-9223372036854775808 : Int64);
    })
  };

  public query func test_integer_range_errors() : async Test.Metrics {
    Test.test(func() {
      expect(CBOR.decode<Nat8>("\19\01\00"), "range", "", 3);
      expect(CBOR.decode<Nat16>("\1a\00\01\00\00"), "range", "", 5);
      expect(CBOR.decode<Nat32>("\1b\00\00\00\01\00\00\00\00"), "range", "", 9);
      expect(CBOR.decode<Nat64>("\c2\49\01\00\00\00\00\00\00\00\00"), "range", "", 11);
      expect(CBOR.decode<Int8>("\18\80"), "range", "", 2);
      expect(CBOR.decode<Int8>("\38\80"), "range", "", 2);
      expect(CBOR.decode<Int16>("\19\80\00"), "range", "", 3);
      expect(CBOR.decode<Int16>("\39\80\00"), "range", "", 3);
      expect(CBOR.decode<Int32>("\1a\80\00\00\00"), "range", "", 5);
      expect(CBOR.decode<Int32>("\3a\80\00\00\00"), "range", "", 5);
      expect(CBOR.decode<Int64>("\1b\80\00\00\00\00\00\00\00"), "range", "", 9);
      expect(CBOR.decode<Int64>("\3b\80\00\00\00\00\00\00\00"), "range", "", 9);
      expect(CBOR.decode<Nat>("\20"), "range", "", 1);
      expect(CBOR.decode<Nat8>("\20"), "range", "", 1);
    })
  };

  public query func test_bignum_tags_and_canonicalization() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.encode(18446744073709551616 : Nat) == #ok ("\c2\49\01\00\00\00\00\00\00\00\00" : Blob);
      assert CBOR.encode(-18446744073709551617 : Int) == #ok ("\c3\49\01\00\00\00\00\00\00\00\00" : Blob);
      assert CBOR.decode<Nat>("\c2\40") == #ok 0;
      assert CBOR.decode<Int>("\c3\40") == #ok (-1);
      assert CBOR.decode<Nat64>("\c2\49\00\ff\ff\ff\ff\ff\ff\ff\ff") == #ok (18446744073709551615 : Nat64);
      assert CBOR.encode(ok(CBOR.decode<Nat>("\c2\43\00\00\18"))) == #ok ("\18\18" : Blob);
      assert CBOR.encode(ok(CBOR.decode<Int>("\c3\42\00\17"))) == #ok ("\37" : Blob);
      let large : Int = -(2 ** 1024) + 17;
      assert CBOR.decode<Int>(ok(CBOR.encode(large))) == #ok large;
      expect(CBOR.decode<Nat>("\c2\61x"), "type", "", 2);
      expect(CBOR.decode<Nat>("\c3\41\00"), "range", "", 3);
    })
  };

  public query func test_bool_null_unit_and_empty_values() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.encode(true) == #ok ("\f5" : Blob);
      assert CBOR.encode(false) == #ok ("\f4" : Blob);
      assert CBOR.encode(null) == #ok ("\f6" : Blob);
      assert CBOR.encode(()) == #ok ("\80" : Blob);
      assert CBOR.encode({}) == #ok ("\a0" : Blob);
      assert CBOR.encode([] : [None]) == #ok ("\80" : Blob);
      assert CBOR.encode("" : Text) == #ok ("\60" : Blob);
      assert CBOR.encode("" : Blob) == #ok ("\40" : Blob);
      assert CBOR.decode<Bool>("\f4") == #ok false;
      assert CBOR.decode<Null>("\f6") == #ok null;
      assert CBOR.decode<()>("\80") == #ok ();
      ignore ok(CBOR.decode<{}>("\a0"));
      assert CBOR.decode<[None]>("\80") == #ok([]);
      assert CBOR.decode<?None>("\f6") == #ok null;
    })
  };

  public query func test_text_unicode_and_characters() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.encode("a☃" : Text) == #ok ("\64a\e2\98\83" : Blob);
      assert CBOR.encode('😀') == #ok ("\64\f0\9f\98\80" : Blob);
      assert CBOR.decode<Char>("\64\f0\9f\98\80") == #ok '😀';
      assert CBOR.decode<Char>("\61\00") == #ok '\00';
      let texts = ["", "ASCII", "\00\01\1f", "é", "é", "中文", "a😀\00é", "\u{10ffff}"];
      for (text in texts.vals()) assert CBOR.decode<Text>(ok(CBOR.encode(text))) == #ok text;
      expect(CBOR.decode<Char>("\60"), "type", "", 1);
      expect(CBOR.decode<Char>("\62ab"), "type", "", 3);
    })
  };

  public query func test_utf8_rejection_corpus() : async Test.Metrics {
    Test.test(func() {
      let invalid : [Blob] = ["\61\80", "\61\ff", "\62\c0\80", "\62\c1\bf", "\62\c2a",
        "\63\e0\80\80", "\63\ed\a0\80", "\63\ed\bf\bf", "\63\ef\bf",
        "\64\f0\80\80\80", "\64\f4\90\80\80", "\65\f8\88\80\80\80"];
      for (bytes in invalid.vals()) {
        let e = error(CBOR.decode<Text>(bytes));
        assert e.kind == "utf8" or e.kind == "syntax";
        assert e.path == "";
      };
      assert CBOR.decode<Text>("\63\ed\9f\bf") == #ok "\u{d7ff}";
      assert CBOR.decode<Text>("\63\ee\80\80") == #ok "\u{e000}";
      assert CBOR.decode<Text>("\64\f4\8f\bf\bf") == #ok "\u{10ffff}";
    })
  };

  public query func test_blob_and_nat8_array_are_distinct() : async Test.Metrics {
    Test.test(func() {
      let bytes : Blob = "\00\18\ff";
      assert CBOR.encode(bytes) == #ok ("\43\00\18\ff" : Blob);
      assert CBOR.encode([0, 24, 255] : [Nat8]) == #ok ("\83\00\18\18\18\ff" : Blob);
      assert CBOR.decode<Blob>("\43\00\18\ff") == #ok bytes;
      assert CBOR.decode<[Nat8]>("\83\00\18\18\18\ff") == #ok([0, 24, 255]);
      assert error(CBOR.decode<Blob>("\83\00\18\18\18\ff")).kind == "type";
      assert error(CBOR.decode<[Nat8]>("\43\00\18\ff")).kind == "type";
    })
  };

  public query func test_principal_byte_mapping_and_limits() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.encode(Principal.fromText("aaaaa-aa")) == #ok ("\40" : Blob);
      assert CBOR.encode(Principal.fromText("2vxsx-fae")) == #ok ("\41\04" : Blob);
      assert CBOR.decode<Principal>("\41\04") == #ok (Principal.fromText("2vxsx-fae"));
      let max = Blob.fromArray(Array.repeat<Nat8>(255, 29));
      assert CBOR.decode<Principal>(ok(CBOR.encode(max))) == #ok (Principal.fromBlob(max));
      let tooLong = Blob.fromArray(Array.repeat<Nat8>(0, 30));
      expect(CBOR.decode<Principal>(ok(CBOR.encode(tooLong))), "principal", "", 32);
    })
  };

  public query func test_float_shortest_rfc_encodings() : async Test.Metrics {
    Test.test(func() {
      let vectors : [(Float, Blob)] = [(0.0, "\f9\00\00"), (-0.0, "\f9\80\00"),
        (1.0, "\f9\3c\00"), (1.5, "\f9\3e\00"), (-4.0, "\f9\c4\00"),
        (65504.0, "\f9\7b\ff"), (0.00006103515625, "\f9\04\00"),
        (0.000000059604644775390625, "\f9\00\01"), (100000.0, "\fa\47\c3\50\00"),
        (1.1, "\fb\3f\f1\99\99\99\99\99\9a")];
      for ((value, wire) in vectors.vals()) {
        assert CBOR.encode(value) == #ok wire;
        assert CBOR.decode<Float>(wire) == #ok value;
      };
      assert 1.0 / ok(CBOR.decode<Float>("\f9\80\00")) == -1.0 / 0.0;
      assert 1.0 / ok(CBOR.decode<Float>("\f9\00\00")) == 1.0 / 0.0;
      assert CBOR.encode(ok(CBOR.decode<Float>("\fb\3f\f0\00\00\00\00\00\00"))) == #ok ("\f9\3c\00" : Blob);
    })
  };

  public query func test_float_nan_infinity_and_float32_rounding() : async Test.Metrics {
    Test.test(func() {
      let nan = ok(CBOR.decode<Float>("\fb\7f\f0\00\00\00\00\00\01"));
      assert nan != nan;
      assert CBOR.encode(nan) == #ok ("\f9\7e\00" : Blob);
      assert CBOR.encode(0.0 / 0.0 : Float) == #ok ("\f9\7e\00" : Blob);
      assert CBOR.encode(1.0 / 0.0 : Float) == #ok ("\f9\7c\00" : Blob);
      assert CBOR.encode(-1.0 / 0.0 : Float) == #ok ("\f9\fc\00" : Blob);
      assert CBOR.decode<Float>("\f9\7c\00") == #ok (1.0 / 0.0);
      assert CBOR.decode<Float32>("\f9\fc\00") == #ok (-1.0 / 0.0 : Float32);
      assert Float32.isNaN(ok(CBOR.decode<Float32>("\f9\fe\01")));
      assert CBOR.encode(-0.0 : Float32) == #ok ("\f9\80\00" : Blob);
      assert CBOR.decode<Float32>("\fb\3f\f1\99\99\99\99\99\9a") == #ok (1.1 : Float32);
      // 1 + 2^-24 is exactly halfway: binary32 rounds to even 1.0.
      assert CBOR.decode<Float32>("\fb\3f\f0\00\00\10\00\00\00") == #ok (1.0 : Float32);
      expect(CBOR.decode<Float32>("\fb\7f\ef\ff\ff\ff\ff\ff\ff"), "range", "", 9);
      expect(CBOR.decode<Float32>("\fb\ff\ef\ff\ff\ff\ff\ff\ff"), "range", "", 9);
      assert CBOR.decode<Float32>("\fb\00\00\00\00\00\00\00\01") == #ok (0.0 : Float32);
      let smallest32 = ok(CBOR.decode<Float32>("\fa\00\00\00\01"));
      let largest32 = ok(CBOR.decode<Float32>("\fa\7f\7f\ff\ff"));
      assert smallest32 > 0.0;
      assert largest32 < 1.0 / 0.0;
      assert CBOR.encode(smallest32) == #ok ("\fa\00\00\00\01" : Blob);
      assert CBOR.encode(largest32) == #ok ("\fa\7f\7f\ff\ff" : Blob);
      assert 1.0 / ok(CBOR.decode<Float32>("\fb\80\00\00\00\00\00\00\01")) == (-1.0 / 0.0 : Float32);
    })
  };

  public query func test_float_all_binary16_encodings() : async Test.Metrics {
    Test.test(func() {
      // Every 16-bit pattern, including all signed NaN payloads and subnormals.
      var bits = 0;
      while (bits < 65536) {
        let wire = Blob.fromArray([0xf9, Nat8.fromNat(bits / 256), Nat8.fromNat(bits % 256)]);
        let decoded = ok(CBOR.decode<Float>(wire));
        let encoded = ok(CBOR.encode(decoded));
        let isNaN = (bits / 1024) % 32 == 31 and bits % 1024 != 0;
        assert encoded == (if (isNaN) ("\f9\7e\00" : Blob) else wire);
        let as32 = ok(CBOR.decode<Float32>(wire));
        assert ok(CBOR.encode(as32)) == encoded;
        bits += 1;
      };
    })
  };

  public query func test_text_and_blob_length_heads() : async Test.Metrics {
    Test.test(func() {
      for (size in [0, 1, 23, 24, 25, 255, 256, 65535, 65536].vals()) {
        let text = ascii(size);
        let bytes = Text.encodeUtf8(text);
        let head = Blob.toArray(integerWire(0, size));
        let byteHead = Blob.fromArray(Array.tabulate<Nat8>(head.size(), func(i) {
          if (i == 0) head[i] + 0x40 else head[i]
        }));
        let textHead = Blob.fromArray(Array.tabulate<Nat8>(head.size(), func(i) {
          if (i == 0) head[i] + 0x60 else head[i]
        }));
        let encodedBlob = append(byteHead, bytes);
        let encodedText = append(textHead, bytes);
        assert CBOR.encode(bytes) == #ok encodedBlob;
        assert CBOR.encode(text) == #ok encodedText;
        assert CBOR.decode<Blob>(encodedBlob) == #ok bytes;
        assert CBOR.decode<Text>(encodedText) == #ok text;
      };
    })
  };

  public query func test_no_implicit_scalar_coercions() : async Test.Metrics {
    Test.test(func() {
      expect(CBOR.decode<Float>("\01"), "type", "", 1);
      expect(CBOR.decode<Nat>("\f9\3c\00"), "type", "", 3);
      expect(CBOR.decode<Bool>("\01"), "type", "", 1);
      expect(CBOR.decode<Text>("\41a"), "type", "", 1);
      expect(CBOR.decode<Blob>("\61a"), "type", "", 1);
      expect(CBOR.decode<Null>("\f4"), "type", "", 1);
      expect(CBOR.decode<None>("\f6"), "type", "", 0);
    })
  };

  public query func test_arrays_tuples_and_length_heads() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.encode((1 : Nat, "x" : Text, ?false : ?Bool)) == #ok ("\83\01\61x\f4" : Blob);
      assert CBOR.decode<(Nat, Text, ?Bool)>("\83\01\61x\f4") == #ok (1, "x", ?false);
      for (size in [0, 1, 23, 24, 25, 255, 256].vals()) {
        let items = Array.repeat<Null>(null, size);
        let encoded = ok(CBOR.encode(items));
        let head = Blob.toArray(integerWire(0, size));
        let expected = Blob.fromArray(Array.tabulate<Nat8>(head.size() + size, func(i) {
          if (i == 0) head[0] + 0x80 else if (i < head.size()) head[i] else 0xf6
        }));
        assert encoded == expected;
        assert CBOR.decode<[Null]>(encoded) == #ok items;
      };
      expect(CBOR.decode<(Nat, Nat)>("\81\00"), "type", "", 1);
      expect(CBOR.decode<(Nat, Nat)>("\83\00\01\02"), "type", "", 1);
      expect(CBOR.decode<[Nat8]>("\82\00\19\01\00"), "range", "/1", 5);
    })
  };

  public query func test_record_names_and_deterministic_order() : async Test.Metrics {
    Test.test(func() {
      let record = { aa = 1 : Nat; b = 2 : Nat; a = 3 : Nat; _42_ = 4 : Nat };
      assert CBOR.encode(record) == #ok ("\a4\61a\03\61b\02\62aa\01\64_42_\04" : Blob);
      assert CBOR.decode<{ a : Nat; b : Nat; aa : Nat; _42_ : Nat }>(
        "\a4\64_42_\04\62aa\01\61b\02\61a\03") == #ok record;
      assert CBOR.encode({ abcdefghijklmnopqrstuvwx = 24 : Nat; abcdefghijklmnopqrstuvw = 23 : Nat }) ==
        #ok ("\a2\77abcdefghijklmnopqrstuvw\17\78\18abcdefghijklmnopqrstuvwx\18\18" : Blob);
    })
  };

  public query func test_records_missing_unknown_and_duplicate_fields() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.decode<{ a : Nat; b : ?Text }>("\a1\61a\07") == #ok { a = 7; b = null };
      assert CBOR.decode<{ a : Nat; b : ?Text }>("\a2\61x\82\f5\a1\61y\f6\61a\07") == #ok { a = 7; b = null };
      expect(CBOR.decode<{ a : Nat }>("\a0"), "missing", "/a", 1);
      expect(CBOR.decode<{ a : Nat }>("\a2\61a\01\61a\02"), "duplicate", "", 6);
      expect(CBOR.decode<{}>("\a1\61x\a2\61a\00\61a\01"), "duplicate", "/x", 9);
      // Duplicate detection compares decoded text, including nonpreferred key heads.
      expect(CBOR.decode<{}>("\a2\61a\00\78\01a\01"), "duplicate", "", 7);
      assert error(CBOR.decode<{}>("\a1\00\00")).kind == "type";
      assert error(CBOR.decode<{}>("\a1\61x\c0\00")).kind == "type";
      assert error(CBOR.decode<{}>("\a1\61x\f7")).kind == "unsupported";
    })
  };

  public query func test_variants_payloads_and_shape_errors() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.encode(#ready : State) == #ok ("\a1\65ready\80" : Blob);
      assert CBOR.decode<State>("\a1\65ready\80") == #ok(#ready);
      assert CBOR.encode(#count(24) : State) == #ok ("\a1\65count\18\18" : Blob);
      assert CBOR.decode<State>("\a1\65bytes\42\00\ff") == #ok(#bytes("\00\ff"));
      expect(CBOR.decode<State>("\a1\61x\00"), "type", "/x", 3);
      expect(CBOR.decode<State>("\a0"), "type", "", 1);
      expect(CBOR.decode<State>("\a2\65count\00\65ready\80"), "type", "/ready", 14);
      assert error(CBOR.decode<State>("\a1\65ready\f6")).path == "/ready";
    })
  };

  public query func test_optional_null_and_nested_options() : async Test.Metrics {
    Test.test(func() {
      assert CBOR.encode(null : ?Nat) == #ok ("\f6" : Blob);
      assert CBOR.encode(?7 : ?Nat) == #ok ("\07" : Blob);
      assert CBOR.encode(null : ??Nat) == #ok ("\f6" : Blob);
      assert CBOR.encode(?null : ??Nat) == #ok ("\a1\64some\f6" : Blob);
      assert CBOR.encode(??7 : ??Nat) == #ok ("\a1\64some\07" : Blob);
      assert CBOR.encode(???7 : ???Nat) == #ok ("\a1\64some\a1\64some\07" : Blob);
      assert CBOR.encode(?null : ?Null) == #ok ("\a1\64some\f6" : Blob);
      assert CBOR.decode<??Nat>("\f6") == #ok null;
      assert CBOR.decode<??Nat>("\a1\64some\f6") == #ok (?null);
      assert CBOR.decode<??Nat>("\a1\64some\07") == #ok (??7);
      assert CBOR.decode<?Null>("\a1\64some\f6") == #ok (?null);
      assert CBOR.decode<?{ some : Nat }>("\a1\64some\07") == #ok (?{ some = 7 });
      expect(CBOR.decode<??Nat>("\a1\61x\00"), "type", "/x", 3);
      expect(CBOR.decode<??Nat>("\a0"), "type", "", 1);
      expect(CBOR.decode<{ a : ??Nat8 }>("\a1\61a\a1\64some\19\01\00"), "range", "/a/some", 12);
    })
  };

  public query func test_recursive_and_mutually_recursive_values() : async Test.Metrics {
    Test.test(func() {
      let chain : Chain = ?{ value = 1; next = ?{ value = 2; next = null } };
      assert CBOR.decode<Chain>(ok(CBOR.encode(chain))) == #ok chain;
      type Tree = { #leaf : Int; #branch : [Tree] };
      let tree : Tree = #branch([#leaf(-1), #branch([]), #branch([#leaf(2 ** 100)])]);
      assert CBOR.decode<Tree>(ok(CBOR.encode(tree))) == #ok tree;
      type A = ?{ b : B; n : Nat };
      type B = { #end; #a : A };
      let mutual : A = ?{ n = 7; b = #a(?{ n = 8; b = #end }) };
      assert CBOR.decode<A>(ok(CBOR.encode(mutual))) == #ok mutual;
    })
  };

  public query func test_deterministic_record_roundtrip_corpus() : async Test.Metrics {
    Test.test(func() {
      var i = 0;
      while (i < 128) {
        let user : User = {
          id = (2 ** (i % 100)) + i;
          name = if (i % 2 == 0) "😀\00é" else "name";
          note = if (i % 3 == 0) null else ?"optional";
          flags = Array.tabulate<Bool>(i % 17, func(j) { j % 2 == 0 });
          state = switch (i % 3) { case 0 #ready; case 1 #count(i); case _ #bytes("\00\ff") };
        };
        let encoded = ok(CBOR.encode(user));
        let decoded = ok(CBOR.decode<User>(encoded));
        assert decoded == user;
        assert CBOR.encode(decoded) == #ok encoded;
        i += 1;
      };
    })
  };

  public query func test_nonpreferred_definite_encodings() : async Test.Metrics {
    Test.test(func() {
      for (wire in (["\18\00", "\19\00\00", "\1a\00\00\00\00", "\1b\00\00\00\00\00\00\00\00"] : [Blob]).vals()) {
        assert CBOR.decode<Nat>(wire) == #ok 0;
        assert CBOR.encode(ok(CBOR.decode<Nat>(wire))) == #ok ("\00" : Blob);
      };
      assert CBOR.decode<Int>("\39\00\00") == #ok (-1);
      assert CBOR.decode<Text>("\78\01x") == #ok "x";
      assert CBOR.decode<Blob>("\59\00\01\ff") == #ok ("\ff" : Blob);
      assert CBOR.decode<[Nat]>("\98\01\18\01") == #ok([1]);
      assert CBOR.decode<{ a : Nat }>("\b8\01\78\01a\19\00\01") == #ok { a = 1 };
      assert CBOR.decode<Nat>("\d8\02\41\01") == #ok 1;
    })
  };

  public query func test_malformed_heads_truncation_and_trailing_bytes() : async Test.Metrics {
    Test.test(func() {
      let malformed : [Blob] = ["", "\18", "\19\00", "\1a\00\00\00", "\1b\00\00\00\00\00\00\00",
        "\1c", "\1d", "\1e", "\01\00", "\c2", "\c2\49\01"];
      for (wire in malformed.vals()) {
        let e = error(CBOR.decode<Nat>(wire));
        assert e.kind == "syntax";
      };
      expect(CBOR.decode<Nat>("\01\00"), "syntax", "", 1);
      let wire : Blob = "\a2\61a\82\01\02\61b\61x";
      let bytes = Blob.toArray(wire);
      var length = 0;
      while (length < bytes.size()) {
        let prefix = Blob.fromArray(Array.tabulate<Nat8>(length, func(i) { bytes[i] }));
        ignore error(CBOR.decode<{ a : [Nat]; b : Text }>(prefix));
        length += 1;
      };
      assert CBOR.decode<{ a : [Nat]; b : Text }>(wire) == #ok { a = [1, 2]; b = "x" };
      ignore error(CBOR.decode<{ a : [Nat]; b : Text }>(append(wire, "\00")));
    })
  };

  public query func test_unsupported_indefinite_tags_and_simple_values() : async Test.Metrics {
    Test.test(func() {
      for (wire in (["\9f\01\ff", "\5f\41a\ff", "\7f\61a\ff", "\bf\61a\01\ff"] : [Blob]).vals()) {
        let unknown = append("\a1\61x", wire);
        assert error(CBOR.decode<{}>(unknown)).kind == "unsupported";
      };
      for (wire in (["\f7", "\e0", "\f8\20", "\f8\ff"] : [Blob]).vals()) {
        assert error(CBOR.decode<{}>(append("\a1\61x", wire))).kind == "unsupported";
      };
      for (wire in (["\c0\00", "\c1\00", "\c4\82\00\00", "\d9\d9\f7\00"] : [Blob]).vals()) {
        assert error(CBOR.decode<{}>(append("\a1\61x", wire))).kind == "type";
      };
      expect(CBOR.decode<Bool>("\f8\14"), "syntax", "", 2);
      expect(CBOR.decode<Null>("\f8\16"), "syntax", "", 2);
    })
  };

  public query func test_single_byte_adversarial_corpus() : async Test.Metrics {
    Test.test(func() {
      var n = 0;
      while (n < 256) {
        let wire = Blob.fromArray([Nat8.fromNat(n)]);
        if (n < 24) assert CBOR.decode<Nat>(wire) == #ok n
        else {
          let e = error(CBOR.decode<Nat>(wire));
          assert e.offset <= 1;
        };
        n += 1;
      };
      // A failing call must not poison runtime scratch state for the next call.
      assert CBOR.decode<Nat>("\18\2a") == #ok 42;
      assert CBOR.encode([true, false]) == #ok ("\82\f5\f4" : Blob);
    })
  };

  public query func test_structured_error_paths_and_offsets() : async Test.Metrics {
    Test.test(func() {
      expect(CBOR.decode<{ a : [Text] }>("\a1\61a\8c\60\60\60\60\60\60\60\60\60\60\60\61\ff"), "utf8", "/a/11", 17);
      expect(CBOR.decode<{}>("\a1\64~\2f\c3\a9\81\61\ff"), "utf8", "/~0~1é/0", 9);
      expect(CBOR.decode<{}>("\a1\65\00~\2f\c3\a9\61\ff"), "utf8", "/\00~0~1é", 9);
      expect(CBOR.decode<{ a : { b : Bool } }>("\a1\61a\a1\61b\00"), "type", "/a/b", 7);
    })
  };

  public query func test_declared_length_limits_before_allocation() : async Test.Metrics {
    Test.test(func() {
      expect(CBOR.decode<[Nat]>("\9b\ff\ff\ff\ff\ff\ff\ff\ff"), "limit", "", 9);
      expect(CBOR.decode<Blob>("\5b\ff\ff\ff\ff\ff\ff\ff\ff"), "limit", "", 9);
      expect(CBOR.decode<Text>("\7a\01\00\00\01"), "limit", "", 5);
      expect(CBOR.decode<{}>("\bb\ff\ff\ff\ff\ff\ff\ff\ff"), "limit", "", 9);
      assert error(CBOR.decode<[Nat]>("\9a\00\0f\42\41")).kind == "limit";
      assert error(CBOR.decode<[Nat]>("\9a\00\0f\42\3f")).kind == "syntax";
      assert error(CBOR.decode<Blob>("\5a\01\00\00\00")).kind == "syntax";
    })
  };

  public query func test_depth_limit_and_recovery() : async Test.Metrics {
    Test.test(func() {
      var chain : Chain = null;
      var i = 0;
      while (i < 20) { chain := ?{ value = i; next = chain }; i += 1 };
      assert CBOR.decode<Chain>(ok(CBOR.encode(chain))) == #ok chain;
      while (i < 100) { chain := ?{ value = i; next = chain }; i += 1 };
      let encodeError = error(CBOR.encode(chain));
      assert encodeError.kind == "limit" and encodeError.offset == 0;
      type Deep = ?{ next : Deep };
      let prefix : [Nat8] = [0xa1, 0x64, 0x6e, 0x65, 0x78, 0x74];
      let wire = Blob.fromArray(Array.tabulate<Nat8>(601, func(i) {
        if (i == 600) 0xf6 else prefix[i % 6]
      }));
      assert error(CBOR.decode<Deep>(wire)).kind == "limit";
      assert CBOR.decode<Deep>("\f6") == #ok null;
      assert CBOR.encode(7 : Nat) == #ok ("\07" : Blob);
    })
  };

  public query func test_bignum_magnitude_limit_and_recovery() : async Test.Metrics {
    Test.test(func() {
      let largest : Nat = 2 ** 32768 - 1;
      assert CBOR.decode<Nat>(ok(CBOR.encode(largest))) == #ok largest;
      let oversized : Nat = 2 ** 32768;
      expect(CBOR.encode(oversized), "limit", "", 0);
      expect(CBOR.encode(??oversized : ??Nat), "limit", "/some", 0);
      let tooLong = append("\c2\59\10\01", Blob.fromArray(Array.repeat<Nat8>(0, 4097)));
      assert error(CBOR.decode<Nat>(tooLong)).kind == "limit";
      assert CBOR.decode<Nat>("\c2\41\01") == #ok 1;
    })
  };

  public func test_item_budget_at_and_past_limit() : async Test.Metrics {
    Test.test(func() {
      // One array value plus its 999,999 children reaches exactly one million.
      let accepted = Array.repeat<Null>(null, 999_999);
      let wire = ok(CBOR.encode(accepted));
      assert ok(CBOR.decode<[Null]>(wire)).size() == 999_999;
      let rejected = Array.repeat<Null>(null, 1_000_000);
      expect(CBOR.encode(rejected), "limit", "", 0);
      expect(CBOR.encode({ items = rejected }), "limit", "/items", 0);
      assert CBOR.decode<[Null]>("\81\f6") == #ok([null]);
    })
  };

  public func test_byte_budget_at_and_past_limit() : async Test.Metrics {
    Test.test(func() {
      // The five-byte string header is included in the total 16 MiB budget.
      let accepted = Text.encodeUtf8(ascii(16_777_211));
      let wire = ok(CBOR.encode(accepted));
      assert wire.size() == 16_777_216;
      assert CBOR.decode<Blob>(wire) == #ok accepted;
      let rejected = Text.encodeUtf8(ascii(16_777_212));
      expect(CBOR.encode(rejected), "limit", "", 0);
      let tooMuchInput = Text.encodeUtf8(ascii(16_777_217));
      expect(CBOR.decode<Blob>(tooMuchInput), "limit", "", 0);
      assert CBOR.encode("x" : Blob) == #ok ("\41x" : Blob);
    })
  };

  public query func test_borrowed_data_and_integer_scratch_are_retained() : async Test.Metrics {
    Test.test(func() {
      let wire : Blob = "\82\85\c2\49\01\00\00\00\00\00\00\00\00\61x\20\a1\65value\c3\49\01\00\00\00\00\00\00\00\00\42\00\ff\85\00\60\f6\a1\65value\00\40";
      let decoded = ok(CBOR.decode<[(Nat, Text, ?Int, { #value : Int }, Blob)]>(wire));
      var i = 0;
      while (i < 32) {
        ignore CBOR.encode(Array.repeat<Text>("overwrite scratch", i));
        ignore error(CBOR.decode<[Nat]>("\82\01\ff"));
        i += 1;
      };
      assert decoded == [
        (18446744073709551616, "x", ?(-1), #value(-18446744073709551617), "\00\ff"),
        (0, "", null, #value(0), ""),
      ];
    })
  };
}
