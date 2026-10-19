//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err e) Prim.trap(debug_show e) }
};
// Records contain only values in the schema's deterministic field order.
assert ok(Wire.encode({})) == "";
assert ok(Wire.encode({a = 1 : Nat8})) == "\01";
assert ok(Wire.encode({a = ()})) == "";
assert ok(Wire.encode({a = null : ?Nat})) == "\00";
assert ok(Wire.encode({a = ?null : ??Nat})) == "\01\00";
assert ok(Wire.decode<{a : ?Nat}>("\00")) == {a = null};
assert ok(Wire.encode({z = 7 : Nat8; a = 6 : Nat8})) == "\06\07";
// Numeric labels influence schema order but never appear on the wire.
let numbered = {_4294967295_ = 7 : Nat8; _0_ = 6 : Nat8};
assert ok(Wire.encode(numbered)) == "\06\07";
assert ok(Wire.decode<{_0_ : Nat8; _4294967295_ : Nat8}>(ok(Wire.encode(numbered)))) == numbered;
assert ok(Wire.encode({_4294967295_ = ?(9 : Nat8)})) == "\01\09";
assert ok(Wire.decode<{_4294967295_ : ?Nat8}>("\01\09")) == {_4294967295_ = ?9};
assert ok(Wire.encode({x_ = 1 : Nat8})) == ok(Wire.encode({x = 1 : Nat8}));
// Variant tags are compact, zero-based schema ordinals, including numeric labels.
assert ok(Wire.encode(#_4294967295_(9 : Nat8) : {#_4294967295_ : Nat8})) == "\00\09";
assert ok(Wire.decode<{#_4294967295_ : Nat8}>("\00\09")) == #_4294967295_(9);
assert ok(Wire.encode(#a(9 : Nat8) : {#a : Nat8; #z})) == "\00\09";
assert ok(Wire.encode(#z : {#a : Nat8; #z})) == "\01";
assert ok(Wire.decode<{#a : Nat8; #z}>("\00\09")) == #a(9);
assert ok(Wire.decode<{#a : Nat8; #z}>("\01")) == #z;
assert ok(Wire.encode(#_4294967295_(9 : Nat8) : {#_0_; #_4294967295_ : Nat8})) == "\01\09";
// Every optional record field has a marker, and nesting adds no record framing.
assert ok(Wire.encode({a = {a = 2 : Nat8; z = null : ?Text}; z = ?"x"})) == "\02\00\01\01x";
assert ok(Wire.decode<{a : {a : Nat8; z : ?Text}; z : ?Text}>("\02\00\01\01x")) == {a = {a = 2; z = null}; z = ?"x"};
type Tree = {#leaf : Nat; #node : {left : Tree; right : Tree; name : ?Text}};
let tree : Tree = #node({left = #leaf(18446744073709551616); right = #node({left = #leaf(2); right = #leaf(3); name = ?"inner"}); name = null});
assert ok(Wire.decode<Tree>(ok(Wire.encode(tree)))) == tree;
// Scalar scratch reuse must not alter values already copied into managed arrays.
let mixed : [(Nat, Text, ?Int, {#value : Int}, Blob)] = [
  (18446744073709551616, "x", ?(-1), #value(-18446744073709551617), "\00\ff"),
  (0, "", null, #value(0), ""),
];
assert ok(Wire.decode<[(Nat, Text, ?Int, {#value : Int}, Blob)]>(ok(Wire.encode(mixed)))) == mixed;

// Ordinals use more than one byte only after case 127.
type ManyCases = {#_0_; #_1_; #_2_; #_3_; #_4_; #_5_; #_6_; #_7_; #_8_; #_9_; #_10_; #_11_; #_12_; #_13_; #_14_; #_15_; #_16_; #_17_; #_18_; #_19_; #_20_; #_21_; #_22_; #_23_; #_24_; #_25_; #_26_; #_27_; #_28_; #_29_; #_30_; #_31_; #_32_; #_33_; #_34_; #_35_; #_36_; #_37_; #_38_; #_39_; #_40_; #_41_; #_42_; #_43_; #_44_; #_45_; #_46_; #_47_; #_48_; #_49_; #_50_; #_51_; #_52_; #_53_; #_54_; #_55_; #_56_; #_57_; #_58_; #_59_; #_60_; #_61_; #_62_; #_63_; #_64_; #_65_; #_66_; #_67_; #_68_; #_69_; #_70_; #_71_; #_72_; #_73_; #_74_; #_75_; #_76_; #_77_; #_78_; #_79_; #_80_; #_81_; #_82_; #_83_; #_84_; #_85_; #_86_; #_87_; #_88_; #_89_; #_90_; #_91_; #_92_; #_93_; #_94_; #_95_; #_96_; #_97_; #_98_; #_99_; #_100_; #_101_; #_102_; #_103_; #_104_; #_105_; #_106_; #_107_; #_108_; #_109_; #_110_; #_111_; #_112_; #_113_; #_114_; #_115_; #_116_; #_117_; #_118_; #_119_; #_120_; #_121_; #_122_; #_123_; #_124_; #_125_; #_126_; #_127_; #_128_};
assert ok(Wire.encode(#_127_ : ManyCases)) == "\7f";
assert ok(Wire.encode(#_128_ : ManyCases)) == "\80\01";
assert ok(Wire.decode<ManyCases>("\7f")) == #_127_;
assert ok(Wire.decode<ManyCases>("\80\01")) == #_128_;
