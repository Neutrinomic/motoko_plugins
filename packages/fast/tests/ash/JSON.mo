import Test "mo:test";
import JSON "mo:fast/JSON";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Char "mo:core/Char";
import Runtime "mo:core/Runtime";
import Float32 "mo:core/Float32";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Principal "mo:core/Principal";

persistent actor {
  type List = ?(Nat, List);
  type Tree = { #leaf : Nat8; #branch : [Tree] };
  type Node = { title : Text; next : ?Node };
  type Chain = ?{ next : Chain };
  type User = {
    active : Bool;
    age : Nat8;
    name : Text;
    nickname : ?Text;
    state : { #ready; #visits : Nat };
    tags : [Text];
  };
  type Generated = {
    choice : { #left : Nat8; #right : Text };
    id : Nat32;
    name : Text;
    optional : ?Bool;
    values : [Nat8];
  };

  func ok<T>(result : JSON.Result<T>) : T {
    switch result {
      case (#ok value) value;
      case (#err value) Runtime.trap("unexpected JSON error: " # debug_show value);
    }
  };

  func error<T>(result : JSON.Result<T>) : JSON.Error {
    switch result {
      case (#err value) {
        assert value.kind != "";
        assert value.message != "";
        value
      };
      case (#ok _) Runtime.trap("expected JSON error");
    }
  };

  public query func test_basic_values_and_empty_containers() : async Test.Metrics {
    Test.test(func() {
      assert JSON.encode(null) == #ok "null";
      assert JSON.decode<Null>(" \r\n\t null \t") == #ok null;
      assert JSON.encode(true) == #ok "true";
      assert JSON.encode(false) == #ok "false";
      assert JSON.decode<Bool>("true") == #ok true;
      assert JSON.decode<Bool>("false") == #ok false;
      assert JSON.encode(()) == #ok "[]";
      assert JSON.decode<()>("[]") == #ok ();
      assert JSON.encode(({} : {})) == #ok "{}";
      assert JSON.decode<{}>("{}") == #ok {};
      assert JSON.encode(([] : [Nat8])) == #ok "[]";
      assert JSON.decode<[Nat8]>("[]") == #ok([]);
      assert JSON.encode((#done : { #done })) == #ok "{\"done\":[]}";
      assert JSON.decode<{ #done }>("{\"done\":[]}") == #ok(#done);
    })
  };

  public query func test_unsigned_integer_boundaries() : async Test.Metrics {
    Test.test(func() {
      assert JSON.encode((0 : Nat8)) == #ok "0";
      assert JSON.encode((255 : Nat8)) == #ok "255";
      assert JSON.decode<Nat8>("255") == #ok 255;
      assert JSON.encode((65535 : Nat16)) == #ok "65535";
      assert JSON.decode<Nat16>("65535") == #ok 65535;
      assert JSON.encode((4294967295 : Nat32)) == #ok "4294967295";
      assert JSON.decode<Nat32>("4294967295") == #ok 4294967295;
      assert JSON.encode((18446744073709551615 : Nat64)) ==
        #ok "\"18446744073709551615\"";
      assert JSON.decode<Nat64>("18446744073709551615") == #ok 18446744073709551615;
      assert JSON.decode<Nat64>("\"18446744073709551615\"") == #ok 18446744073709551615;
      assert JSON.encode((0 : Nat)) == #ok "\"0\"";
      assert JSON.decode<Nat>("0") == #ok 0;
      assert JSON.decode<Nat>("\"0\"") == #ok 0;
    })
  };

  public query func test_signed_integer_boundaries() : async Test.Metrics {
    Test.test(func() {
      assert JSON.encode((-128 : Int8)) == #ok "-128";
      assert JSON.decode<Int8>("-128") == #ok (-128);
      assert JSON.decode<Int8>("127") == #ok 127;
      assert JSON.encode((-32768 : Int16)) == #ok "-32768";
      assert JSON.decode<Int16>("-32768") == #ok (-32768);
      assert JSON.decode<Int16>("32767") == #ok 32767;
      assert JSON.encode((-2147483648 : Int32)) == #ok "-2147483648";
      assert JSON.decode<Int32>("-2147483648") == #ok (-2147483648);
      assert JSON.decode<Int32>("2147483647") == #ok 2147483647;
      assert JSON.encode((-9223372036854775808 : Int64)) ==
        #ok "\"-9223372036854775808\"";
      assert JSON.decode<Int64>("-9223372036854775808") == #ok (-9223372036854775808);
      assert JSON.decode<Int64>("\"9223372036854775807\"") == #ok 9223372036854775807;
      assert JSON.decode<Int>("-0") == #ok 0;
      assert JSON.decode<Int>("\"-0\"") == #ok 0;
    })
  };

  public query func test_arbitrary_integer_precision() : async Test.Metrics {
    Test.test(func() {
      let big : Nat = 115792089237316195423570985008687907853269984665640564039457584007913129639937;
      let digits = "115792089237316195423570985008687907853269984665640564039457584007913129639937";
      assert JSON.encode(big) == #ok ("\"" # digits # "\"");
      assert JSON.decode<Nat>(digits) == #ok big;
      assert JSON.decode<Nat>("\"" # digits # "\"") == #ok big;
      assert JSON.encode(-big) == #ok ("\"-" # digits # "\"");
      assert JSON.decode<Int>("-" # digits) == #ok (-big);
      assert JSON.decode<Int>("\"-" # digits # "\"") == #ok (-big);
      // Adjacent values beyond double precision must remain distinct.
      assert JSON.decode<Nat>("9007199254740993") == #ok 9007199254740993;
      assert JSON.encode((9007199254740993 : Nat)) == #ok "\"9007199254740993\"";
    })
  };

  public query func test_integer_overflow_and_underflow() : async Test.Metrics {
    Test.test(func() {
      assert error(JSON.decode<Nat8>("256")).kind == "range";
      assert error(JSON.decode<Nat16>("65536")).kind == "range";
      assert error(JSON.decode<Nat32>("4294967296")).kind == "range";
      assert error(JSON.decode<Nat64>("\"18446744073709551616\"")).kind == "range";
      assert error(JSON.decode<Nat>("-1")).kind == "range";
      assert error(JSON.decode<Int8>("-129")).kind == "range";
      assert error(JSON.decode<Int8>("128")).kind == "range";
      assert error(JSON.decode<Int16>("-32769")).kind == "range";
      assert error(JSON.decode<Int16>("32768")).kind == "range";
      assert error(JSON.decode<Int32>("-2147483649")).kind == "range";
      assert error(JSON.decode<Int32>("2147483648")).kind == "range";
      assert error(JSON.decode<Int64>("-9223372036854775809")).kind == "range";
      assert error(JSON.decode<Int64>("9223372036854775808")).kind == "range";
      assert error(JSON.decode<Nat8>("\"1\"")).kind == "type";
      assert error(JSON.decode<Int32>("\"1\"")).kind == "type";
    })
  };

  public query func test_integer_grammar_does_not_coerce() : async Test.Metrics {
    Test.test(func() {
      for (text in ["1.0", "1e0", "1E+2", "-1.5"].values()) {
        assert error(JSON.decode<Int>(text)).kind == "range";
      };
      for (text in ["\"01\"", "\"+1\"", "\" 1\"", "\"1 \"", "\"1e2\"", "\"\""].values()) {
        assert error(JSON.decode<Int>(text)).kind == "range";
      };
      for (text in ["01", "+1", "--1", "1.", ".1", "1e", "0x10"].values()) {
        ignore error(JSON.decode<Int>(text));
      };
      assert error(JSON.decode<Nat>("true")).kind == "type";
      assert error(JSON.decode<Int>("null")).kind == "type";
    })
  };

  public query func test_float_finite_and_negative_zero() : async Test.Metrics {
    Test.test(func() {
      for (value in ([
        0.0, 1.25, -3.5, 1e-300, 1e300, 3.141592653589793,
        5e-324, 2.2250738585072014e-308, 1.7976931348623157e308
      ] : [Float]).values()) {
        assert JSON.decode<Float>(ok(JSON.encode(value))) == #ok value;
      };
      assert JSON.encode((1.25 : Float)) == #ok "1.2500000000000000e0";
      let negative = ok(JSON.decode<Float>("-0.0"));
      assert 1.0 / negative == -1.0 / 0.0;
      let copied = ok(JSON.decode<Float>(ok(JSON.encode(negative))));
      assert 1.0 / copied == -1.0 / 0.0;
      assert error(JSON.decode<Float>("1e999")).kind == "range";
      assert error(JSON.decode<Float>("\"1.25\"")).kind == "type";
    })
  };

  public query func test_float_nonfinite_values() : async Test.Metrics {
    Test.test(func() {
      assert JSON.encode((1.0 / 0.0 : Float)) == #ok "\"Infinity\"";
      assert JSON.encode((-1.0 / 0.0 : Float)) == #ok "\"-Infinity\"";
      assert JSON.decode<Float>("\"Infinity\"") == #ok (1.0 / 0.0);
      assert JSON.decode<Float>("\"-Infinity\"") == #ok (-1.0 / 0.0);
      let nan = ok(JSON.decode<Float>("\"NaN\""));
      assert nan != nan;
      assert JSON.encode(nan) == #ok "\"NaN\"";
      ignore error(JSON.decode<Float>("NaN"));
      ignore error(JSON.decode<Float>("Infinity"));
    })
  };

  public query func test_float32_rounding_and_nonfinite() : async Test.Metrics {
    Test.test(func() {
      for (value in ([
        0.0, 1.25, -3.5, 1e-30, 1e30,
        1.401298464324817e-45, 1.1754943508222875e-38, 3.4028234663852886e38
      ] : [Float32]).values()) {
        assert JSON.decode<Float32>(ok(JSON.encode(value))) == #ok value;
      };
      // Decimal-to-binary32 must not double round through binary64.
      assert JSON.decode<Float32>("1.0000000596046448") ==
        #ok(Float32.fromFloat(1.0 + 1.0 / 8388608.0));
      assert JSON.decode<Float32>("-1.0000000596046448") ==
        #ok(Float32.fromFloat(-(1.0 + 1.0 / 8388608.0)));
      assert JSON.decode<Float32>("1.000000059604644775390625") == #ok (1.0 : Float32);
      let negative = ok(JSON.decode<Float32>("-0"));
      assert 1.0 / Float32.toFloat(negative) == -1.0 / 0.0;
      let inf = Float32.fromFloat(1.0 / 0.0);
      assert JSON.encode(inf) == #ok "\"Infinity\"";
      assert JSON.decode<Float32>("\"Infinity\"") == #ok inf;
      let nan = ok(JSON.decode<Float32>("\"NaN\""));
      assert nan != nan;
      assert JSON.encode(nan) == #ok "\"NaN\"";
      assert error(JSON.decode<Float32>("1e39")).kind == "range";
    })
  };

  public query func test_text_escapes_and_unicode() : async Test.Metrics {
    Test.test(func() {
      let text = "\u{0}\u{8}\t\n\u{c}\r\"\\/é😀";
      assert JSON.encode(text) == #ok "\"\\u0000\\u0008\\t\\n\\u000c\\r\\\"\\\\/é😀\"";
      assert JSON.decode<Text>("\"\\u0000\\b\\t\\n\\f\\r\\\"\\\\\\/\\u00e9\\uD83D\\uDE00\"") == #ok text;
      assert JSON.decode<Text>("\"\"") == #ok "";
      assert JSON.decode<Text>("\"a\\u0062c\"") == #ok "abc";
      assert JSON.decode<Text>("\"e\\u0301\"") == #ok "é";
      // No Unicode normalization: these strings are different scalar sequences.
      assert ok(JSON.decode<Text>("\"e\\u0301\"")) != "é";
    })
  };

  public query func test_unicode_scalar_boundaries() : async Test.Metrics {
    Test.test(func() {
      for (scalar in ([0, 31, 32, 127, 128, 2047, 2048, 55295, 57344, 65535, 65536, 1114111] : [Nat32]).values()) {
        let char = Char.fromNat32(scalar);
        let text = Char.toText(char);
        assert JSON.decode<Char>(ok(JSON.encode(char))) == #ok char;
        assert JSON.decode<Text>(ok(JSON.encode(text))) == #ok text;
      };
      assert JSON.decode<Char>("\"\\uDBFF\\uDFFF\"") == #ok '\u{10ffff}';
      assert JSON.decode<Char>("\"\\uD83D\\uDE00\"") == #ok '😀';
      for (text in ["\"\"", "\"ab\"", "\"e\\u0301\""].values()) {
        assert error(JSON.decode<Char>(text)).kind == "type";
      };
    })
  };

  public query func test_invalid_unicode_and_string_syntax() : async Test.Metrics {
    Test.test(func() {
      for (text in [
        "\"\\uD800\"", "\"\\uDC00\"", "\"\\uD800\\u0061\"",
        "\"\\uD800\\uD800\"", "\"\\uZZZZ\"", "\"\\u123\"",
        "\"\\x41\"", "\"\\q\"", "\"unterminated", "\"line\nbreak\"",
        "\"\u{0}\""
      ].values()) {
        assert error(JSON.decode<Text>(text)).kind == "syntax";
      };
    })
  };

  public query func test_base64_known_vectors() : async Test.Metrics {
    Test.test(func() {
      let vectors : [(Blob, Text)] = [
        ("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"),
        ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy"),
        ("\00\ff\80", "AP+A")
      ];
      for ((bytes, encoded) in vectors.values()) {
        assert JSON.encode(bytes) == #ok ("\"" # encoded # "\"");
        assert JSON.decode<Blob>("\"" # encoded # "\"") == #ok bytes;
      };
      let allBytes = Blob.fromArray(Array.tabulate<Nat8>(256, Nat8.fromNat));
      assert JSON.decode<Blob>(ok(JSON.encode(allBytes))) == #ok allBytes;
    })
  };

  public query func test_base64_rejects_noncanonical_and_malformed() : async Test.Metrics {
    Test.test(func() {
      for (encoded in ["Zg", "Zg=", "Zg===", "=m9v", "Zm=v", "Zm9v=", "Zh==", "Zm9=", "____", "AP-A", "Z g==", "Zg==\n"].values()) {
        assert error(JSON.decode<Blob>(ok(JSON.encode(encoded)))).kind == "base64";
      };
      assert error(JSON.decode<Blob>("[1,2]")).kind == "type";
    })
  };

  public query func test_principal_known_values_and_lengths() : async Test.Metrics {
    Test.test(func() {
      assert JSON.encode(Principal.fromBlob("")) == #ok "\"aaaaa-aa\"";
      assert JSON.encode(Principal.fromBlob("\04")) == #ok "\"2vxsx-fae\"";
      assert JSON.decode<Principal>("\"aaaaa-aa\"") == #ok(Principal.fromBlob(""));
      assert JSON.decode<Principal>("\"2vxsx-fae\"") == #ok(Principal.fromBlob("\04"));
      var size = 0;
      while (size <= 29) {
        let principal = Principal.fromBlob(Blob.fromArray(Array.tabulate<Nat8>(size, Nat8.fromNat)));
        let encoded = ok(JSON.encode(principal));
        assert encoded == "\"" # Principal.toText(principal) # "\"";
        assert JSON.decode<Principal>(encoded) == #ok principal;
        size += 1;
      };
    })
  };

  public query func test_principal_rejects_noncanonical() : async Test.Metrics {
    Test.test(func() {
      for (text in ["", "2vxsx-fab", "2VXSX-FAE", "2vxsxfae", "aaaaa-aa-", " aaaaa-aa", "aaaaa-aa "].values()) {
        assert error(JSON.decode<Principal>(ok(JSON.encode(text)))).kind == "principal";
      };
      assert error(JSON.decode<Principal>("null")).kind == "type";
    })
  };

  public query func test_record_names_order_and_unknown_fields() : async Test.Metrics {
    Test.test(func() {
      type Names = { z : Nat8; a : Text; _42_ : Bool; next : ?Nat };
      let value : Names = { z = 7; a = "name"; _42_ = true; next = null };
      assert JSON.encode(value) == #ok "{\"_42_\":true,\"a\":\"name\",\"next\":null,\"z\":7}";
      assert JSON.decode<Names>("{\"z\":7,\"unknown\":{\"a\":[true,null,{},[]]},\"a\":\"name\",\"_42_\":true}") == #ok value;
      assert JSON.decode<{ x : Nat8 }>("{\"\\u0078\":9}") == #ok { x = 9 };
      // Unknown values are syntax-checked, without numeric conversion to a
      // Motoko type. A valid large exponent therefore remains ignorable.
      assert JSON.decode<{}>("{\"ignored\":1e999}") == #ok {};
      let withType = object { public type Count = Nat; public let count : Count = 3 };
      assert JSON.encode(withType) == #ok "{\"count\":\"3\"}";
    })
  };

  public query func test_record_missing_required_and_optional() : async Test.Metrics {
    Test.test(func() {
      type Missing = { required : Nat8; optional : ?Nat; nested : ??Null };
      assert JSON.decode<Missing>("{\"required\":7}") ==
        #ok { required = 7; optional = null; nested = null };
      let absent = error(JSON.decode<Missing>("{}"));
      assert absent.kind == "missing";
      assert absent.path == "/required";
      assert absent.offset == 2;
      assert error(JSON.decode<Missing>("{\"required\":null}")).kind == "type";
    })
  };

  public query func test_duplicate_keys_include_ignored_subtrees() : async Test.Metrics {
    Test.test(func() {
      assert error(JSON.decode<{ x : Nat8 }>("{\"x\":1,\"x\":2}")).kind == "duplicate";
      assert error(JSON.decode<{ x : Nat8 }>("{\"x\":1,\"\\u0078\":2}")).kind == "duplicate";
      assert error(JSON.decode<{}>("{\"ignored\":1,\"ignored\":2}")).kind == "duplicate";
      let nested = error(JSON.decode<{}>("{\"ghost\":[{\"x\":1,\"\\u0078\":2}]}"));
      assert nested.kind == "duplicate";
      assert nested.path == "/ghost/0";
      // Equal keys in different objects are valid.
      assert JSON.decode<{}>("{\"one\":{\"x\":1},\"two\":{\"x\":2}}") == #ok {};
    })
  };

  public query func test_variant_shape_and_payloads() : async Test.Metrics {
    Test.test(func() {
      type Choice = { #ready; #count : Nat; #pair : (Bool, Text); #nested : { value : Nat8 } };
      let values : [Choice] = [#ready, #count(9007199254740993), #pair(false, "yes"), #nested { value = 7 }];
      for (value in values.values()) assert JSON.decode<Choice>(ok(JSON.encode(value))) == #ok value;
      assert JSON.encode((#pair(false, "yes") : Choice)) == #ok "{\"pair\":[false,\"yes\"]}";
      assert error(JSON.decode<Choice>("{}")).kind == "type";
      assert error(JSON.decode<Choice>("{\"missing\":[]}")).path == "/missing";
      assert error(JSON.decode<Choice>("{\"ready\":[],\"count\":1}")).kind == "type";
      assert error(JSON.decode<Choice>("{\"ready\":null}")).kind == "type";
      let bad = error(JSON.decode<Choice>("{\"nested\":{\"value\":256}}"));
      assert bad.kind == "range";
      assert bad.path == "/nested/value";
    })
  };

  public query func test_arrays_and_tuple_shapes() : async Test.Metrics {
    Test.test(func() {
      assert JSON.decode<[Nat8]>("[0, 1,255]") == #ok([0, 1, 255]);
      assert JSON.encode((([true, false], [], [true]) : ([Bool], [Null], [Bool]))) == #ok "[[true,false],[],[true]]";
      assert JSON.decode<(Text, Nat8, ?Bool)>("[\"pair\",3,false]") == #ok ("pair", 3, ?false);
      assert JSON.encode((("pair", 3, ?false) : (Text, Nat8, ?Bool))) == #ok "[\"pair\",3,false]";
      assert error(JSON.decode<(Nat8, Nat8)>("[1]")).kind == "type";
      assert error(JSON.decode<(Nat8, Nat8)>("[1,2,3]")).kind == "type";
      assert error(JSON.decode<()>("[null]")).kind == "type";
      assert error(JSON.decode<[Nat8]>("[1,256]")).path == "/1";
      assert error(JSON.decode<[Nat8]>("{} ")).kind == "type";
    })
  };

  public query func test_options_preserve_all_null_distinctions() : async Test.Metrics {
    Test.test(func() {
      assert JSON.encode((null : ?Nat)) == #ok "null";
      assert JSON.encode((?3 : ?Nat)) == #ok "\"3\"";
      assert JSON.decode<?Nat>("3") == #ok (?3);
      assert JSON.decode<?Nat>("null") == #ok null;
      assert JSON.encode((?null : ??Nat)) == #ok "{\"some\":null}";
      assert JSON.encode((??3 : ??Nat)) == #ok "{\"some\":\"3\"}";
      assert JSON.decode<??Nat>("null") == #ok null;
      assert JSON.decode<??Nat>("{\"some\":null}") == #ok (?null);
      assert JSON.decode<??Nat>("{\"some\":\"3\"}") == #ok (??3);
      assert JSON.decode<?Null>("{\"some\":null}") == #ok (?null);
      let values : [???Null] = [null, ?null, ??null, ???null];
      let expected = ["null", "{\"some\":null}", "{\"some\":{\"some\":null}}", "{\"some\":{\"some\":{\"some\":null}}}"];
      var i = 0;
      for (value in values.values()) {
        assert JSON.encode(value) == #ok(expected[i]);
        assert JSON.decode<???Null>(expected[i]) == #ok value;
        i += 1;
      };
    })
  };

  public query func test_tagged_option_errors() : async Test.Metrics {
    Test.test(func() {
      assert error(JSON.decode<??Nat>("{\"wrong\":null}")).path == "/wrong";
      assert error(JSON.decode<??Nat>("{\"some\":\"bad\"}")).path == "/some";
      let extra = error(JSON.decode<??Nat>("{\"some\":null,\"extra\":1}"));
      assert extra.kind == "type";
      assert extra.path == "/extra";
      assert extra.offset == 21;
      assert error(JSON.decode<??Nat>("{}")).kind == "type";
      assert error(JSON.decode<?Null>("0")).kind == "type";
    })
  };

  public query func test_recursive_records_lists_and_variants() : async Test.Metrics {
    Test.test(func() {
      let list : List = ?(1, ?(2, ?(3, null)));
      assert JSON.encode(list) == #ok "[\"1\",[\"2\",[\"3\",null]]]";
      assert JSON.decode<List>(ok(JSON.encode(list))) == #ok list;
      let node : Node = { title = "first"; next = ?{ title = "last"; next = null } };
      assert JSON.decode<Node>(ok(JSON.encode(node))) == #ok node;
      let tree : Tree = #branch([#leaf(3), #branch([#leaf(1), #branch([]), #leaf(2)])]);
      assert JSON.decode<Tree>(ok(JSON.encode(tree))) == #ok tree;
      let bad = error(JSON.decode<Tree>("{\"branch\":[{\"leaf\":3},{\"branch\":[{\"leaf\":256}]}]}"));
      assert bad.kind == "range";
      assert bad.path == "/branch/1/branch/0/leaf";
    })
  };

  public query func test_nested_application_record() : async Test.Metrics {
    Test.test(func() {
      let user : User = {
        active = true; age = 42; name = "Zoë 😀\n\"\\"; nickname = null;
        state = #visits 18446744073709551616; tags = ["one", "two"];
      };
      assert JSON.decode<User>(ok(JSON.encode(user))) == #ok user;
      assert JSON.decode<[User]>(ok(JSON.encode([user, user]))) == #ok([user, user]);
      assert JSON.decode<User>("{\"name\":\"M\",\"age\":1,\"active\":false,\"tags\":[],\"state\":{\"ready\":[]},\"extra\":{\"x\":[true,null]}}") ==
        #ok { name = "M"; age = 1; active = false; tags = []; nickname = null; state = #ready };
    })
  };

  public query func test_error_paths_and_utf8_byte_offsets() : async Test.Metrics {
    Test.test(func() {
      let nested = error(JSON.decode<[{ x : Nat8 }]>("[{\"x\":1},{\"x\":256}]"));
      assert nested.kind == "range";
      assert nested.path == "/1/x";
      let escaped = error(JSON.decode<{}>("{\"a/b~\":[{\"x\":1,\"x\":2}]}"));
      assert escaped.kind == "duplicate";
      assert escaped.path == "/a~1b~0/0";
      let unicode = error(JSON.decode<{}>("{\"café/~\":{\"0\":[null,{\"\": [1, truX]}]}}"));
      assert unicode.kind == "type";
      assert unicode.path == "/café~1~0/0/1//1";
      assert unicode.offset == 31;
      let root = error(JSON.decode<Nat8>("256"));
      assert root.path == "";
      assert root.offset == 3;
    })
  };

  public query func test_malformed_json_corpus() : async Test.Metrics {
    Test.test(func() {
      for (text in [
        "", " ", "[", "{", "[1,]", "[,1]", "[1 2]", "[1,,2]",
        "{\"a\":}", "{a:1}", "{\"a\" 1}", "{\"a\":1,}", "{,}",
        "{\"a\":1 \"b\":2}", "{\"a\":tru}", "{\"a\":undefined}",
        "{\"a\":NaN}", "{\"a\":01}", "{\"a\":1e}", "{\"a\":/*x*/1}",
        "{\"a\":\"\\uD800\"}", "{}{}", "{} true", "{} // comment"
      ].values()) {
        ignore error(JSON.decode<{}>(text));
        // Error scratch and visitor state must not leak into the next call.
        assert JSON.decode<{ x : Nat8 }>("{\"x\":7}") == #ok { x = 7 };
      };
      assert error(JSON.decode<Nat8>("1 true")).kind == "syntax";
      // Array syntax pre-scan intentionally detects a later malformed element
      // before converting an earlier element to the requested type.
      let preScan = error(JSON.decode<[Nat]>("[\"wrong\",trux]"));
      assert preScan.path == "/1";
      assert preScan.offset == 9;
    })
  };

  public query func test_aliases_and_argument_evaluation_once() : async Test.Metrics {
    Test.test(func() {
      let encode = JSON.encode;
      let decode = JSON.decode;
      let methods = { encode; decode };
      var calls = 0;
      func value() : { x : Nat8 } { calls += 1; { x = 9 } };
      func input() : Text { calls += 1; "{\"x\":9}" };
      assert methods.encode(value()) == #ok "{\"x\":9}";
      assert calls == 1;
      assert methods.decode<{ x : Nat8 }>(input()) == #ok { x = 9 };
      assert calls == 2;
      assert methods.encode([true, false]) == #ok "[true,false]";
      assert methods.decode<[Bool]>("[true,false]") == #ok([true, false]);
      func concrete(text : Text) : JSON.Result<Nat8> { decode<Nat8>(text) };
      let callback : Text -> JSON.Result<Nat8> = concrete;
      assert callback("42") == #ok 42;
    })
  };

  public query func test_deterministic_generated_record_oracle() : async Test.Metrics {
    Test.test(func() {
      var seed = 0x5eed;
      var i = 0;
      while (i < 128) {
        seed := (seed * 25173 + 13849) % 65536;
        let byte = seed % 256;
        let title = "row" # Nat.toText(seed);
        let left = seed % 3 == 0;
        let present = seed % 2 == 0;
        let value : Generated = {
          choice = if (left) #left(Nat8.fromNat(byte)) else #right title;
          id = Nat32.fromNat(seed);
          name = title;
          optional = if (present) ?true else null;
          values = [Nat8.fromNat(byte), 0, 255];
        };
        // This oracle is assembled without calling either JSON operation.
        let choice = if (left) "{\"left\":" # Nat.toText(byte) # "}"
          else "{\"right\":\"" # title # "\"}";
        let opt = if (present) "true" else "null";
        let values = "[" # Nat.toText(byte) # ",0,255]";
        let expected = "{\"choice\":" # choice # ",\"id\":" # Nat.toText(seed) #
          ",\"name\":\"" # title # "\",\"optional\":" # opt # ",\"values\":" # values # "}";
        assert JSON.encode(value) == #ok expected;
        assert JSON.decode<Generated>(expected) == #ok value;
        let permuted = " { \"values\" : " # values # ", \"optional\" : " # opt #
          ", \"name\" : \"" # title # "\", \"ignored\" : [null,{\"x\":true}], \"id\" : " #
          Nat.toText(seed) # ", \"choice\" : " # choice # " } ";
        assert JSON.decode<Generated>(permuted) == #ok value;
        ignore error(JSON.decode<Generated>(expected # "!"));
        i += 1;
      };
    })
  };

  public query func test_repeated_partial_failures_preserve_live_values() : async Test.Metrics {
    Test.test(func() {
      let kept : User = ok(JSON.decode<User>("{\"active\":true,\"age\":7,\"name\":\"kept😀\",\"state\":{\"visits\":\"18446744073709551616\"},\"tags\":[\"still\",\"alive\"]}"));
      let snapshot = ok(JSON.encode(kept));
      var i = 0;
      while (i < 128) {
        let failure = error(JSON.decode<[{ x : Nat8; y : [Text] }]>("[{\"x\":1,\"y\":[\"allocated\"]},{\"x\":999}]"));
        assert failure.path == "/1/x";
        assert failure.kind == "range";
        assert JSON.decode<[Text]>("[\"fresh😀\",\"value\"]") == #ok(["fresh😀", "value"]);
        assert JSON.encode(kept) == #ok snapshot;
        i += 1;
      };
      assert kept.name == "kept😀";
      assert kept.tags == ["still", "alive"];
      assert kept.state == #visits 18446744073709551616;
    })
  };

  public query func test_depth_limits_and_recovery() : async Test.Metrics {
    Test.test(func() {
      var chain : Chain = null;
      var text = "null";
      var i = 0;
      while (i < 100) {
        chain := ?{ next = chain };
        text := "{\"next\":" # text # "}";
        i += 1;
      };
      assert error(JSON.encode(chain)).kind == "limit";
      assert error(JSON.decode<Chain>(text)).kind == "limit";
      assert JSON.decode<Chain>("{\"next\":null}") == #ok (?{ next = null });
      assert JSON.encode((?{ next = null } : Chain)) == #ok "{\"next\":null}";
    })
  };

  public query func test_integer_digit_limits_and_error_paths() : async Test.Metrics {
    Test.test(func() {
      var digits = "1";
      var i = 0;
      while (i < 12) { digits #= digits; i += 1 };
      // Exactly 4096 digits is legal; one more must be a typed limit error.
      let boundary = ok(JSON.decode<Nat>(digits));
      assert JSON.encode(boundary) == #ok ("\"" # digits # "\"");
      assert error(JSON.decode<Nat>(digits # "1")).kind == "limit";
      assert error(JSON.decode<Int>("\"-" # digits # "1\"")).kind == "limit";
      let huge : Nat = 10 ** 4096;
      let limit = error(JSON.encode({ nested = (??huge : ??Nat) }));
      assert limit.kind == "limit";
      assert limit.path == "/nested/some";
      assert limit.offset == 0;
      assert JSON.decode<Nat8>("42") == #ok 42;
    })
  };

  public func test_text_byte_and_collection_item_limits() : async Test.Metrics {
    Test.test(func() {
      var oversized = " ";
      var i = 0;
      while (i < 25) { oversized #= oversized; i += 1 };
      assert error(JSON.decode<Nat>(oversized)).kind == "limit";
      let many = Array.tabulate<Null>(1_000_000, func(_) { null });
      assert error(JSON.encode(many)).kind == "limit";
      assert error(JSON.encode({ items = many })).path == "/items";
      assert JSON.decode<[Bool]>("[true,false]") == #ok([true, false]);
      assert JSON.encode([true, false]) == #ok "[true,false]";
    })
  };
}
