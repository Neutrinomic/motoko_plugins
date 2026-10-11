//MOC-FLAG --plugin ../../../../dist/candidx
import Prim "mo:⛔";

// Errors are ordinary variant values; a failed call cannot poison the next one.
let huge = 2 ** 28_673 : Nat;
assert Prim.to_candid_canonical(huge) == #err("integer length limit");
type Chain = ?(Nat, Chain);
var chain : Chain = null;
var count = 0;
while (count < 140) {
  chain := ?(count, chain);
  count += 1;
};
assert Prim.to_candid_canonical(chain) == #err("value nesting limit");
assert Prim.to_candid_canonical([null, ?1] : [?Nat]) ==
  #ok("DIDL\02\6d\01\6e\7d\01\00\02\00\01\01");

// A static schema has no Rust shape context, but exposes the same Result API.
let tooLong = Prim.Array_tabulate<Null>(2_000_001, func(_) { null });
assert Prim.to_candid_canonical(tooLong) == #err("collection length limit");
assert Prim.to_candid_canonical(7 : Nat64) == #ok("DIDL\00\01\78\07\00\00\00\00\00\00\00");

// Large repeated text exercises the output limit in a specialized static
// array. Sizing must return the error before allocating the output Blob.
var text = "x";
var doubling = 0;
while (doubling < 20) {
  text #= text;
  doubling += 1;
};
let texts = Prim.Array_tabulate<Text>(33, func(_) { text });
assert Prim.to_candid_canonical(texts) == #err("output byte limit");
assert Prim.to_candid_canonical(null) == #ok("DIDL\00\01\7f");

// An optional array uses the dynamic shape path. Each fixed record charges
// four visits even though its three null fields require no payload bytes.
let row = { _0_ = null; _1_ = null; _2_ = null };
let withinVisits = Prim.Array_tabulate(499_999, func(_) { row });
switch (Prim.to_candid_canonical(?withinVisits)) {
  case (#ok _) {};
  case (#err _) assert false;
};
let tooManyVisits = Prim.Array_tabulate(500_000, func(_) { row });
assert Prim.to_candid_canonical(?tooManyVisits) == #err("value traversal limit");
assert Prim.to_candid_canonical(?[row]) ==
  #ok("DIDL\03\6e\01\6d\02\6c\03\00\7f\01\7f\02\7f\01\00\01\01");
