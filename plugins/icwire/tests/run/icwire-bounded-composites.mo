//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err error) Prim.trap(debug_show error) }
};
func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected " # debug_show (kind, offset));
    case (#err error) assert error == {kind; offset = Prim.natToNat64(offset)};
  }
};
// Bound failure must identify the first child that does not fit, even where
// the optimized writer attempts to reserve an entire fixed-width aggregate.
let fixed = (7 : Nat8, 0x1234 : Nat16, true, 0x12345678 : Nat32);
let fixedBytes : Blob = "\07\34\12\01\78\56\34\12";
for ((capacity, offset) in ([(0, 0), (1, 1), (2, 1), (3, 3), (4, 4), (7, 4)] : [(Nat, Nat)]).values()) {
  at(Wire.encodeBounded(fixed, capacity), "limit", offset);
};
assert ok(Wire.encodeBounded(fixed, 8)) == fixedBytes;
assert ok(Wire.encodeBounded(fixed, 100)) == fixedBytes;
let fixedArray : [Nat16] = [0x1234, 0x5678, 0x9abc];
for ((capacity, offset) in ([(0, 0), (1, 1), (2, 1), (3, 3), (4, 3), (5, 5), (6, 5)] : [(Nat, Nat)]).values()) {
  at(Wire.encodeBounded(fixedArray, capacity), "limit", offset);
};
assert ok(Wire.encodeBounded(fixedArray, 7)) == "\03\34\12\78\56\bc\9a";
assert ok(Wire.encodeBounded([(), (), ()], 1)) == "\03";
at(Wire.encodeBounded([(), (), ()], 0), "limit", 0);
assert ok(Wire.encodeBounded([] : [None], 1)) == "\00";
assert ok(Wire.encodeBounded(null : ?None, 1)) == "\00";

type Item = {#a : Nat16; #z : ?Text};
type Message = {a : Nat8; b : [Item]; z : ?Blob};
let message : Message = {a = 7; b = [#a(0x1234), #z(?"λ")]; z = ?"\ff"};
let golden : Blob = "\07\02\00\34\12\01\01\02\ce\bb\01\01\ff";
// Prefix positions: record 0, array 1, first variant 2, Nat16 3,
// second variant 5, option 6, Text 7, final option 10, Blob 11.
let offsets : [Nat] = [0, 1, 2, 3, 3, 5, 6, 7, 7, 7, 10, 11, 11];
var capacity = 0;
while (capacity < golden.size()) {
  at(Wire.encodeBounded(message, capacity), "limit", offsets[capacity]);
  capacity += 1;
};
assert ok(Wire.encodeBounded(message, golden.size())) == golden;
assert ok(Wire.encodeBounded(message, 8192)) == golden;
assert ok(Wire.decode<Message>(golden)) == message;
// Numeric schema labels affect order but are never serialized.
assert ok(Wire.encodeBounded({_4294967295_ = ?(9 : Nat8); _0_ = 6 : Nat8}, 3)) == "\06\01\09";
at(Wire.encodeBounded({_4294967295_ = ?(9 : Nat8); _0_ = 6 : Nat8}, 2), "limit", 2);
assert ok(Wire.encodeBounded(#_4294967295_(9 : Nat8) : {#_0_; #_4294967295_ : Nat8}, 2)) == "\01\09";

// Multi-byte schema ordinals are admitted atomically, without field IDs.
type ManyCases = {#_0_; #_1_; #_2_; #_3_; #_4_; #_5_; #_6_; #_7_; #_8_; #_9_; #_10_; #_11_; #_12_; #_13_; #_14_; #_15_; #_16_; #_17_; #_18_; #_19_; #_20_; #_21_; #_22_; #_23_; #_24_; #_25_; #_26_; #_27_; #_28_; #_29_; #_30_; #_31_; #_32_; #_33_; #_34_; #_35_; #_36_; #_37_; #_38_; #_39_; #_40_; #_41_; #_42_; #_43_; #_44_; #_45_; #_46_; #_47_; #_48_; #_49_; #_50_; #_51_; #_52_; #_53_; #_54_; #_55_; #_56_; #_57_; #_58_; #_59_; #_60_; #_61_; #_62_; #_63_; #_64_; #_65_; #_66_; #_67_; #_68_; #_69_; #_70_; #_71_; #_72_; #_73_; #_74_; #_75_; #_76_; #_77_; #_78_; #_79_; #_80_; #_81_; #_82_; #_83_; #_84_; #_85_; #_86_; #_87_; #_88_; #_89_; #_90_; #_91_; #_92_; #_93_; #_94_; #_95_; #_96_; #_97_; #_98_; #_99_; #_100_; #_101_; #_102_; #_103_; #_104_; #_105_; #_106_; #_107_; #_108_; #_109_; #_110_; #_111_; #_112_; #_113_; #_114_; #_115_; #_116_; #_117_; #_118_; #_119_; #_120_; #_121_; #_122_; #_123_; #_124_; #_125_; #_126_; #_127_; #_128_};
for (capacity in [0, 1].values()) {
  at(Wire.encodeBounded(#_128_ : ManyCases, capacity), "limit", 0);
};
assert ok(Wire.encodeBounded(#_127_ : ManyCases, 1)) == "\7f";
assert ok(Wire.encodeBounded(#_128_ : ManyCases, 2)) == "\80\01";
at(Wire.encodeBounded((7 : Nat8, #_128_ : ManyCases), 2), "limit", 1);
let longArray = Prim.Array_tabulate<Nat8>(128, func i { Prim.natToNat8(i) });
at(Wire.encodeBounded(longArray, 1), "limit", 0);
at(Wire.encodeBounded(longArray, 2), "limit", 2);
at(Wire.encodeBounded(longArray, 129), "limit", 129);
assert ok(Wire.encodeBounded(longArray, 130)) == ok(Wire.encode(longArray));

// Invalid floating values keep ordinary traversal precedence. A capacity
// failure in an earlier field still prevents inspecting a later NaN.
let nan : Float = 0.0 / 0.0;
let nan32 : Float32 = 0.0 / 0.0;
at(Wire.encodeBounded((7 : Nat8, nan), 0), "limit", 0);
for (capacity in [1, 2, 8, 9, 100].values()) {
  at(Wire.encodeBounded((7 : Nat8, nan), capacity), "float", 1);
  at(Wire.encodeBounded((7 : Nat8, nan32), capacity), "float", 1);
};
at(Wire.encodeBounded((1.0 : Float, nan), 7), "limit", 0);
at(Wire.encodeBounded((1.0 : Float, nan), 8), "float", 8);
at(Wire.encodeBounded([nan, 1.0], 0), "limit", 0);
at(Wire.encodeBounded([nan, 1.0], 1), "float", 1);
at(Wire.encodeBounded([1.0, nan], 8), "limit", 1);
at(Wire.encodeBounded([1.0, nan], 9), "float", 9);
at(Wire.encodeBounded([1.0 : Float32, nan32], 4), "limit", 1);
at(Wire.encodeBounded([1.0 : Float32, nan32], 5), "float", 5);
at(Wire.encodeBounded(("ab" : Text, nan), 2), "limit", 0);
at(Wire.encodeBounded(("ab" : Text, nan), 3), "float", 3);

// Published outputs must be distinct immutable Blobs, trimmed to actual bytes,
// and must survive later writes, rejected writes and intervening allocations.
let retained = ok(Wire.encodeBounded(message, 4096));
let retainedValue = ok(Wire.decode<Message>(retained));
var iteration = 0;
while (iteration < 80) {
  let scratch = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(8192, func i { Prim.natToNat8((i + iteration) % 256) }));
  let next = ok(Wire.encodeBounded((iteration, scratch, message), 16_384));
  assert next.size() == 1 + 2 + 8192 + golden.size();
  at(Wire.encodeBounded((iteration, scratch, message), 8192), "limit", 1);
  assert retained == golden;
  assert retainedValue == message;
  iteration += 1;
};
assert ok(Wire.decode<Message>(retained)) == message;
Prim.debugPrint("bounded composites: ok");
