//MOC-FLAG --plugin ../../../../dist/candidx

import Prim "mo:⛔";

// Numeric labels fix the canonical positions on both sides of bits 31/32
// and 63/64. High bits must be tested as i64 before the branch condition.
type Choice = { #_0_; #_1_; #_2_; #_3_; #_4_; #_5_; #_6_; #_7_; #_8_; #_9_; #_10_; #_11_; #_12_; #_13_; #_14_; #_15_; #_16_; #_17_; #_18_; #_19_; #_20_; #_21_; #_22_; #_23_; #_24_; #_25_; #_26_; #_27_; #_28_; #_29_; #_30_; #_31_; #_32_; #_33_; #_34_; #_35_; #_36_; #_37_; #_38_; #_39_; #_40_; #_41_; #_42_; #_43_; #_44_; #_45_; #_46_; #_47_; #_48_; #_49_; #_50_; #_51_; #_52_; #_53_; #_54_; #_55_; #_56_; #_57_; #_58_; #_59_; #_60_; #_61_; #_62_; #_63_; #_64_ };
let values : [Choice] = [#_31_, #_32_, #_63_, #_64_, #_0_, #_64_, #_32_];
assert Prim.to_candid_canonical(values) == #ok("\44\49\44\4c\02\6d\01\6b\05\00\7f\1f\7f\20\7f\3f\7f\40\7f\01\00\07\01\02\03\04\00\04\02");

// Repeated calls to the same generated helper must have independent bits.
let nested = [[#_64_, #_64_] : [Choice], [#_0_, #_0_] : [Choice]];
let narrow = [[#_64_, #_64_], [#_0_, #_0_]] : [[{ #_0_; #_64_ }]];
assert Prim.to_candid_canonical(nested) == Prim.to_candid_canonical(narrow);
assert Prim.to_candid_canonical([#_32_, #_32_] : [Choice]) ==
  #ok("DIDL\02\6d\01\6b\01\20\7f\01\00\02\00\00");

// Every original element still charges its variant and primitive payload.
// The enclosing record and array consume the remaining two visits exactly.
let largest = Prim.Array_tabulate<Choice>(999_999, func(i) {
  if (i % 2 == 0) #_0_ else #_64_
});
switch (Prim.to_candid_canonical({ values = largest })) {
  case (#ok _) {};
  case (#err _) assert false;
};
let tooMany = Prim.Array_tabulate<Choice>(1_000_000, func(_) { #_64_ });
assert Prim.to_candid_canonical({ values = tooMany }) ==
  #err("value traversal limit");
assert Prim.to_candid_canonical([#_0_, #_0_] : [Choice]) ==
  #ok("DIDL\02\6d\01\6b\01\00\7f\01\00\02\00\00");
