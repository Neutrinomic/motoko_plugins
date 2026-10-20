//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";

type Value = {#ok : {#err : Nat}; #err : Text};
let values : [Value] = [#ok(#err(12345)), #err("handled")];
for (value in values.values()) {
  let bytes = Wire.encodeOrTrap(value);
  assert Wire.encode(value) == #ok bytes;
  assert Wire.encodeBoundedOrTrap(value, 128) == bytes;
  assert Wire.decodeOrTrap<Value>(bytes) == value;
  assert Wire.decode<Value>(bytes) == #ok value;
};

let words : [Nat16] = [0, 1, 65535];
assert Wire.encodeOrTrap(words) == "\03\00\00\01\00\ff\ff";
assert Wire.decodeOrTrap<[Nat16]>("\03\00\00\01\00\ff\ff") == words;
assert Wire.encodeBoundedOrTrap(words, 7) == Wire.encodeOrTrap(words);
assert Wire.encodeOrTrap(()) == "";
assert Wire.encodeBoundedOrTrap((), 0) == "";
Wire.decodeOrTrap<()>("");
let floats : (Float, [Float32]) = (-0.0, [1.5, -0.0]);
assert Wire.encode(floats) == #ok(Wire.encodeOrTrap(floats));
assert Wire.encodeBoundedOrTrap(floats, 32) == Wire.encodeOrTrap(floats);
