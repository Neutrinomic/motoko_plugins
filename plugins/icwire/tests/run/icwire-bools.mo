//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err e) Prim.trap(debug_show e) }
};
func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected " # kind);
    case (#err error) {
      if (error.kind != kind or Prim.nat64ToNat(error.offset) != offset) {
        Prim.trap("expected " # debug_show (kind, offset) # ", got " # debug_show error)
      }
    };
  }
};
assert ok(Wire.decode<[Bool]>("\00")) == [];
assert ok(Wire.decode<[Bool]>("\02\00\01")) == [false, true];
assert ok(Wire.encode([false, true])) == "\02\00\01";
for ((size, prefix) in ([(127, "\7f"), (128, "\80\01")] : [(Nat, Blob)]).values()) {
  let values = Prim.Array_tabulate<Bool>(size, func i { i % 2 == 1 });
  let encoded = ok(Wire.encode(values));
  let bytes = Prim.blobToArray(encoded);
  let head = Prim.blobToArray(prefix);
  assert bytes.size() == size + head.size();
  var index = 0;
  while (index < head.size()) { assert bytes[index] == head[index]; index += 1 };
  assert ok(Wire.decode<[Bool]>(encoded)) == values;
};
at(Wire.decode<[Bool]>("\00\02"), "trailing", 1);
// Invalid values win over a later missing element: validation follows wire order.
at(Wire.decode<[Bool]>("\04\02"), "bool", 1);
at(Wire.decode<[Bool]>("\04\01\02"), "bool", 2);
at(Wire.decode<[Bool]>("\04\00\01\ff"), "bool", 3);
at(Wire.decode<[Bool]>("\03\02\01\00"), "bool", 1);
at(Wire.decode<[Bool]>("\03\00\02\01"), "bool", 2);
at(Wire.decode<[Bool]>("\03\00\01\ff"), "bool", 3);
at(Wire.decode<[Bool]>("\03"), "truncated", 1);
at(Wire.decode<[Bool]>("\03\01"), "truncated", 2);
at(Wire.decode<[Bool]>("\03\00\01"), "truncated", 3);
// Borrowed bytes cannot overrun following values or change absolute error offsets.
let record = {a = [true, false, true]; z = 0x1234 : Nat16};
assert ok(Wire.encode(record)) == "\03\01\00\01\34\12";
assert ok(Wire.decode<{a : [Bool]; z : Nat16}>("\03\01\00\01\34\12")) == record;
let nested : [[Bool]] = [[true, false], [], [false]];
assert ok(Wire.decode<[[Bool]]>(ok(Wire.encode(nested)))) == nested;
at(Wire.decode<(Nat16, [Bool], Nat8)>("\34\12\03\00\02"), "bool", 4);
at(Wire.decode<(Nat16, [Bool], Nat8)>("\34\12\03\00\01"), "truncated", 5);
at(Wire.decode<(Nat16, [Bool], Nat8)>("\34\12\03\00\01\00"), "truncated", 6);
// Array admission checks the remaining typed-node budget before reading payloads.
at(Wire.decode<[Bool]>("\c0\84\3d\02"), "limit", 3); // 1,000,000 children
at(Wire.decode<[Bool]>("\bf\84\3d"), "truncated", 3); // 999,999 children fit
at(Wire.decode<(Null, [Bool])>("\be\84\3d\02"), "limit", 3); // 999,998 exceed the remaining budget
at(Wire.decode<(Null, [Bool])>("\bd\84\3d"), "truncated", 3); // 999,997 children fit
// An empty Bool array fits at depth 128; a child would exceed that depth first.
type Nest = {#next : Nest; #end : [Bool]};
func nest(n : Nat, values : [Bool]) : Nest {
  var value : Nest = #end(values);
  var count = n;
  while (count > 0) { value := #next(value); count -= 1 };
  value
};
let populated = nest(125, [false, true]);
assert ok(Wire.decode<Nest>(ok(Wire.encode(populated)))) == populated;
let deep = nest(126, []);
assert ok(Wire.decode<Nest>(ok(Wire.encode(deep)))) == deep;
at(Wire.encode(nest(126, [false])), "limit", 128);
let tooDeep = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(129, func i {
  if (i < 126) 1 else if (i == 126) 0 else if (i == 127) 1 else 2
}));
at(Wire.decode<Nest>(tooDeep), "limit", 128);
// Compare every byte value at every array position, with and without a later suffix.
var digest : Nat64 = 14695981039346656037;
var successes = 0;
var errors = 0;
func inspect(bytes : Blob) {
  let outcome : Wire.Result<Blob> = switch (Wire.decode<[Bool]>(bytes)) {
    case (#ok value) {
      successes += 1;
      let encoded = ok(Wire.encode(value));
      assert encoded == bytes;
      #ok encoded
    };
    case (#err error) { errors += 1; #err error };
  };
  for (byte in Prim.encodeUtf8(debug_show (bytes.size(), outcome)).values()) {
    digest := (digest ^ Prim.natToNat64(Prim.nat8ToNat(byte))) *% 1099511628211;
  };
  digest := (digest ^ 255) *% 1099511628211;
};
var position = 0;
while (position < 3) {
  var byte = 0;
  while (byte < 256) {
    let value = Prim.natToNat8(byte);
    inspect(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(4, func i {
      if (i == 0) 3 else if (i == position + 1) value else 1
    })));
    inspect(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(position + 2, func i {
      if (i == 0) 4 else if (i == position + 1) value else 1
    })));
    byte += 1;
  };
  position += 1;
};
assert successes == 6;
assert errors == 1530;
Prim.debugPrint(debug_show (successes, errors, digest));
