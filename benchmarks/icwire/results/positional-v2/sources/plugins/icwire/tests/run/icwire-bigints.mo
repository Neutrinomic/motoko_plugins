//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err e) Prim.trap(debug_show e) }
};
// Literal goldens cross the 9/10, 18/19, and 27/28-byte reconstruction paths.
// Each signed transition includes the largest positive and smallest negative
// value at the shorter width, and the first value requiring another byte.
let nats : [(Nat, Blob)] = [
  (9223372036854775807, "\ff\ff\ff\ff\ff\ff\ff\ff\7f"), // 9 bytes
  (9223372036854775808, "\80\80\80\80\80\80\80\80\80\01"), // 10 bytes
  (85070591730234615865843651857942052863, "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\7f"), // 18 bytes
  (85070591730234615865843651857942052864, "\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\01"), // 19 bytes
  (784637716923335095479473677900958302012794430558004314111, "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\7f"), // 27 bytes
  (784637716923335095479473677900958302012794430558004314112, "\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\01"), // 28 bytes
  (156797324626531188993, "\81\82\80\80\80\80\80\80\80\11"), // 10 bytes
  (10633823966279326992453828519097532673, "\81\82\80\80\80\80\80\80\80\81\80\80\80\80\80\80\80\10"), // 18 bytes
  (1361129467683753853862721801763927621889, "\81\82\80\80\80\80\80\80\80\81\80\80\80\80\80\80\80\80\10"), // 19 bytes
  (98079714615416886934934209737619787760822675856605315329, "\81\82\80\80\80\80\80\80\80\81\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\10"), // 27 bytes
  (12554203470773361527671578846415332832213934260964923801857, "\81\82\80\80\80\80\80\80\80\81\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\10"), // 28 bytes
];
let ints : [(Int, Blob)] = [
  (4611686018427387903, "\ff\ff\ff\ff\ff\ff\ff\ff\3f"), // 9 bytes
  (4611686018427387904, "\80\80\80\80\80\80\80\80\c0\00"), // 10 bytes
  (-4611686018427387904, "\80\80\80\80\80\80\80\80\40"), // 9 bytes
  (-4611686018427387905, "\ff\ff\ff\ff\ff\ff\ff\ff\bf\7f"), // 10 bytes
  (42535295865117307932921825928971026431, "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\3f"), // 18 bytes
  (42535295865117307932921825928971026432, "\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\c0\00"), // 19 bytes
  (-42535295865117307932921825928971026432, "\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\40"), // 18 bytes
  (-42535295865117307932921825928971026433, "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\bf\7f"), // 19 bytes
  (392318858461667547739736838950479151006397215279002157055, "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\3f"), // 27 bytes
  (392318858461667547739736838950479151006397215279002157056, "\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\c0\00"), // 28 bytes
  (-392318858461667547739736838950479151006397215279002157056, "\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\40"), // 27 bytes
  (-392318858461667547739736838950479151006397215279002157057, "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\bf\7f"), // 28 bytes
  (156797324626531188993, "\81\82\80\80\80\80\80\80\80\11"), // 10 bytes
  (-156797324626531188993, "\ff\fd\ff\ff\ff\ff\ff\ff\ff\6e"), // 10 bytes
  (10633823966279326992453828519097532673, "\81\82\80\80\80\80\80\80\80\81\80\80\80\80\80\80\80\10"), // 18 bytes
  (-10633823966279326992453828519097532673, "\ff\fd\ff\ff\ff\ff\ff\ff\ff\fe\ff\ff\ff\ff\ff\ff\ff\6f"), // 18 bytes
  (1361129467683753853862721801763927621889, "\81\82\80\80\80\80\80\80\80\81\80\80\80\80\80\80\80\80\10"), // 19 bytes
  (-1361129467683753853862721801763927621889, "\ff\fd\ff\ff\ff\ff\ff\ff\ff\fe\ff\ff\ff\ff\ff\ff\ff\ff\6f"), // 19 bytes
  (98079714615416886934934209737619787760822675856605315329, "\81\82\80\80\80\80\80\80\80\81\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\10"), // 27 bytes
  (-98079714615416886934934209737619787760822675856605315329, "\ff\fd\ff\ff\ff\ff\ff\ff\ff\fe\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\6f"), // 27 bytes
  (12554203470773361527671578846415332832213934260964923801857, "\81\82\80\80\80\80\80\80\80\81\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\80\10"), // 28 bytes
  (-12554203470773361527671578846415332832213934260964923801857, "\ff\fd\ff\ff\ff\ff\ff\ff\ff\fe\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\6f"), // 28 bytes
 ];
var digest : Nat64 = 14695981039346656037;
var successes = 0;
var errors = 0;
func record(bytes : Blob, outcome : Wire.Result<Blob>) {
  switch outcome { case (#ok _) successes += 1; case (#err _) errors += 1 };
  for (byte in Prim.encodeUtf8(debug_show (bytes.size(), outcome)).values()) {
    digest := (digest ^ Prim.natToNat64(Prim.nat8ToNat(byte))) *% 1099511628211;
  };
  digest := (digest ^ 255) *% 1099511628211;
};
func inspectNat(bytes : Blob) {
  record(bytes, switch (Wire.decode<Nat>(bytes)) {
    case (#ok value) Wire.encode(value);
    case (#err error) #err error;
  });
};
func inspectInt(bytes : Blob) {
  record(bytes, switch (Wire.decode<Int>(bytes)) {
    case (#ok value) Wire.encode(value);
    case (#err error) #err error;
  });
};
func exercise(bytes : Blob, inspect : Blob -> ()) {
  inspect(bytes);
  let raw = Prim.blobToArray(bytes);
  var position = 0;
  while (position < raw.size()) {
    inspect(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(position, func i { raw[i] })));
    for (mask in ([1, 128, 255] : [Nat8]).values()) {
      inspect(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(raw.size(), func i {
        if (i == position) raw[i] ^ mask else raw[i]
      })));
    };
    position += 1;
  };
};
for ((value, golden) in nats.values()) {
  assert ok(Wire.encode(value)) == golden;
  assert ok(Wire.decode<Nat>(golden)) == value;
  // Non-root reconstruction must preserve earlier and later managed values.
  let tuple = (value, value + 1, value);
  assert ok(Wire.decode<(Nat, Nat, Nat)>(ok(Wire.encode(tuple)))) == tuple;
  exercise(golden, inspectNat);
};
for ((value, golden) in ints.values()) {
  assert ok(Wire.encode(value)) == golden;
  assert ok(Wire.decode<Int>(golden)) == value;
  let tuple = (value, -value, value);
  assert ok(Wire.decode<(Int, Int, Int)>(ok(Wire.encode(tuple)))) == tuple;
  exercise(golden, inspectInt);
};
let natValues = Prim.Array_tabulate<Nat>(nats.size(), func i { nats[i].0 });
let intValues = Prim.Array_tabulate<Int>(ints.size(), func i { ints[i].0 });
assert ok(Wire.decode<[Nat]>(ok(Wire.encode(natValues)))) == natValues;
assert ok(Wire.decode<[Int]>(ok(Wire.encode(intValues)))) == intValues;
assert successes > 100;
assert errors > 100;
Prim.debugPrint(debug_show (successes, errors, digest));
