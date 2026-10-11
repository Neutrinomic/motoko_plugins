//MOC-FLAG --plugin ../../../../dist/cbor
import Prim "mo:⛔";
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func ok<T>(result : {#ok : T; #err : Error}) : T {
  switch result {case (#ok value) value; case (#err error) Prim.trap(debug_show error)}
};
assert ok(Prim.to_cbor(0 : Nat)) == "\00";
assert ok(Prim.to_cbor(23 : Nat8)) == "\17";
assert ok(Prim.to_cbor(24 : Nat)) == "\18\18";
assert ok(Prim.to_cbor(255 : Nat8)) == "\18\ff";
assert ok(Prim.to_cbor(256 : Nat16)) == "\19\01\00";
assert ok(Prim.to_cbor(65536 : Nat32)) == "\1a\00\01\00\00";
assert ok(Prim.to_cbor(18446744073709551615 : Nat64)) == "\1b\ff\ff\ff\ff\ff\ff\ff\ff";
assert ok(Prim.to_cbor(-1 : Int8)) == "\20";
assert ok(Prim.to_cbor(-128 : Int8)) == "\38\7f";
assert ok(Prim.to_cbor(-32768 : Int16)) == "\39\7f\ff";
assert ok(Prim.to_cbor(-2147483648 : Int32)) == "\3a\7f\ff\ff\ff";
assert ok(Prim.to_cbor(-9223372036854775808 : Int64)) == "\3b\7f\ff\ff\ff\ff\ff\ff\ff";
assert ok(Prim.to_cbor(18446744073709551616 : Nat)) == "\c2\49\01\00\00\00\00\00\00\00\00";
assert ok(Prim.to_cbor(-18446744073709551617 : Int)) == "\c3\49\01\00\00\00\00\00\00\00\00";
assert ok(Prim.from_cbor<Int>("\3b\ff\ff\ff\ff\ff\ff\ff\ff")) == -18446744073709551616;
let ints : [Int] = [-99999999999999999999999999999999, -9223372036854775808,-129,-128,-65,-64,-1,0,1,63,64,127,128,18446744073709551616,99999999999999999999999999999999];
assert ok(Prim.from_cbor<[Int]>(ok(Prim.to_cbor(ints)))) == ints;
assert ok(Prim.from_cbor<Nat64>("\c2\49\00\ff\ff\ff\ff\ff\ff\ff\ff")) == 18446744073709551615;
assert ok(Prim.to_cbor(true)) == "\f5";
assert ok(Prim.to_cbor(false)) == "\f4";
assert ok(Prim.to_cbor(null)) == "\f6";
assert ok(Prim.to_cbor("a\u{2603}" : Text)) == "\64a\e2\98\83";
assert ok(Prim.to_cbor("\00\ff" : Blob)) == "\42\00\ff";
assert ok(Prim.from_cbor<Char>(ok(Prim.to_cbor('😀')))) == '😀';
let principal = Prim.principalOfBlob("\04");
assert ok(Prim.to_cbor(principal)) == "\41\04";
assert ok(Prim.from_cbor<Principal>("\41\04")) == principal;
assert ok(Prim.to_cbor(0.0 : Float)) == "\f9\00\00";
assert ok(Prim.to_cbor(-0.0 : Float)) == "\f9\80\00";
assert ok(Prim.to_cbor(1.5 : Float)) == "\f9\3e\00";
assert ok(Prim.to_cbor(65504.0 : Float)) == "\f9\7b\ff";
assert ok(Prim.to_cbor(0.00006103515625 : Float)) == "\f9\04\00";
assert ok(Prim.to_cbor(100000.0 : Float)) == "\fa\47\c3\50\00";
assert ok(Prim.to_cbor(1.1 : Float)) == "\fb\3f\f1\99\99\99\99\99\9a";
assert ok(Prim.to_cbor(1.5 : Float32)) == "\f9\3e\00";
assert ok(Prim.from_cbor<Float>("\f9\00\01")) == 0.000000059604644775390625;
assert ok(Prim.from_cbor<Float32>(ok(Prim.to_cbor(1.1 : Float32)))) == (1.1 : Float32);
let nan : Float = 0.0 / 0.0;
assert ok(Prim.to_cbor(nan)) == "\f9\7e\00";
assert ok(Prim.to_cbor(1.0 / 0.0 : Float)) == "\f9\7c\00";
assert ok(Prim.to_cbor(-1.0 / 0.0 : Float)) == "\f9\fc\00";

// Independent wire data interleaves retained big/small integers and borrowed
// Text/Blob values. Later scratch reuse must not change earlier array entries.
let mixed = ok(Prim.from_cbor<[(Nat, Text, ?Int, {#value : Int}, Blob)]>(
  "\82\85\c2\49\01\00\00\00\00\00\00\00\00\61x\20\a1\65value\c3\49\01\00\00\00\00\00\00\00\00\42\00\ff\85\00\60\f6\a1\65value\00\40"));
assert mixed == [
  (18446744073709551616, "x", ?(-1), #value(-18446744073709551617), "\00\ff"),
  (0, "", null, #value(0), ""),
];
