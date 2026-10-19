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
