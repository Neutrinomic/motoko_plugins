import Test "mo:test";
import CandidX "mo:fast/CandidX";
import Array "mo:core/Array";
import Float "mo:core/Float";
import Principal "mo:core/Principal";

persistent actor {
  // These exact wire examples are derived from the CandidX cx profile, not
  // from this encoder. Decoding checks below supplement these fixed oracles.
  func bytes(result : CandidX.Result) : Blob {
    switch result { case (#ok value) value; case (#err _) { assert false; "" } }
  };

  public query func test_zero_variadic_tuple_and_unit() : async Test.Metrics {
    Test.test(func() {
      assert CandidX.encode() == #ok "DIDL\00\00";
      assert CandidX.encode(()) == #ok "DIDL\00\01\7f";
      assert CandidX.encode(null) == #ok "DIDL\00\01\7f";
      assert CandidX.encode(42 : Any) == #ok "DIDL\00\01\70";
      assert CandidX.encode(true, false, null) == #ok "DIDL\00\03\7e\7e\7f\01\00";
      assert CandidX.encode(1 : Nat, true) == #ok "DIDL\00\02\7d\7e\01\01";
      assert CandidX.encode((1 : Nat, true)) == #ok "DIDL\01\6c\02\00\7d\01\7e\01\00\01\01";
      let pair = (1 : Nat, true);
      assert CandidX.encode(pair) == CandidX.encode((1 : Nat, true));
      assert CandidX.encode(1 : Nat, true) != CandidX.encode(true, 1 : Nat);
    })
  };

  public query func test_integer_kinds_and_boundaries() : async Test.Metrics {
    Test.test(func() {
      assert CandidX.encode(0 : Nat) == #ok "DIDL\00\01\7d\00";
      assert CandidX.encode(127 : Nat) == #ok "DIDL\00\01\7d\7f";
      assert CandidX.encode(128 : Nat) == #ok "DIDL\00\01\7d\80\01";
      assert CandidX.encode(255 : Nat) == #ok "DIDL\00\01\7d\ff\01";
      assert CandidX.encode(-65 : Int) == #ok "DIDL\00\01\7c\bf\7f";
      assert CandidX.encode(-64 : Int) == #ok "DIDL\00\01\7c\40";
      assert CandidX.encode(64 : Int) == #ok "DIDL\00\01\7c\c0\00";
      assert CandidX.encode(255 : Nat8) == #ok "DIDL\00\01\7b\ff";
      assert CandidX.encode(65_535 : Nat16) == #ok "DIDL\00\01\7a\ff\ff";
      assert CandidX.encode(4_294_967_295 : Nat32) == #ok "DIDL\00\01\79\ff\ff\ff\ff";
      assert CandidX.encode(18_446_744_073_709_551_615 : Nat64) == #ok "DIDL\00\01\78\ff\ff\ff\ff\ff\ff\ff\ff";
      assert CandidX.encode(-128 : Int8) == #ok "DIDL\00\01\77\80";
      assert CandidX.encode(-32_768 : Int16) == #ok "DIDL\00\01\76\00\80";
      assert CandidX.encode(-2_147_483_648 : Int32) == #ok "DIDL\00\01\75\00\00\00\80";
      assert CandidX.encode(-9_223_372_036_854_775_808 : Int64) == #ok "DIDL\00\01\74\00\00\00\00\00\00\00\80";
      assert CandidX.encode(1 : Nat) != CandidX.encode(1 : Nat64);
      assert CandidX.encode(1 : Nat) != CandidX.encode(1 : Int);
      let big = 18_446_744_073_709_551_616 : Nat;
      assert CandidX.encode(big) == #ok "DIDL\00\01\7d\80\80\80\80\80\80\80\80\80\02";
      let negative = -(big : Int) - 1;
      assert CandidX.encode(negative) == #ok(to_candid(negative));
      var n : Nat = 1;
      var i = 0;
      while (i < 180) {
        assert CandidX.encode(n) == #ok(to_candid(n));
        assert CandidX.encode(-(n : Int)) == #ok(to_candid(-(n : Int)));
        n *= 2;
        i += 1;
      };
    })
  };

  public query func test_float_bits_and_nan_normalization() : async Test.Metrics {
    Test.test(func() {
      assert CandidX.encode(0.0) == #ok "DIDL\00\01\72\00\00\00\00\00\00\00\00";
      assert CandidX.encode(-0.0) == #ok "DIDL\00\01\72\00\00\00\00\00\00\00\80";
      assert CandidX.encode(1.5) == #ok "DIDL\00\01\72\00\00\00\00\00\00\f8\3f";
      assert CandidX.encode(Float.toFloat32(1.5)) == #ok "DIDL\00\01\73\00\00\c0\3f";
      assert CandidX.encode(Float.toFloat32(-0.0)) == #ok "DIDL\00\01\73\00\00\00\80";
      let nanWire : Blob = "DIDL\00\01\72\01\00\00\00\00\00\f0\ff";
      let nan : ?Float = from_candid(nanWire);
      switch nan {
        case (?value) {
          assert Float.isNaN(value);
          assert CandidX.encode(value) == #ok "DIDL\00\01\72\00\00\00\00\00\00\f8\7f";
          assert CandidX.encode(Float.toFloat32(value)) == #ok "DIDL\00\01\73\00\00\c0\7f";
        };
        case null assert false;
      };
      let wires : [Blob] = [
        "DIDL\00\01\72\00\00\00\00\00\00\f0\7f", // infinity
        "DIDL\00\01\72\00\00\00\00\00\00\f0\ff", // -infinity
        "DIDL\00\01\72\01\00\00\00\00\00\00\00", // smallest subnormal
      ];
      for (wire in wires.vals()) {
        let decoded : ?Float = from_candid(wire);
        switch decoded {
          case (?value) assert CandidX.encode(value) == #ok wire;
          case null assert false;
        };
      };
    })
  };

  public query func test_text_char_principal_and_binary() : async Test.Metrics {
    Test.test(func() {
      assert CandidX.encode("\u{FEFF}λ") == #ok "DIDL\00\01\71\05\ef\bb\bf\ce\bb";
      assert CandidX.encode("a\u{0}b") == #ok "DIDL\00\01\71\03a\00b";
      assert CandidX.encode("é") != CandidX.encode("e\u{301}");
      assert CandidX.encode('a') == CandidX.encode(97 : Nat32);
      assert CandidX.encode('😀') == CandidX.encode(128_512 : Nat32);
      assert CandidX.encode(Principal.fromText("aaaaa-aa")) == #ok "DIDL\00\01\68\01\00";
      assert CandidX.encode(Principal.fromText("2vxsx-fae")) == #ok "DIDL\00\01\68\01\01\04";
      assert CandidX.encode("" : Blob) == #ok "DIDL\01\6d\7b\01\00\00";
      assert CandidX.encode("\00\ff" : Blob) == #ok "DIDL\01\6d\7b\01\00\02\00\ff";
      assert CandidX.encode("\00\ff" : Blob) == CandidX.encode([0, 255] : [Nat8]);
      assert CandidX.encode("" : Blob) == CandidX.encode([] : [Nat8]);
      assert CandidX.encode("" : Blob) != CandidX.encode([] : [Nat]);
    })
  };

  public query func test_option_presence_is_data() : async Test.Metrics {
    Test.test(func() {
      assert CandidX.encode(null : ?Nat) == CandidX.encode(null : ?Text);
      assert CandidX.encode(null : ?Nat) == #ok "DIDL\00\01\7f";
      assert CandidX.encode(?null) == #ok "DIDL\01\6e\7f\01\00\01";
      assert CandidX.encode(??null) == #ok "DIDL\02\6e\01\6e\7f\01\00\01\01";
      assert CandidX.encode(null) != CandidX.encode(?null);
      assert CandidX.encode(?null) != CandidX.encode(??null);
      assert CandidX.encode([null, ?128] : [?Nat]) == #ok "DIDL\02\6d\01\6e\7d\01\00\02\00\01\80\01";
      assert CandidX.encode([?(?null), null] : [??Null]) == #ok "DIDL\03\6d\01\6e\02\6e\7f\01\00\02\01\01\00";
      assert CandidX.encode([null, null] : [?Nat]) == CandidX.encode([null, null] : [?Text]);
    })
  };

  public query func test_record_evolution_and_numeric_labels() : async Test.Metrics {
    Test.test(func() {
      let old = { a = "abc" };
      let added = { a = "abc"; b = null : ?Text };
      assert CandidX.encode(old) == #ok "DIDL\01\6c\01\61\71\01\00\03abc";
      assert CandidX.encode(old) == CandidX.encode(added);
      assert CandidX.encode(old) != CandidX.encode({ a = "abc"; b = ?"" });
      assert CandidX.encode(old) != CandidX.encode({ a = "abc"; b = null });
      assert CandidX.encode({ a = "abc"; b = null }) == #ok "DIDL\01\6c\02\61\71\62\7f\01\00\03abc";
      assert CandidX.encode({ a = "abc"; b = null : Any }) == #ok "DIDL\01\6c\02\61\71\62\70\01\00\03abc";
      assert CandidX.encode({ a = "abc"; b = ?(null : ?Text) }) != CandidX.encode(old);
      assert CandidX.encode({ _97_ = "abc" }) == CandidX.encode(old);
      assert CandidX.encode({ _4294967295_ = 1 : Nat }) == #ok "DIDL\01\6c\01\ff\ff\ff\ff\0f\7d\01\00\01";
      assert CandidX.encode({ _2_ = true; _0_ = 42 : Nat }) == CandidX.encode({ _0_ = 42 : Nat; _2_ = true });
      assert CandidX.encode({ x = old; y = [old] }) == CandidX.encode({ x = added; y = [added] });
    })
  };

  public query func test_array_joins_and_type_interning() : async Test.Metrics {
    Test.test(func() {
      assert CandidX.encode([] : [Nat]) == #ok "DIDL\01\6d\6f\01\00\00";
      assert CandidX.encode([] : [Nat]) == CandidX.encode([] : [Text]);
      assert CandidX.encode([1, 2] : [Nat]) != CandidX.encode([2, 1] : [Nat]);
      type Old = { a : Text };
      type New = { a : Text; b : ?Text };
      let old : [Old] = [{ a = "x" }, { a = "y" }];
      let added : [New] = [{ a = "x"; b = null }, { a = "y"; b = null }];
      assert CandidX.encode(old) == CandidX.encode(added);
      let mixed : [New] = [{ a = "x"; b = null }, { a = "y"; b = ?"z" }];
      let wire = bytes(CandidX.encode(mixed));
      let decoded : ?[New] = from_candid(wire);
      assert decoded == ?mixed;
      assert wire == bytes(CandidX.encode([{ a = "x"; b = null; c = null : ?Nat }, { a = "y"; b = ?"z"; c = null : ?Nat }]));
      assert CandidX.encode({ a = "\01\02" : Blob; b = [1, 2] : [Nat8] }) == #ok "DIDL\02\6c\02\61\01\62\01\6d\7b\01\00\02\01\02\02\01\02";
      assert CandidX.encode([{ _0_ = { _0_ = 'a' }; _1_ = { _0_ = 97 : Nat32 } }]) == #ok "DIDL\03\6d\01\6c\02\00\02\01\02\6c\01\00\79\01\00\01\61\00\00\00\61\00\00\00";
      assert CandidX.encode([[1 : Nat], [], [2, 3]]) == #ok "DIDL\02\6d\01\6d\7d\01\00\03\01\01\00\02\02\03";
    })
  };

  public query func test_variant_narrowing_and_join_order() : async Test.Metrics {
    Test.test(func() {
      type Narrow = { #a : Nat };
      type Wide = { #a : Nat; #b : Bool; #_4294967295_ };
      assert CandidX.encode(#a(7) : Narrow) == CandidX.encode(#a(7) : Wide);
      assert CandidX.encode(#_4294967295_ : Wide) == #ok "DIDL\01\6b\01\ff\ff\ff\ff\0f\7f\01\00\00";
      let values : [Wide] = [#b(true), #a(128), #_4294967295_, #a(0)];
      assert CandidX.encode(values) == #ok "DIDL\02\6d\01\6b\03\61\7d\62\7e\ff\ff\ff\ff\0f\7f\01\00\04\01\01\00\80\01\02\00\00";
      let decoded : ?[Wide] = from_candid(bytes(CandidX.encode(values)));
      assert decoded == ?values;
      assert CandidX.encode([#a(1), #a(2)] : [Wide]) == CandidX.encode([#a(1), #a(2)] : [Narrow]);
      let nested = [{ _0_ = [#a(1)] : [Wide]; _1_ = 5 : Nat8 }, { _0_ = [#b(true)] : [Wide]; _1_ = 6 : Nat8 }];
      let decodedNested : ?[{ _0_ : [Wide]; _1_ : Nat8 }] = from_candid(bytes(CandidX.encode(nested)));
      assert decodedNested == ?nested;
    })
  };

  public query func test_recursive_values_ignore_unused_shapes() : async Test.Metrics {
    Test.test(func() {
      type List = ?(Nat, List);
      type Other = ?(Nat, ?(Nat, Other));
      let list : List = ?(1, ?(2, null));
      let other : Other = ?(1, ?(2, null));
      assert CandidX.encode(list) == CandidX.encode(other);
      let decoded : ?List = from_candid(bytes(CandidX.encode(list)));
      assert decoded == ?list;
      type Uninhabited = { next : Uninhabited };
      assert CandidX.encode([] : [Uninhabited]) == CandidX.encode([] : [Nat]);
      type Shape = { #leaf : Nat; #branch : [Shape] };
      let tree : Shape = #branch([#leaf(1), #branch([]), #leaf(2)]);
      let treeDecoded : ?Shape = from_candid(bytes(CandidX.encode(tree)));
      assert treeDecoded == ?tree;
    })
  };

  public query func test_aliases_callbacks_and_evaluation_order() : async Test.Metrics {
    Test.test(func() {
      let encode = CandidX.encode;
      let ops = { encode };
      func identity<T>(value : T) : T = value;
      let alias = identity(encode);
      let aliases = [encode, alias];
      assert aliases[0](42 : Nat) == ops.encode(42 : Nat);
      assert aliases[1](true, "abc") == CandidX.encode(true, "abc");
      let optional = ?encode;
      switch optional { case (?f) assert f(42 : Nat) == encode(42 : Nat); case null assert false };
      func encodeNat(n : Nat) : CandidX.Result = encode(n);
      let callback : Nat -> CandidX.Result = encodeNat;
      assert callback(42) == #ok "DIDL\00\01\7d\2a";
      var order = "";
      let actual = (do { order #= "callee;"; encode })(
        do { order #= "first;"; 1 : Nat },
        do { order #= "second;"; true },
      );
      assert order == "callee;first;second;";
      assert actual == #ok "DIDL\00\02\7d\7e\01\01";
    })
  };

  public query func test_reference_errors_and_recovery() : async Test.Metrics {
    Test.test(func() {
      let service : actor { call : shared () -> async () } = actor "aaaaa-aa";
      let expected : CandidX.Error = "function and service values are excluded";
      assert CandidX.encode(service) == #err expected;
      assert CandidX.encode(service.call) == #err expected;
      assert CandidX.encode(?service.call) == #err expected;
      assert CandidX.encode(null : ?(shared () -> async ())) == #ok "DIDL\00\01\7f";
      assert CandidX.encode([] : [actor {}]) == CandidX.encode([] : [Nat]);
      assert CandidX.encode({ a = 1 : Nat; _97_ = 2 : Nat }) == #err "source type field ids must strictly increase";
      assert CandidX.encode(7 : Nat64) == #ok "DIDL\00\01\78\07\00\00\00\00\00\00\00";
    })
  };

  public func test_nesting_and_integer_limit_errors() : async Test.Metrics {
    Test.test(func() {
      let saved = bytes(CandidX.encode({ a = "retained" }));
      type Chain = ?(Nat, Chain);
      var chain : Chain = null;
      var n = 0;
      while (n < 140) { chain := ?(n, chain); n += 1 };
      assert CandidX.encode(chain) == #err "value nesting limit";
      assert CandidX.encode(2 ** 28_673 : Nat) == #err "integer length limit";
      assert CandidX.encode([null, ?1] : [?Nat]) == #ok "DIDL\02\6d\01\6e\7d\01\00\02\00\01\01";
      assert saved == bytes(CandidX.encode({ a = "retained" }));
    })
  };

  public func test_seeded_records_and_retained_results() : async Test.Metrics {
    Test.test(func() {
      type Row = { key : Nat; name : Text; extra : ?Nat; choice : { #a : Nat; #b : Bool } };
      var state = 1729 : Nat;
      var sample = 0;
      let saved = bytes(CandidX.encode({ a = "saved" }));
      while (sample < 150) {
        let rows : [Row] = Array.tabulate<Row>(sample % 17, func(i) {
          state := (state * 48271) % 2147483647;
          { key = state; name = if (i % 2 == 0) "λ\u{0}" else "text";
            extra = if (state % 3 == 0) null else ?(state * state);
            choice = if (state % 2 == 0) #a(state) else #b(state % 3 == 0) }
        });
        let wire = bytes(CandidX.encode(rows));
        let decoded : ?[Row] = from_candid(wire);
        assert decoded == ?rows;
        assert wire == bytes(CandidX.encode(rows));
        assert saved == bytes(CandidX.encode({ a = "saved" }));
        sample += 1;
      };
    })
  };

  public func test_fixed_shape_depth_boundary() : async Test.Metrics {
    Test.test(func() {
      type Row = { _0_ : Nat16; _1_ : Nat8 };
      type Nested = ?{ rows : [Row]; next : Nested };
      let rows : [Row] = [{ _0_ = 1; _1_ = 2 }, { _0_ = 3; _1_ = 4 }];
      assert CandidX.encode(?rows) == #ok "DIDL\03\6e\01\6d\02\6c\02\00\7a\01\7b\01\00\01\02\01\00\02\03\00\04";
      var nested : Nested = ?{ rows; next = null };
      var depth = 0;
      while (depth < 126) { nested := ?{ rows = []; next = nested }; depth += 1 };
      ignore bytes(CandidX.encode(nested)); // deepest row fields are at depth 256
      nested := ?{ rows = []; next = nested };
      assert CandidX.encode(nested) == #err "value nesting limit";
      assert CandidX.encode(?rows) == #ok "DIDL\03\6e\01\6d\02\6c\02\00\7a\01\7b\01\00\01\02\01\00\02\03\00\04";
    })
  };

  public func test_collection_and_output_limit_errors() : async Test.Metrics {
    Test.test(func() {
      // No per-element payload allocation is needed for this collection edge.
      let tooLong = Array.repeat<Null>(null, 2_000_001);
      assert CandidX.encode(tooLong) == #err "collection length limit";
      var text = "x";
      var doubling = 0;
      while (doubling < 20) { text #= text; doubling += 1 };
      // Shared 1 MiB input text exceeds 32 MiB only in encoded output.
      let repeated = Array.repeat<Text>(text, 33);
      assert CandidX.encode(repeated) == #err "output byte limit";
      assert CandidX.encode(7 : Nat) == #ok "DIDL\00\01\7d\07";
    })
  };

  public func test_dynamic_traversal_limit_boundary() : async Test.Metrics {
    Test.test(func() {
      let row = { _0_ = null; _1_ = null; _2_ = null };
      // Four visits per row, plus the option and vector containers.
      let withinLimit = Array.repeat(row, 499_999);
      ignore bytes(CandidX.encode(?withinLimit));
      let overLimit = Array.repeat(row, 500_000);
      assert CandidX.encode(?overLimit) == #err "value traversal limit";
      assert CandidX.encode(?[row]) == #ok "DIDL\03\6e\01\6d\02\6c\03\00\7f\01\7f\02\7f\01\00\01\01";
    })
  };
}
