//MOC-FLAG --plugin ../../../../dist/candidx

import Prim "mo:⛔";

type Row = { _0_ : Nat16; _1_ : Nat8 };
assert Prim.to_candid_canonical([] : [Row]) ==
  #ok("DIDL\01\6d\6f\01\00\00");
assert Prim.to_candid_canonical([{ _0_ = 1; _1_ = 2 }] : [Row]) ==
  #ok("DIDL\02\6d\01\6c\02\00\7a\01\7b\01\00\01\01\00\02");

// Records containing only nulls consume visits but have no payload bytes.
assert Prim.to_candid_canonical([{ _0_ = null }, { _0_ = null }]) ==
  #ok("DIDL\02\6d\01\6c\01\00\7f\01\00\02");

// Binary lengths vary independently inside a vector's fixed wire shape.
// Blob and [Nat8] must share the same type-table entry.
let binaries = [
  { _0_ = "a" : Blob; _1_ = [] : [Nat8] },
  { _0_ = "" : Blob; _1_ = [0, 255] : [Nat8] },
];
assert Prim.to_candid_canonical(binaries) ==
  Prim.to_candid_canonical([
    { _0_ = "a" : Blob; _1_ = "" : Blob },
    { _0_ = "" : Blob; _1_ = "\00\ff" : Blob },
  ]);

// Deduplicate record children by wire shape even when Motoko layouts differ.
let chars = [{ _0_ = { _0_ = 'a' }; _1_ = { _0_ = 97 : Nat32 } }];
assert Prim.to_candid_canonical(chars) ==
  #ok("DIDL\03\6d\01\6c\02\00\02\01\02\6c\01\00\79\01\00\01\61\00\00\00\61\00\00\00");

// Type recursion must terminate in the fixed-size analysis even when there
// are no values of the recursive type in this particular input.
type Recursive = { next : Recursive };
assert Prim.to_candid_canonical([] : [Recursive]) ==
  #ok("DIDL\01\6d\6f\01\00\00");

// An enclosing option selects dynamic headers. Empty and repeated fixed
// records must still use the canonical value-derived vector element shape.
assert Prim.to_candid_canonical(?([] : [Row])) ==
  #ok("DIDL\02\6e\01\6d\6f\01\00\01\00");
let rows : [Row] = [{ _0_ = 1; _1_ = 2 }, { _0_ = 3; _1_ = 4 }];
assert Prim.to_candid_canonical(?rows) ==
  #ok("DIDL\03\6e\01\6d\02\6c\02\00\7a\01\7b\01\00\01\02\01\00\02\03\00\04");

// The first fixed element must retain the full value-depth validation.
// Here its fields are exactly at depth 256, then two levels too deep.
type Nested = ?{ rows : [Row]; next : Nested };
var nested : Nested = ?{ rows; next = null };
var depth = 0;
while (depth < 126) {
  nested := ?{ rows = []; next = nested };
  depth += 1;
};
switch (Prim.to_candid_canonical(nested)) {
  case (#ok _) {};
  case (#err _) assert false;
};
nested := ?{ rows = []; next = nested };
assert Prim.to_candid_canonical(nested) == #err("value nesting limit");
