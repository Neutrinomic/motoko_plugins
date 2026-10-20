import Test "mo:test";
import ICWire "mo:fast/ICWire";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Float "mo:core/Float";
import Nat8 "mo:core/Nat8";
import Nat64 "mo:core/Nat64";
import Principal "mo:core/Principal";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";
import Prim "mo:⛔";

persistent actor {
  func ok<T>(result : ICWire.Result<T>) : T {
    switch result {
      case (#ok value) value;
      case (#err error) Runtime.trap(debug_show error);
    }
  };

  func error<T>(result : ICWire.Result<T>) : ICWire.Error {
    switch result {
      case (#ok _) Runtime.trap("expected an ICWire error");
      case (#err value) { assert value.kind.size() > 0; value };
    }
  };

  func expect<T>(result : ICWire.Result<T>, kind : Text, offset : Nat) {
    let e = error(result);
    if ((e.kind, Nat64.toNat(e.offset)) != (kind, offset)) {
      Runtime.trap("ICWire diagnostic mismatch: " # debug_show { actual = e; expected = (kind, offset) });
    };
  };

  func append(a : Blob, b : Blob) : Blob {
    let aa = Blob.toArray(a);
    let bb = Blob.toArray(b);
    Blob.fromArray(Array.tabulate<Nat8>(aa.size() + bb.size(), func(i) {
      if (i < aa.size()) aa[i] else bb[i - aa.size()]
    }))
  };

  func prefix(bytes : Blob, size : Nat) : Blob {
    let data = Blob.toArray(bytes);
    Blob.fromArray(Array.tabulate<Nat8>(size, func(i) { data[i] }))
  };

  func ascii(size : Nat) : Text {
    var remaining = size;
    var chunk = "a";
    var result = "";
    while (remaining > 0) {
      if (remaining % 2 == 1) result #= chunk;
      remaining /= 2;
      if (remaining > 0) chunk #= chunk;
    };
    result
  };

  // An independent arithmetic oracle for unsigned LEB128, with no plugin calls.
  func natWire(value : Nat) : Blob {
    var n = value;
    var width = 1;
    while (n >= 128) { n /= 128; width += 1 };
    Blob.fromArray(Array.tabulate<Nat8>(width, func(i) {
      Nat8.fromNat((value / 128 ** i) % 128 + (if (i + 1 < width) 128 else 0))
    }))
  };

  type Choice = { #_0_; #_1_ : Nat; #_2_ : Blob };
  type Row = { id : Nat; title : Text; payload : Blob; note : ??Text; choice : Choice; owner : Principal; numbers : [Int] };
  type List = ?{ value : Nat; next : List };
  type Tree = { #leaf : Nat; #branch : [Tree] };
  type Depth = { #_0_; #_1_ : Depth };

  public query func test_size_bounds_and_helpers_without_allocation() : async Test.Metrics {
    Test.test(func() {
      type Sized = { id : Nat64; words : [Nat32]; integers : [Int]; text : Text; tail : ?Sized };
      let value : Sized = {
        id = 42; words = Array.repeat<Nat32>(1234, 4096);
        integers = [-1, 63, 64, -65, 2 ** 128, -(2 ** 512)];
        text = "λ😀" # ascii(4096); tail = null;
      };
      let before = Prim.rts_total_allocation();
      let size = ICWire.estimateSize(value);
      let after = Prim.rts_total_allocation();
      assert before == after;
      let wire = ICWire.unwrap(ICWire.encode(value));
      assert size == wire.size();
      assert ICWire.toOption(ICWire.decode<Sized>(wire)) == ?value;
      assert ICWire.toOption(ICWire.decode<Sized>("")) == null;
      assert ICWire.unwrap(#ok (7 : Nat)) == 7;
      assert ICWire.estimateSize([0.0 / 0.0, 1.0 / 0.0] : [Float]) == 17;
      for (bits in [60, 61, 62, 63, 64, 65, 255, 256, 257, 1023, 1024, 1025, 28670, 28671, 28672].vals()) {
        let positive : Nat = 2 ** bits;
        let negative : Int = -(positive : Int);
        let start = Prim.rts_total_allocation();
        let positiveSize = ICWire.estimateSize(positive);
        let negativeSize = ICWire.estimateSize(negative);
        let end = Prim.rts_total_allocation();
        assert start == end;
        switch (ICWire.encode(positive)) {
          case (#ok bytes) assert positiveSize == bytes.size();
          case (#err _) assert positiveSize == 2 ** 61 - 1;
        };
        switch (ICWire.encode(negative)) {
          case (#ok bytes) assert negativeSize == bytes.size();
          case (#err _) assert negativeSize == 2 ** 61 - 1;
        };
      };
    })
  };

  func mediumNats() : [Nat] = [
    2 ** 63 - 1, 2 ** 63, 2 ** 63 + 1,
    2 ** 126 - 1, 2 ** 126, 2 ** 126 + 1,
    2 ** 189 - 1, 2 ** 189, 2 ** 189 + 1,
    2 ** 187 + 2 ** 125 + 2 ** 62 + 37,
  ];

  func mediumInts() : [Int] = [
    -(2 ** 62) - 1, -(2 ** 62), -(2 ** 62) + 1, 2 ** 62 - 1, 2 ** 62, 2 ** 62 + 1,
    -(2 ** 125) - 1, -(2 ** 125), -(2 ** 125) + 1, 2 ** 125 - 1, 2 ** 125, 2 ** 125 + 1,
    -(2 ** 188) - 1, -(2 ** 188), -(2 ** 188) + 1, 2 ** 188 - 1, 2 ** 188, 2 ** 188 + 1,
    2 ** 187 + 2 ** 125 + 2 ** 62 + 37, -(2 ** 187 + 2 ** 125 + 2 ** 62 + 37),
  ];

  public query func test_public_result_types_and_typed_wrappers() : async Test.Metrics {
    Test.test(func() {
      func encodeNat(value : Nat) : ICWire.Result<Blob> = ICWire.encode(value);
      func decodeNat(bytes : Blob) : ICWire.Result<Nat> = ICWire.decode<Nat>(bytes);
      let methods = { encode = encodeNat; decode = decodeNat };
      let callback : Nat -> ICWire.Result<Blob> = methods.encode;
      assert callback(42) == #ok "\2a";
      assert methods.decode("\2a") == #ok 42;
      let e : ICWire.Error = error(ICWire.decode<Nat>(""));
      assert e.kind == "truncated";
      var visits = 0;
      let encoded = ICWire.encode(do { visits += 1; 42 : Nat });
      assert visits == 1;
      assert encoded == #ok "\2a";
      assert ICWire.decode<Nat>(do { visits += 1; ok(encoded) }) == #ok 42;
      assert visits == 2;
    })
  };

  public query func test_null_unit_bool_options_and_tuples() : async Test.Metrics {
    Test.test(func() {
      assert ICWire.encode(()) == #ok "";
      assert ICWire.encode(null) == #ok "";
      assert ICWire.decode<()>("") == #ok ();
      assert ICWire.decode<Null>("") == #ok null;
      assert ICWire.encode(false) == #ok "\00";
      assert ICWire.decode<Bool>("\01") == #ok true;
      assert ICWire.encode(null : ?Nat) == #ok "\00";
      assert ICWire.encode(?null : ?Null) == #ok "\01";
      assert ICWire.encode(??null : ??Null) == #ok "\01\01";
      assert ICWire.decode<??Nat>("\01\00") == #ok (?null);
      assert ICWire.encode((true, 128 : Nat, (), null : ?Text)) == #ok "\01\80\01\00";
      assert ICWire.decode<(Bool, Nat, (), ?Text)>("\01\80\01\00") == #ok (true, 128, (), null);
      expect(ICWire.decode<Bool>("\02"), "bool", 0);
      expect(ICWire.decode<?Nat>("\ff"), "bool", 0);
    })
  };

  public query func test_fixed_width_integer_known_answers() : async Test.Metrics {
    Test.test(func() {
      assert ICWire.encode(255 : Nat8) == #ok "\ff";
      assert ICWire.encode(4660 : Nat16) == #ok "\34\12";
      assert ICWire.encode(0x12345678 : Nat32) == #ok "\78\56\34\12";
      assert ICWire.encode(0x0123456789abcdef : Nat64) == #ok "\ef\cd\ab\89\67\45\23\01";
      assert ICWire.decode<Nat8>("\ff") == #ok (255 : Nat8);
      assert ICWire.decode<Nat16>("\ff\ff") == #ok (65535 : Nat16);
      assert ICWire.decode<Nat32>("\ff\ff\ff\ff") == #ok (4294967295 : Nat32);
      assert ICWire.decode<Nat64>("\ff\ff\ff\ff\ff\ff\ff\ff") == #ok (18446744073709551615 : Nat64);
      assert ICWire.encode(-128 : Int8) == #ok "\80";
      assert ICWire.encode(-32768 : Int16) == #ok "\00\80";
      assert ICWire.encode(-2147483648 : Int32) == #ok "\00\00\00\80";
      assert ICWire.encode(-9223372036854775808 : Int64) == #ok "\00\00\00\00\00\00\00\80";
      assert ICWire.decode<Int8>("\ff") == #ok (-1 : Int8);
      assert ICWire.decode<Int16>("\fe\ff") == #ok (-2 : Int16);
      assert ICWire.decode<Int32>("\00\00\00\80") == #ok (-2147483648 : Int32);
      assert ICWire.decode<Int64>("\00\00\00\00\00\00\00\80") == #ok (-9223372036854775808 : Int64);
    })
  };

  public query func test_arbitrary_integer_known_answers_and_oracle() : async Test.Metrics {
    Test.test(func() {
      let values : [Nat] = [0, 1, 63, 64, 127, 128, 129, 255, 256, 16383, 16384,
        4294967295, 4294967296, 9223372036854775807, 9223372036854775808,
        18446744073709551615, 18446744073709551616, 2 ** 128 - 1, 2 ** 128, 2 ** 512 + 17];
      for (value in values.vals()) {
        let wire = natWire(value);
        assert ICWire.encode(value) == #ok wire;
        assert ICWire.decode<Nat>(wire) == #ok value;
      };
      let signed : [(Int, Blob)] = [
        (0, "\00"), (63, "\3f"), (64, "\c0\00"),
        (127, "\ff\00"), (128, "\80\01"), (-1, "\7f"),
        (-64, "\40"), (-65, "\bf\7f"), (-128, "\80\7f"),
        (-129, "\ff\7e"), (-8192, "\80\40"), (-8193, "\ff\bf\7f"),
        (18446744073709551616, "\80\80\80\80\80\80\80\80\80\02"),
        (-18446744073709551617, "\ff\ff\ff\ff\ff\ff\ff\ff\ff\7d")
      ];
      for ((value, wire) in signed.vals()) {
        assert ICWire.encode(value) == #ok wire;
        assert ICWire.decode<Int>(wire) == #ok value;
      };
      for (value in mediumNats().vals()) {
        assert ICWire.encode(value) == #ok (natWire(value));
        assert ICWire.decode<Nat>(natWire(value)) == #ok value;
      };
      // Independent endpoint byte patterns across 9/10, 18/19 and 27/28 LEB bytes.
      for (width in ([9, 18, 27] : [Nat]).vals()) {
        let bound : Int = 2 ** (width * 7 - 1);
        let positive = Blob.fromArray(Array.tabulate<Nat8>(width, func(i) { if (i + 1 == width) 63 else 255 }));
        let nextPositive = Blob.fromArray(Array.tabulate<Nat8>(width + 1, func(i) {
          if (i == width) 0 else if (i + 1 == width) 192 else 128
        }));
        let negative = Blob.fromArray(Array.tabulate<Nat8>(width, func(i) { if (i + 1 == width) 64 else 128 }));
        let nextNegative = Blob.fromArray(Array.tabulate<Nat8>(width + 1, func(i) {
          if (i == width) 127 else if (i + 1 == width) 191 else 255
        }));
        assert ICWire.encode(bound - 1) == #ok positive;
        assert ICWire.decode<Int>(positive) == #ok (bound - 1);
        assert ICWire.encode(bound) == #ok nextPositive;
        assert ICWire.decode<Int>(nextPositive) == #ok bound;
        assert ICWire.encode(-bound) == #ok negative;
        assert ICWire.decode<Int>(negative) == #ok (-bound);
        assert ICWire.encode(-bound - 1) == #ok nextNegative;
        assert ICWire.decode<Int>(nextNegative) == #ok (-bound - 1);
      };
      var state = 1729;
      var i = 0;
      while (i < 128) {
        state := (state * 6364136223846793005 + 1442695040888963407) % (2 ** 128);
        assert ICWire.encode(state) == #ok (natWire(state));
        assert ICWire.decode<Nat>(natWire(state)) == #ok state;
        i += 1;
      };
    })
  };

  public query func test_nonminimal_and_truncated_integer_rejection() : async Test.Metrics {
    Test.test(func() {
      for (wire in (["\80\00", "\81\00", "\ff\00", "\80\81\00"] : [Blob]).vals()) {
        expect(ICWire.decode<Nat>(wire), "canonical", 0);
      };
      for (wire in (["\80\00", "\bf\00", "\ff\7f", "\c0\7f"] : [Blob]).vals()) {
        expect(ICWire.decode<Int>(wire), "canonical", 0);
      };
      expect(ICWire.decode<Nat>("\80"), "truncated", 1);
      expect(ICWire.decode<Int>("\80\80"), "truncated", 2);
      expect(ICWire.decode<Nat64>("\01\02\03"), "truncated", 0);
      for (width in ([10, 18, 19, 27, 28] : [Nat]).vals()) {
        let redundantZero = Blob.fromArray(Array.tabulate<Nat8>(width, func(i) { if (i + 1 == width) 0 else 128 }));
        let redundantSign = Blob.fromArray(Array.tabulate<Nat8>(width, func(i) { if (i + 1 == width) 127 else 255 }));
        expect(ICWire.decode<Nat>(redundantZero), "canonical", 0);
        expect(ICWire.decode<Int>(redundantZero), "canonical", 0);
        expect(ICWire.decode<Int>(redundantSign), "canonical", 0);
        expect(ICWire.decode<Int>(Blob.fromArray(Array.repeat<Nat8>(128, width))), "truncated", width);
      };
      assert ICWire.decode<Int>("\ff\00") == #ok 127;
      assert ICWire.decode<Int>("\c0\00") == #ok 64;
    })
  };

  public query func test_float_widths_signed_zero_and_finite_values() : async Test.Metrics {
    Test.test(func() {
      assert ICWire.encode(1.5 : Float) == #ok "\00\00\00\00\00\00\f8\3f";
      assert ICWire.encode(Float.toFloat32(1.5)) == #ok "\00\00\c0\3f";
      assert ICWire.encode(-0.0 : Float) == #ok "\00\00\00\00\00\00\00\80";
      assert ICWire.encode(Float.toFloat32(-0.0)) == #ok "\00\00\00\80";
      assert ICWire.encode(ok(ICWire.decode<Float>("\00\00\00\00\00\00\00\80"))) == #ok "\00\00\00\00\00\00\00\80";
      assert ICWire.encode(ok(ICWire.decode<Float32>("\00\00\00\80"))) == #ok "\00\00\00\80";
      for (wire in (["\01\00\00\00\00\00\00\00", "\ff\ff\ff\ff\ff\ff\ef\7f"] : [Blob]).vals()) {
        assert ICWire.encode(ok(ICWire.decode<Float>(wire))) == #ok wire;
      };
      for (wire in (["\01\00\00\00", "\ff\ff\7f\7f"] : [Blob]).vals()) {
        assert ICWire.encode(ok(ICWire.decode<Float32>(wire))) == #ok wire;
      };
      for (wire in (["\00\00\00\00\00\00\f0\7f", "\00\00\00\00\00\00\f0\ff", "\01\00\00\00\00\00\f8\7f"] : [Blob]).vals()) {
        expect(ICWire.decode<Float>(wire), "float", 0);
      };
      for (wire in (["\00\00\80\7f", "\00\00\80\ff", "\01\00\c0\7f"] : [Blob]).vals()) {
        expect(ICWire.decode<Float32>(wire), "float", 0);
      };
      assert error(ICWire.encode(0.0 / 0.0 : Float)).kind == "float";
      assert error(ICWire.encode(1.0 / 0.0 : Float)).kind == "float";
      assert error(ICWire.encode(Float.toFloat32(-1.0 / 0.0))).kind == "float";
      let nan : Float = 0.0 / 0.0;
      let infinity : Float = 1.0 / 0.0;
      let nan32 = Float.toFloat32(nan);
      expect(ICWire.encode(nan), "float", 0);
      expect(ICWire.encode(nan32), "float", 0);
      expect(ICWire.encode([1.5, nan, 2.5] : [Float]), "float", 9);
      expect(ICWire.encode([Float.toFloat32(1.5), nan32, Float.toFloat32(2.5)]), "float", 5);
      expect(ICWire.encode({ a = 7 : Nat8; b = infinity; z = "following" : Text }), "float", 1);
      expect(ICWire.encode({ a = 7 : Nat8; b = { a = [1.5, nan]; z = 9 : Nat }; z = "following" : Blob }), "float", 10);
      expect(ICWire.encode((7 : Nat8, ?infinity, "following" : Blob)), "float", 2);
      expect(ICWire.encode({ a = ?(1.5 : Float, nan32); z = 7 : Nat8 }), "float", 9);
      type FloatTree = { #_0_ : Float; #_1_ : { a : FloatTree; z : Blob } };
      expect(ICWire.encode(#_1_({ a = #_0_(nan); z = "following" }) : FloatTree), "float", 2);
      type FloatA = { a : Nat8; b : FloatB; z : Blob };
      type FloatB = { #_0_ : Float; #_1_ : FloatA };
      let mutual : FloatA = { a = 7; b = #_1_({ a = 8; b = #_0_(nan); z = "inner" }); z = "outer" };
      expect(ICWire.encode(mutual), "float", 4);
      assert ICWire.encode(null : ?Float) == #ok "\00";
      assert ICWire.encode([] : [Float]) == #ok "\00";
      assert ICWire.encode([] : [Float32]) == #ok "\00";
      assert ICWire.decode<[Float]>("\00") == #ok ([]);
      assert ICWire.decode<[Float32]>("\00") == #ok ([]);
      let zero64 : Blob = "\00\00\00\00\00\00\00\00";
      let inf64 : Blob = "\00\00\00\00\00\00\f0\7f";
      let nan64 : Blob = "\01\00\00\00\00\00\f8\7f";
      let zero32 : Blob = "\00\00\00\00";
      let inf32 : Blob = "\00\00\80\7f";
      let bad32 : Blob = "\01\00\c0\7f";
      expect(ICWire.decode<[Float]>(append("\03", inf64)), "float", 1);
      expect(ICWire.decode<[Float]>(append("\03", append(zero64, nan64))), "float", 9);
      expect(ICWire.decode<[Float]>(append("\04", append(zero64, append(zero64, inf64)))), "float", 17);
      expect(ICWire.decode<[Float]>(append("\03", append(zero64, append(zero64, inf64)))), "float", 17);
      expect(ICWire.decode<[Float32]>(append("\03", inf32)), "float", 1);
      expect(ICWire.decode<[Float32]>(append("\03", append(zero32, bad32))), "float", 5);
      expect(ICWire.decode<[Float32]>(append("\04", append(zero32, append(zero32, inf32)))), "float", 9);
      expect(ICWire.decode<[Float32]>(append("\03", append(zero32, append(zero32, inf32)))), "float", 9);
      expect(ICWire.decode<[Float]>(append("\03", append(zero64, append(zero64, "\00\00\00\00")))), "truncated", 17);
      expect(ICWire.decode<[Float32]>(append("\03", append(zero32, append(zero32, "\00\00")))), "truncated", 9);
      let finite64 : Blob = "\03\00\00\00\00\00\00\f8\3f\00\00\00\00\00\00\00\80\01\00\00\00\00\00\00\00";
      let finite32 : Blob = "\03\00\00\c0\3f\00\00\00\80\01\00\00\00";
      assert ICWire.encode(ok(ICWire.decode<[Float]>(finite64))) == #ok finite64;
      assert ICWire.encode(ok(ICWire.decode<[Float32]>(finite32))) == #ok finite32;
    })
  };

  public query func test_text_blob_unicode_and_char_wire_values() : async Test.Metrics {
    Test.test(func() {
      assert ICWire.encode("a\u{0}λ😀" : Text) == #ok "\08a\00\ce\bb\f0\9f\98\80";
      assert ICWire.decode<Text>("\08a\00\ce\bb\f0\9f\98\80") == #ok "a\u{0}λ😀";
      assert ICWire.encode("\00\ff" : Blob) == #ok "\02\00\ff";
      assert ICWire.decode<Blob>("\02\00\ff") == #ok "\00\ff";
      assert ICWire.encode('😀') == #ok "\00\f6\01\00";
      assert ICWire.decode<Char>("\ff\ff\10\00") == #ok '\u{10ffff}';
      assert ICWire.decode<Char>("\00\00\00\00") == #ok '\u{0}';
      expect(ICWire.decode<Char>("\00\d8\00\00"), "char", 0);
      expect(ICWire.decode<Char>("\ff\df\00\00"), "char", 0);
      expect(ICWire.decode<Char>("\00\00\11\00"), "char", 0);
      assert ICWire.encode("é" : Text) != ICWire.encode("e\u{301}" : Text);
      assert ICWire.decode<Text>("\00") == #ok "";
    })
  };

  public query func test_invalid_utf8_and_principal_bounds() : async Test.Metrics {
    Test.test(func() {
      let invalid : [Blob] = ["\80", "\c0\80", "\c1\bf", "\c2", "\e0\80\80", "\ed\a0\80", "\ed\bf\bf", "\f0\80\80\80", "\f4\90\80\80", "\f5\80\80\80", "\ff"];
      for (payload in invalid.vals()) {
        let wire = append(natWire(payload.size()), payload);
        expect(ICWire.decode<Text>(wire), "utf8", 0);
        assert ICWire.decode<Blob>(wire) == #ok payload;
      };
      assert ICWire.encode(Principal.fromText("aaaaa-aa")) == #ok "\00";
      assert ICWire.encode(Principal.fromText("2vxsx-fae")) == #ok "\01\04";
      assert ICWire.decode<Principal>("\01\04") == #ok (Principal.fromText("2vxsx-fae"));
      let payload = Blob.fromArray(Array.tabulate<Nat8>(29, Nat8.fromNat));
      let principal = Principal.fromBlob(payload);
      let wire = append("\1d", payload);
      assert ICWire.encode(principal) == #ok wire;
      assert ICWire.decode<Principal>(wire) == #ok principal;
      expect(ICWire.decode<Principal>(append("\1e", append(payload, "\00"))), "principal", 0);
      expect(ICWire.decode<Principal>("\1e"), "principal", 0);
    })
  };

  public query func test_arrays_empty_values_and_nested_collections() : async Test.Metrics {
    Test.test(func() {
      assert ICWire.encode([] : [Nat]) == #ok "\00";
      assert ICWire.encode([(), (), ()]) == #ok "\03";
      assert ICWire.decode<[()]>("\03") == #ok ([(), (), ()]);
      assert ICWire.encode([0, 255] : [Nat8]) == #ok "\02\00\ff";
      assert ICWire.decode<[Nat8]>("\02\00\ff") == #ok ([0, 255]);
      assert ICWire.encode([[1 : Nat, 128], [], [2]]) == #ok "\03\02\01\80\01\00\01\02";
      assert ICWire.decode<[[Nat]]>("\03\02\01\80\01\00\01\02") == #ok ([[1, 128], [], [2]]);
      assert ICWire.encode([null, ?null, ??7] : [??Nat]) == #ok "\03\00\01\00\01\01\07";
      assert ICWire.decode<[??Nat]>("\03\00\01\00\01\01\07") == #ok ([null, ?null, ??7]);
      assert ICWire.encode([false, true, false, true, true]) == #ok "\05\00\01\00\01\01";
      assert ICWire.decode<[Bool]>("\05\00\01\00\01\01") == #ok ([false, true, false, true, true]);
      assert ICWire.decode<[Bool]>("\00") == #ok ([]);
      assert ICWire.decode<{ a : [Bool]; z : Nat16 }>("\03\00\01\00\34\12") == #ok { a = [false, true, false]; z = 4660 };
      // Report an invalid existing element before a later missing array tail.
      expect(ICWire.decode<[Bool]>("\04\02"), "bool", 1);
      expect(ICWire.decode<[Bool]>("\04\00\02"), "bool", 2);
      expect(ICWire.decode<[Bool]>("\04\00\01\02"), "bool", 3);
      expect(ICWire.decode<[Bool]>("\03\00\01\02"), "bool", 3);
      expect(ICWire.decode<[Bool]>("\04\00\01\00"), "truncated", 4);
      expect(ICWire.decode<[Bool]>("\01\02\00"), "bool", 1);
      expect(ICWire.decode<[Bool]>("\01\00\02"), "trailing", 2);
      expect(ICWire.decode<[Bool]>("\00\02"), "trailing", 1);
      type Uninhabited = { next : Uninhabited };
      assert ICWire.decode<[Uninhabited]>("\00") == #ok ([]);
    })
  };

  public query func test_fixed_width_arrays_and_partial_final_words() : async Test.Metrics {
    Test.test(func() {
      assert ICWire.encode([0, 255] : [Nat8]) == #ok "\02\00\ff";
      assert ICWire.decode<[Nat8]>("\02\00\ff") == #ok ([0, 255]);
      assert ICWire.encode([4660, 65535] : [Nat16]) == #ok "\02\34\12\ff\ff";
      assert ICWire.decode<[Nat16]>("\02\34\12\ff\ff") == #ok ([4660, 65535]);
      assert ICWire.encode([0x12345678, 4294967295] : [Nat32]) == #ok "\02\78\56\34\12\ff\ff\ff\ff";
      assert ICWire.decode<[Nat32]>("\02\78\56\34\12\ff\ff\ff\ff") == #ok ([0x12345678, 4294967295]);
      assert ICWire.encode([0x0123456789abcdef, 18446744073709551615] : [Nat64]) == #ok "\02\ef\cd\ab\89\67\45\23\01\ff\ff\ff\ff\ff\ff\ff\ff";
      assert ICWire.decode<[Nat64]>("\02\ef\cd\ab\89\67\45\23\01\ff\ff\ff\ff\ff\ff\ff\ff") == #ok ([0x0123456789abcdef, 18446744073709551615]);
      assert ICWire.encode([-128, 127] : [Int8]) == #ok "\02\80\7f";
      assert ICWire.decode<[Int8]>("\02\80\7f") == #ok ([-128, 127]);
      assert ICWire.encode([-32768, 32767] : [Int16]) == #ok "\02\00\80\ff\7f";
      assert ICWire.decode<[Int16]>("\02\00\80\ff\7f") == #ok ([-32768, 32767]);
      assert ICWire.encode([-2147483648, 2147483647] : [Int32]) == #ok "\02\00\00\00\80\ff\ff\ff\7f";
      assert ICWire.decode<[Int32]>("\02\00\00\00\80\ff\ff\ff\7f") == #ok ([-2147483648, 2147483647]);
      assert ICWire.encode([-9223372036854775808, 9223372036854775807] : [Int64]) == #ok "\02\00\00\00\00\00\00\00\80\ff\ff\ff\ff\ff\ff\ff\7f";
      assert ICWire.decode<[Int64]>("\02\00\00\00\00\00\00\00\80\ff\ff\ff\ff\ff\ff\ff\7f") == #ok ([-9223372036854775808, 9223372036854775807]);
      expect(ICWire.decode<[Nat8]>("\02\01"), "truncated", 2);
      expect(ICWire.decode<[Int8]>("\02\ff"), "truncated", 2);
      expect(ICWire.decode<[Nat16]>("\02\01\00\02"), "truncated", 3);
      expect(ICWire.decode<[Int16]>("\02\ff\ff\ff"), "truncated", 3);
      expect(ICWire.decode<[Nat32]>("\02\01\00\00\00\02\00\00"), "truncated", 5);
      expect(ICWire.decode<[Int32]>("\02\ff\ff\ff\ff\ff\ff\ff"), "truncated", 5);
      expect(ICWire.decode<[Nat64]>("\02\01\00\00\00\00\00\00\00\02\00\00\00\00\00\00"), "truncated", 9);
      expect(ICWire.decode<[Int64]>("\02\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"), "truncated", 9);
      assert ICWire.decode<[Nat64]>("\00") == #ok ([]);
      assert ICWire.decode<[Int64]>("\00") == #ok ([]);
    })
  };

  public query func test_positional_records_schema_order_and_zero_width_fields() : async Test.Metrics {
    Test.test(func() {
      assert ICWire.encode({ x = 7 : Nat }) == #ok "\07";
      assert ICWire.decode<{ x : Nat }>("\07") == #ok { x = 7 };
      assert ICWire.encode({ _120_ = 7 : Nat }) == ICWire.encode({ x = 7 : Nat });
      assert ICWire.encode({ type_ = true }) == ICWire.encode({ _1292432058_ = true });
      assert ICWire.encode({ z = false; a = 128 : Nat }) == #ok "\80\01\00";
      assert ICWire.encode({ a = 128 : Nat; z = false }) == #ok "\80\01\00";
      assert ICWire.decode<{ z : Bool; a : Nat }>("\80\01\00") == #ok { z = false; a = 128 };
      assert ICWire.encode({ _4294967295_ = (); _0_ = null }) == #ok "";
      assert ICWire.decode<{ _4294967295_ : (); _0_ : Null }>("") == #ok { _4294967295_ = (); _0_ = null };
      assert ICWire.encode({ _4294967295_ = 2 : Nat8; _0_ = 1 : Nat8 }) == #ok "\01\02";
      assert ICWire.encode({ a = 7 : Nat8; z = true }) == #ok "\07\01";
      assert ICWire.encode({ a = true; z = 7 : Nat8 }) == #ok "\01\07";
    })
  };

  public query func test_record_optional_fields_have_explicit_presence() : async Test.Metrics {
    Test.test(func() {
      type Exact = { a : ?Text; b : Nat; m : ??Nat; y : Bool; z : ?Blob };
      let absent : Exact = { a = null; b = 7; m = null; y = true; z = null };
      let present : Exact = { a = ?"new"; b = 7; m = ?null; y = true; z = ?"\ff" };
      assert ICWire.encode(absent) == #ok "\00\07\00\01\00";
      assert ICWire.decode<Exact>("\00\07\00\01\00") == #ok absent;
      assert ICWire.encode(present) == #ok "\01\03new\07\01\00\01\01\01\ff";
      assert ICWire.decode<Exact>("\01\03new\07\01\00\01\01\01\ff") == #ok present;
      assert ICWire.encode({ x = null : ?Null }) == #ok "\00";
      assert ICWire.encode({ x = ?null : ?Null }) == #ok "\01";
      assert ICWire.decode<{ x : ??Nat }>("\01\00") == #ok { x = ?null };
      expect(ICWire.decode<{ x : ?Nat }>(""), "truncated", 0);
      expect(ICWire.decode<{ x : ?Nat }>("\02"), "bool", 0);
      // Adding even an absent optional changes this exact positional schema.
      assert ICWire.encode({ a = 7 : Nat }) == #ok "\07";
      assert ICWire.encode({ a = 7 : Nat; b = null : ?Nat }) == #ok "\07\00";
      expect(ICWire.decode<{ a : Nat }>("\07\00"), "trailing", 1);
      expect(ICWire.decode<{ a : Nat; b : ?Nat }>("\07"), "truncated", 1);
    })
  };

  public query func test_variant_ordinals_follow_exact_sorted_schema() : async Test.Metrics {
    Test.test(func() {
      type Narrow = { #m : Nat; #z };
      type Full = { #a : Text; #m : Nat; #n : Blob; #z; #_4294967295_ };
      assert ICWire.encode(#m(128) : Narrow) == #ok "\00\80\01";
      assert ICWire.encode(#m(128) : Full) == #ok "\01\80\01";
      assert ICWire.decode<Narrow>("\00\80\01") == #ok (#m(128));
      assert ICWire.decode<Full>("\01\80\01") == #ok (#m(128));
      assert ICWire.encode(#z : Narrow) == #ok "\01";
      assert ICWire.encode(#z : Full) == #ok "\03";
      assert ICWire.encode(#_4294967295_ : Full) == #ok "\04";
      assert ICWire.decode<Full>("\04") == #ok (#_4294967295_);
      expect(ICWire.decode<Narrow>("\02"), "variant", 1);
      expect(ICWire.decode<Full>("\05"), "variant", 1);
      expect(ICWire.decode<Full>("\80\00"), "canonical", 0);
      expect(ICWire.decode<Full>("\80"), "truncated", 1);
      expect(ICWire.decode<Full>("\80\80\80\80\10"), "canonical", 0);
      type Many = {
        #_0_; #_1_; #_2_; #_3_; #_4_; #_5_; #_6_; #_7_; #_8_; #_9_; #_10_; #_11_; #_12_; #_13_; #_14_; #_15_;
        #_16_; #_17_; #_18_; #_19_; #_20_; #_21_; #_22_; #_23_; #_24_; #_25_; #_26_; #_27_; #_28_; #_29_; #_30_; #_31_;
        #_32_; #_33_; #_34_; #_35_; #_36_; #_37_; #_38_; #_39_; #_40_; #_41_; #_42_; #_43_; #_44_; #_45_; #_46_; #_47_;
        #_48_; #_49_; #_50_; #_51_; #_52_; #_53_; #_54_; #_55_; #_56_; #_57_; #_58_; #_59_; #_60_; #_61_; #_62_; #_63_;
        #_64_; #_65_; #_66_; #_67_; #_68_; #_69_; #_70_; #_71_; #_72_; #_73_; #_74_; #_75_; #_76_; #_77_; #_78_; #_79_;
        #_80_; #_81_; #_82_; #_83_; #_84_; #_85_; #_86_; #_87_; #_88_; #_89_; #_90_; #_91_; #_92_; #_93_; #_94_; #_95_;
        #_96_; #_97_; #_98_; #_99_; #_100_; #_101_; #_102_; #_103_; #_104_; #_105_; #_106_; #_107_; #_108_; #_109_; #_110_; #_111_;
        #_112_; #_113_; #_114_; #_115_; #_116_; #_117_; #_118_; #_119_; #_120_; #_121_; #_122_; #_123_; #_124_; #_125_; #_126_; #_127_;
        #_128_; #_129_;
      };
      assert ICWire.encode(#_128_ : Many) == #ok "\80\01";
      assert ICWire.decode<Many>("\80\01") == #ok (#_128_);
      assert ICWire.encode(#_129_ : Many) == #ok "\81\01";
      expect(ICWire.decode<Many>("\82\01"), "variant", 2);
    })
  };

  public query func test_recursive_and_mutually_recursive_values() : async Test.Metrics {
    Test.test(func() {
      let list : List = ?{ value = 2 ** 128; next = ?{ value = 17; next = null } };
      assert ICWire.decode<List>(ok(ICWire.encode(list))) == #ok list;
      let tree : Tree = #branch([#leaf(1), #branch([]), #branch([#leaf(2), #leaf(2 ** 128)])]);
      assert ICWire.decode<Tree>(ok(ICWire.encode(tree))) == #ok tree;
      type A = { title : Text; next : ?B };
      type B = { #back : A; #end : Blob };
      let value : A = { title = "outer"; next = ?(#back({ title = "inner"; next = ?(#end("\00\ff")) })) };
      assert ICWire.decode<A>(ok(ICWire.encode(value))) == #ok value;
      let chain : Depth = #_1_(#_1_(#_0_));
      assert ICWire.encode(chain) == #ok "\01\01\00";
      assert ICWire.decode<Depth>("\01\01\00") == #ok chain;
    })
  };

  public query func test_positional_record_truncation_and_nested_bulk_arrays() : async Test.Metrics {
    Test.test(func() {
      type R = { a : [Nat16]; b : Int8; z : [Nat64] };
      let value : R = { a = [1, 65535]; b = -128; z = [0x0123456789abcdef] };
      let wire : Blob = "\02\01\00\ff\ff\80\01\ef\cd\ab\89\67\45\23\01";
      assert ICWire.encode(value) == #ok wire;
      assert ICWire.decode<R>(wire) == #ok value;
      assert ICWire.encode({ a = [] : [Int64]; b = 42 : Nat; z = [-1, 2] : [Int32] }) == #ok "\00\2a\02\ff\ff\ff\ff\02\00\00\00";
      assert ICWire.decode<{ a : [Int64]; b : Nat; z : [Int32] }>("\00\2a\02\ff\ff\ff\ff\02\00\00\00") == #ok { a = []; b = 42; z = [-1, 2] };
      expect(ICWire.decode<R>("\02\01\00\ff"), "truncated", 3);
      expect(ICWire.decode<R>("\02\01\00\ff\ff"), "truncated", 5);
      expect(ICWire.decode<R>("\02\01\00\ff\ff\80\01\ef\cd"), "truncated", 7);
      expect(ICWire.decode<{ a : Nat; z : Text }>("\07\02a"), "truncated", 2);
      expect(ICWire.decode<{ a : Nat; z : ?Nat }>("\07\02"), "bool", 1);
      expect(ICWire.decode<{ a : Nat; z : Bool }>("\07"), "truncated", 1);
      expect(ICWire.decode<{ a : Nat }>("\07\01"), "trailing", 1);
    })
  };

  public query func test_compact_length_prefixes_truncation_and_trailing_bytes() : async Test.Metrics {
    Test.test(func() {
      assert ICWire.encode(()) == #ok "";
      expect(ICWire.decode<()>("\00"), "trailing", 0);
      expect(ICWire.decode<Nat>("\00\01"), "trailing", 1);
      let wire : Blob = "\01\80\01";
      assert ICWire.decode<{ x : ?Nat }>(wire) == #ok { x = ?128 };
      var size = 0;
      while (size < wire.size()) {
        assert error(ICWire.decode<{ x : ?Nat }>(prefix(wire, size))).kind == "truncated";
        size += 1;
      };
      for (count in ([0, 1, 127, 128, 255, 16383, 16384] : [Nat]).vals()) {
        let payload = ascii(count);
        let expected = append(natWire(count), Text.encodeUtf8(payload));
        assert ICWire.encode(payload) == #ok expected;
        assert ICWire.decode<Text>(expected) == #ok payload;
        assert ICWire.encode(Array.repeat<()>((), count)) == #ok (natWire(count));
      };
      expect(ICWire.decode<Text>("\02a"), "truncated", 1);
      expect(ICWire.decode<[Bool]>("\02\01"), "truncated", 2);
      expect(ICWire.decode<Blob>("\80\00"), "canonical", 0);
      expect(ICWire.decode<[()]>("\81\00"), "canonical", 0);
      expect(ICWire.decode<Text>("\80"), "truncated", 1);
      expect(ICWire.decode<Blob>("\80\80\80\80\10"), "canonical", 0);
      expect(ICWire.decode<[()]>("\ff\ff\ff\ff\1f"), "canonical", 0);
      assert ICWire.decode<Nat>("\80\80\80\80\10") == #ok 4294967296;
      assert ICWire.decode<Nat>("\2a") == #ok 42;
    })
  };

  public query func test_all_byte_bool_and_option_acceptance_oracle() : async Test.Metrics {
    Test.test(func() {
      var n = 0;
      while (n < 256) {
        let wire = Blob.fromArray([Nat8.fromNat(n)]);
        if (n < 2) {
          assert ICWire.decode<Bool>(wire) == #ok (n == 1);
          assert ICWire.decode<?Null>(wire) == #ok (if (n == 1) ?null else null);
        } else {
          expect(ICWire.decode<Bool>(wire), "bool", 0);
          expect(ICWire.decode<?Null>(wire), "bool", 0);
        };
        if (n < 128) assert ICWire.decode<Nat>(wire) == #ok n
        else assert error(ICWire.decode<Nat>(wire)).kind == "truncated";
        n += 1;
      };
      assert ICWire.encode(true) == #ok "\01";
    })
  };

  public query func test_declared_collection_limits_before_allocation() : async Test.Metrics {
    Test.test(func() {
      expect(ICWire.decode<[()]>("\ff\ff\ff\ff\0f"), "limit", 5);
      expect(ICWire.decode<[Null]>("\c0\84\3d"), "limit", 3);
      expect(ICWire.decode<[Nat8]>("\c0\84\3d"), "limit", 3);
      expect(ICWire.decode<[[()]]>("\02\bf\84\3d"), "limit", 4);
      expect(ICWire.decode<[Bool]>("\bf\84\3d"), "truncated", 3);
      expect(ICWire.decode<Blob>("\ff\ff\ff\ff\0f"), "limit", 0);
      assert ICWire.decode<[()]>("\01") == #ok ([()]);
    })
  };

  public query func test_depth_limit_at_boundary_and_recovery() : async Test.Metrics {
    Test.test(func() {
      var chain : Depth = #_0_;
      var i = 0;
      while (i < 126) { chain := #_1_(chain); i += 1 };
      let wire = ok(ICWire.encode(chain));
      assert wire.size() == 127;
      assert ICWire.decode<Depth>(wire) == #ok chain;
      assert error(ICWire.encode(#_1_(chain) : Depth)).kind == "limit";
      let tooDeep = Blob.fromArray(Array.tabulate<Nat8>(128, func(i) { if (i < 127) 1 else 0 }));
      assert error(ICWire.decode<Depth>(tooDeep)).kind == "limit";
      assert ICWire.decode<Depth>("\00") == #ok (#_0_);
    })
  };

  public func test_integer_byte_limit_at_boundary_and_recovery() : async Test.Metrics {
    Test.test(func() {
      let largest : Nat = 2 ** 28672 - 1;
      let positive = Blob.fromArray(Array.tabulate<Nat8>(4096, func(i) { if (i == 4095) 127 else 255 }));
      assert ICWire.encode(largest) == #ok positive;
      assert ICWire.decode<Nat>(positive) == #ok largest;
      let signedLargest : Int = 2 ** 28671 - 1;
      let signedWire = Blob.fromArray(Array.tabulate<Nat8>(4096, func(i) { if (i == 4095) 63 else 255 }));
      assert ICWire.encode(signedLargest) == #ok signedWire;
      assert ICWire.decode<Int>(signedWire) == #ok signedLargest;
      let smallest : Int = -(2 ** 28671);
      let negative = Blob.fromArray(Array.tabulate<Nat8>(4096, func(i) { if (i == 4095) 64 else 128 }));
      assert ICWire.encode(smallest) == #ok negative;
      assert ICWire.decode<Int>(negative) == #ok smallest;
      assert error(ICWire.encode(largest + 1)).kind == "limit";
      assert error(ICWire.encode(signedLargest + 1)).kind == "limit";
      assert error(ICWire.encode(smallest - 1)).kind == "limit";
      let oversized = Blob.fromArray(Array.tabulate<Nat8>(4097, func(i) { if (i == 4096) 1 else 128 }));
      expect(ICWire.decode<Nat>(oversized), "limit", 0);
      expect(ICWire.decode<Int>(oversized), "limit", 0);
      assert ICWire.decode<Int>("\7f") == #ok (-1);
    })
  };

  public func test_zero_byte_array_item_budget_at_boundary() : async Test.Metrics {
    Test.test(func() {
      // The array itself consumes one visit, even though unit elements use no bytes.
      let units = ok(ICWire.decode<[()]>("\bf\84\3d"));
      assert units.size() == 999_999;
      assert ICWire.encode(units) == #ok "\bf\84\3d";
      assert ICWire.estimateSize(units) == 3;
      let excess = Array.repeat<()>((), 1_000_000);
      assert error(ICWire.encode(excess)).kind == "limit";
      assert ICWire.estimateSize(excess) == 2 ** 61 - 1;
      let nan : Float = 0.0 / 0.0;
      expect(ICWire.encode((nan, excess)), "float", 0);
      expect(ICWire.encode((excess, nan)), "limit", 0);
      expect(ICWire.encode(Array.repeat<Float>(nan, 1_000_000)), "limit", 0);
      expect(ICWire.decode<[Float]>("\c0\84\3d"), "limit", 3);
      expect(ICWire.decode<[Float32]>("\c0\84\3d"), "limit", 3);
      expect(ICWire.decode<[()]>("\c0\84\3d"), "limit", 3);
      // Records count their typed values, without a separate field-frame charge.
      type Budget = { a : [()]; z : Null };
      let record = ok(ICWire.decode<Budget>("\bd\84\3d"));
      assert record.a.size() == 999_997;
      assert ICWire.encode(record) == #ok "\bd\84\3d";
      assert ICWire.estimateSize(record) == 3;
      expect(ICWire.decode<Budget>("\be\84\3d"), "limit", 3);
      assert error(ICWire.encode({ a = Array.repeat<()>((), 999_998); z = null })).kind == "limit";
      assert ICWire.estimateSize({ a = Array.repeat<()>((), 999_998); z = null }) == 2 ** 61 - 1;
      assert ICWire.decode<[()]>("\02") == #ok ([(), ()]);
    })
  };

  public func test_complete_message_byte_budget_at_boundary() : async Test.Metrics {
    Test.test(func() {
      // This payload uses a four-byte ULEB length prefix and no envelope.
      let payload = ascii(16 * 1024 * 1024 - 4);
      let wire = ok(ICWire.encode(payload));
      assert wire.size() == 16 * 1024 * 1024;
      assert ICWire.estimateSize(payload) == wire.size();
      assert ok(ICWire.decode<Text>(wire)) == payload;
      assert error(ICWire.encode(payload # "a")).kind == "limit";
      assert ICWire.estimateSize(payload # "a") == 2 ** 61 - 1;
      let nan : Float = 0.0 / 0.0;
      expect(ICWire.encode(([nan], payload)), "float", 1);
      expect(ICWire.encode((payload, [nan])), "limit", 16 * 1024 * 1024);
      expect(ICWire.decode<()>(Text.encodeUtf8(ascii(16 * 1024 * 1024 + 1))), "limit", 0);
      assert ICWire.encode("recovered" : Text) == #ok "\09recovered";
    })
  };

  public query func test_seeded_composite_roundtrips_and_failure_recovery() : async Test.Metrics {
    Test.test(func() {
      var state = 1729;
      var sample = 0;
      while (sample < 100) {
        state := (state * 48271) % 2147483647;
        let row : Row = {
          id = state * 2 ** 128;
          title = if (sample % 2 == 0) "λ😀\u{0}" else "plain";
          payload = Blob.fromArray(Array.tabulate<Nat8>(sample, func(i) { Nat8.fromNat((i * 17 + sample) % 256) }));
          note = if (sample % 3 == 0) null else if (sample % 3 == 1) ?null else ??"present";
          choice = if (sample % 2 == 0) #_1_(state) else #_2_("\00\ff");
          owner = Principal.fromText("2vxsx-fae");
          numbers = [-(state : Int), state, -(2 ** 128), 2 ** 128];
        };
        let wire = ok(ICWire.encode(row));
        assert ICWire.estimateSize(row) >= wire.size();
        assert ICWire.decode<Row>(wire) == #ok row;
        assert ICWire.encode(ok(ICWire.decode<Row>(wire))) == #ok wire;
        ignore error(ICWire.decode<Row>(prefix(wire, wire.size() - 1)));
        assert ICWire.decode<Row>(wire) == #ok row;
        sample += 1;
      };
    })
  };

  transient var retained : ?Row = null;
  transient var retainedWire : Blob = "";
  transient var retainedError : ?ICWire.Error = null;
  transient var retainedNats : [Nat] = [];
  transient var retainedInts : [Int] = [];
  transient var retainedBools : [Bool] = [];
  transient var retainedFloats : [Float] = [];
  transient var retainedFloat32s : [Float32] = [];

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

  public func test_decoded_values_and_errors_survive_messages_and_confirmed_gc() : async Test.Metrics {
    let expected : Row = {
      id = 2 ** 256 + 17; title = "retained λ😀"; payload = "\00\01\fe\ff";
      note = ??"still present"; choice = #_2_("shared scratch must not escape");
      owner = Principal.fromText("2vxsx-fae"); numbers = [-(2 ** 256) - 1, 2 ** 128, -65];
    };
    // Deliberately reserve spare capacity so finalization leaves a filler tail.
    // The retained logical bytes and later failed writes must survive real GC.
    retainedWire := ok(ICWire.encodeBounded(expected, 65_536));
    assert ICWire.encode(expected) == #ok retainedWire;
    expect(ICWire.encodeBounded(expected, 1), "limit", 0);
    retained := ?ok(ICWire.decode<Row>(retainedWire));
    retainedError := ?error(ICWire.decode<Text>("\01\ff"));
    let natBoundaries = mediumNats();
    let intBoundaries = mediumInts();
    let expectedNats = Array.tabulate<Nat>(natBoundaries.size() * 3, func(i) { natBoundaries[i % natBoundaries.size()] });
    let expectedInts = Array.tabulate<Int>(intBoundaries.size() * 3, func(i) { intBoundaries[i % intBoundaries.size()] });
    let expectedBools = Array.tabulate<Bool>(259, func(i) { i % 5 == 1 or i % 7 == 2 });
    let boolWire = append("\83\02", Blob.fromArray(Array.tabulate<Nat8>(259, func(i) { if (expectedBools[i]) 1 else 0 })));
    let floatWire : Blob = "\03\00\00\00\00\00\00\f8\3f\00\00\00\00\00\00\00\80\01\00\00\00\00\00\00\00";
    let float32Wire : Blob = "\03\00\00\c0\3f\00\00\00\80\01\00\00\00";
    retainedNats := ok(ICWire.decode<[Nat]>(ok(ICWire.encode(expectedNats))));
    retainedInts := ok(ICWire.decode<[Int]>(ok(ICWire.encode(expectedInts))));
    assert ICWire.encode(expectedBools) == #ok boolWire;
    retainedBools := ok(ICWire.decode<[Bool]>(boolWire));
    retainedFloats := ok(ICWire.decode<[Float]>(floatWire));
    retainedFloat32s := ok(ICWire.decode<[Float32]>(float32Wire));
    let before = Prim.rts_reclaimed();
    await collect();
    assert Prim.rts_reclaimed() > before + 4 * 1024 * 1024;
    var i = 0;
    while (i < 128) {
      assert ICWire.decode<Int>(ok(ICWire.encode(-(2 ** (128 + i) : Int)))) == #ok (-(2 ** (128 + i) : Int));
      ignore error(ICWire.decode<Nat>("\80\00"));
      ignore error(ICWire.decode<[Bool]>("\04\00\01\02"));
      ignore error(ICWire.encodeBounded(expected, 64));
      ignore ok(ICWire.decode<Text>(ok(ICWire.encode(ascii(1024 + i)))));
      i += 1;
    };
    let second = Prim.rts_reclaimed();
    await collect();
    assert Prim.rts_reclaimed() > second + 4 * 1024 * 1024;
    let metrics = Test.test(func() {
      assert retained == ?expected;
      assert retainedError == ?{ kind = "utf8"; offset = 0 : Nat64 };
      assert retainedNats == expectedNats;
      assert retainedInts == expectedInts;
      assert retainedBools == expectedBools;
      assert ICWire.encode(retainedNats) == ICWire.encode(expectedNats);
      assert ICWire.encode(retainedInts) == ICWire.encode(expectedInts);
      assert ICWire.encode(retainedBools) == #ok boolWire;
      assert retainedFloats.size() == 3 and retainedFloats[0] == 1.5;
      assert retainedFloat32s.size() == 3 and retainedFloat32s[0] == Float.toFloat32(1.5);
      assert ICWire.encode(retainedFloats) == #ok floatWire;
      assert ICWire.encode(retainedFloat32s) == #ok float32Wire;
      switch retained {
        case (?value) {
          assert ICWire.encode(value) == #ok retainedWire;
          assert ICWire.decode<Row>(retainedWire) == #ok expected;
        };
        case null assert false;
      };
    });
    retained := null;
    retainedWire := "";
    retainedError := null;
    retainedNats := [];
    retainedInts := [];
    retainedBools := [];
    retainedFloats := [];
    retainedFloat32s := [];
    metrics
  };
}
