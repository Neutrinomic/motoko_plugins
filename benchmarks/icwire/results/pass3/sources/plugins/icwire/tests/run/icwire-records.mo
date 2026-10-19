//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err e) Prim.trap(debug_show e) }
};
assert ok(Wire.encode({})) == "ICW1\00\00\00\00";
assert ok(Wire.encode({a = 1 : Nat8})) == "ICW1\09\00\00\00\61\00\00\00\01\00\00\00\01";
assert ok(Wire.encode({a = ()})) == "ICW1\08\00\00\00\61\00\00\00\00\00\00\00";
assert ok(Wire.encode({a = null : ?Nat})) == "ICW1\00\00\00\00";
assert ok(Wire.encode({a = ?null : ??Nat})) == "ICW1\0a\00\00\00\61\00\00\00\02\00\00\00\01\00";
assert ok(Wire.decode<{a : ?Nat}>("ICW1\00\00\00\00")) == {a = null};
assert ok(Wire.encode({z = 7 : Nat8; a = 6 : Nat8})) == "ICW1\12\00\00\00\61\00\00\00\01\00\00\00\06\7a\00\00\00\01\00\00\00\07";
// Numeric labels are literal unsigned Candid IDs, sorted without sign truncation.
let numbered = {_4294967295_ = 7 : Nat8; _0_ = 6 : Nat8};
assert ok(Wire.encode(numbered)) == "ICW1\12\00\00\00\00\00\00\00\01\00\00\00\06\ff\ff\ff\ff\01\00\00\00\07";
assert ok(Wire.decode<{_0_ : Nat8; _4294967295_ : Nat8}>(ok(Wire.encode(numbered)))) == numbered;
assert ok(Wire.encode({x_ = 1 : Nat8})) == ok(Wire.encode({x = 1 : Nat8}));
assert ok(Wire.encode(#a(9 : Nat8) : {#a : Nat8; #z})) == "ICW1\61\00\00\00\09";
assert ok(Wire.decode<{#a : Nat8; #z}>("ICW1\61\00\00\00\09")) == #a(9);
// Added fields are length-delimited and skipped, including arbitrary unknown bytes.
assert ok(Wire.decode<{a : Nat8; newField : ?Text}>(ok(Wire.encode({a = 8 : Nat8; z = "future"})))) == {a = 8; newField = null};
ignore ok(Wire.decode<{}>("ICW1\0b\00\00\00\61\00\00\00\03\00\00\00\ff\80\00"));
type Tree = {#leaf : Nat; #node : {left : Tree; right : Tree; name : ?Text}};
let tree : Tree = #node({left = #leaf(18446744073709551616); right = #node({left = #leaf(2); right = #leaf(3); name = ?"inner"}); name = null});
assert ok(Wire.decode<Tree>(ok(Wire.encode(tree)))) == tree;
// Scalar scratch reuse must not alter values already copied into managed arrays.
let mixed : [(Nat, Text, ?Int, {#value : Int}, Blob)] = [
  (18446744073709551616, "x", ?(-1), #value(-18446744073709551617), "\00\ff"),
  (0, "", null, #value(0), ""),
];
assert ok(Wire.decode<[(Nat, Text, ?Int, {#value : Int}, Blob)]>(ok(Wire.encode(mixed)))) == mixed;
