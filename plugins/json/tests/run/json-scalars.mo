//MOC-FLAG --plugin ../../../../dist/json
import Prim "mo:⛔";
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func ok<T>(result : {#ok : T; #err : Error}) : T {
  switch result {case (#ok value) value; case (#err error) Prim.trap(debug_show error)}
};
assert ok(Prim.to_json(184467440737095516160000000000000000000 : Nat)) == "\"184467440737095516160000000000000000000\"";
assert ok(Prim.from_json<Nat>("184467440737095516160000000000000000000")) == 184467440737095516160000000000000000000;
assert ok(Prim.from_json<Int>("\"-184467440737095516160000000000000000000\"")) == -184467440737095516160000000000000000000;
assert ok(Prim.from_json<Int>("\"-0\"")) == 0;
assert ok(Prim.from_json<Int8>("-128")) == -128;
assert ok(Prim.from_json<Int16>("-32768")) == -32768;
assert ok(Prim.from_json<Int32>("-2147483648")) == -2147483648;
assert ok(Prim.from_json<Int64>("\"-9223372036854775808\"")) == -9223372036854775808;
assert ok(Prim.to_json(18446744073709551615 : Nat64)) == "\"18446744073709551615\"";
assert ok(Prim.from_json<Nat64>("18446744073709551615")) == 18446744073709551615;
assert ok(Prim.from_json<Nat8>("255")) == 255;
assert ok(Prim.from_json<Nat16>("65535")) == 65535;
assert ok(Prim.from_json<Nat32>("4294967295")) == 4294967295;
assert ok(Prim.to_json(-128 : Int8)) == "-128";
assert ok(Prim.to_json(-32768 : Int16)) == "-32768";
assert ok(Prim.to_json(-2147483648 : Int32)) == "-2147483648";
assert ok(Prim.to_json(255 : Nat8)) == "255";
assert ok(Prim.from_json<Float>(ok(Prim.to_json(1.25 : Float)))) == 1.25;
assert ok(Prim.from_json<Float32>(ok(Prim.to_json(1.25 : Float32)))) == (1.25 : Float32);
assert ok(Prim.to_json(1.0 / 0.0 : Float)) == "\"Infinity\"";
assert ok(Prim.from_json<Float>("\"-Infinity\"")) == -1.0 / 0.0;
let nan = ok(Prim.from_json<Float>("\"NaN\"")); assert nan != nan;
assert ok(Prim.from_json<Text>("\"\\uD83D\\uDE00\\n\\u0061\"")) == "😀\na";
assert ok(Prim.from_json<Char>("\"😀\"")) == '😀';
assert ok(Prim.to_json('☃')) == "\"☃\"";
let bytes : Blob = "\00\ff\80hello";
assert ok(Prim.from_json<Blob>(ok(Prim.to_json(bytes)))) == bytes;
assert ok(Prim.to_json("a" : Blob)) == "\"YQ==\"";
let principal_ = Prim.principalOfBlob("\04");
assert ok(Prim.to_json(principal_)) == "\"2vxsx-fae\"";
assert ok(Prim.from_json<Principal>("\"2vxsx-fae\"")) == principal_;
