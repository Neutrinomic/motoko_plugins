//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err e) Prim.trap(debug_show e) }
};
// Every specialized fixed-width array path preserves its extrema and signedness.
let n8 : [Nat8] = [0, 255];
let n16 : [Nat16] = [0, 65535];
let n32 : [Nat32] = [0, 4294967295];
let n64 : [Nat64] = [0, 18446744073709551615];
let i8 : [Int8] = [-128, 127];
let i16 : [Int16] = [-32768, 32767];
let i32 : [Int32] = [-2147483648, 2147483647];
let i64 : [Int64] = [-9223372036854775808, 9223372036854775807];
assert ok(Wire.encode(n8)) == "\02\00\ff";
assert ok(Wire.encode(n16)) == "\02\00\00\ff\ff";
assert ok(Wire.encode(n32)) == "\02\00\00\00\00\ff\ff\ff\ff";
assert ok(Wire.encode(n64)) == "\02\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff";
assert ok(Wire.encode(i8)) == "\02\80\7f";
assert ok(Wire.encode(i16)) == "\02\00\80\ff\7f";
assert ok(Wire.encode(i32)) == "\02\00\00\00\80\ff\ff\ff\7f";
assert ok(Wire.encode(i64)) == "\02\00\00\00\00\00\00\00\80\ff\ff\ff\ff\ff\ff\ff\7f";
assert ok(Wire.decode<[Nat8]>(ok(Wire.encode(n8)))) == n8;
assert ok(Wire.decode<[Nat16]>(ok(Wire.encode(n16)))) == n16;
assert ok(Wire.decode<[Nat32]>(ok(Wire.encode(n32)))) == n32;
assert ok(Wire.decode<[Nat64]>(ok(Wire.encode(n64)))) == n64;
assert ok(Wire.decode<[Int8]>(ok(Wire.encode(i8)))) == i8;
assert ok(Wire.decode<[Int16]>(ok(Wire.encode(i16)))) == i16;
assert ok(Wire.decode<[Int32]>(ok(Wire.encode(i32)))) == i32;
assert ok(Wire.decode<[Int64]>(ok(Wire.encode(i64)))) == i64;
assert ok(Wire.decode<[Nat8]>("\00")) == [];
assert ok(Wire.decode<[Nat16]>("\00")) == [];
assert ok(Wire.decode<[Nat32]>("\00")) == [];
assert ok(Wire.decode<[Nat64]>("\00")) == [];
assert ok(Wire.decode<[Int8]>("\00")) == [];
assert ok(Wire.decode<[Int16]>("\00")) == [];
assert ok(Wire.decode<[Int32]>("\00")) == [];
assert ok(Wire.decode<[Int64]>("\00")) == [];
assert ok(Wire.encode([] : [Nat8])) == "\00";
assert ok(Wire.encode([] : [Nat16])) == "\00";
assert ok(Wire.encode([] : [Nat32])) == "\00";
assert ok(Wire.encode([] : [Nat64])) == "\00";
assert ok(Wire.encode([] : [Int8])) == "\00";
assert ok(Wire.encode([] : [Int16])) == "\00";
assert ok(Wire.encode([] : [Int32])) == "\00";
assert ok(Wire.encode([] : [Int64])) == "\00";
let record = {a = i64; z = 123 : Nat16};
assert ok(Wire.decode<{a : [Int64]; z : Nat16}>(ok(Wire.encode(record)))) == record;
// Compact length prefixes cross their 7-bit boundaries without adding framing.
let lengths : [(Nat, Blob)] = [(0, "\00"), (127, "\7f"), (128, "\80\01"), (16383, "\ff\7f"), (16384, "\80\80\01")];
for ((length, prefix) in lengths.values()) {
  let bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(length, func i { Prim.natToNat8(i % 256) }));
  let encoded = ok(Wire.encode(bytes));
  let parts = Prim.blobToArray(prefix);
  let raw = Prim.blobToArray(encoded);
  assert raw.size() == length + parts.size();
  var i = 0;
  while (i < parts.size()) { assert raw[i] == parts[i]; i += 1 };
  assert ok(Wire.decode<Blob>(encoded)) == bytes;
  let values = Prim.Array_tabulate<Nat16>(length, func i { Prim.natToNat16(i) });
  let arrayEncoded = ok(Wire.encode(values));
  let arrayRaw = Prim.blobToArray(arrayEncoded);
  assert arrayRaw.size() == length * 2 + parts.size();
  i := 0;
  while (i < parts.size()) { assert arrayRaw[i] == parts[i]; i += 1 };
  assert ok(Wire.decode<[Nat16]>(arrayEncoded)) == values;
};
