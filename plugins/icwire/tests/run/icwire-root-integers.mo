//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

// Wrapping the same scalar in a one-field positional record uses the unchanged
// general leaf decoder and exactly the same bytes, providing a differential
// oracle for values, malformed-input precedence and absolute error offsets.
func check(bytes : Blob) {
  let nat : Wire.Result<Nat> = switch (Wire.decode<{value : Nat}>(bytes)) {
    case (#ok record) #ok(record.value);
    case (#err error) #err(error);
  };
  let int : Wire.Result<Int> = switch (Wire.decode<{value : Int}>(bytes)) {
    case (#ok record) #ok(record.value);
    case (#err error) #err(error);
  };
  assert Wire.decode<Nat>(bytes) == nat;
  assert Wire.decode<Int>(bytes) == int;
};
check("");
var first = 0;
while (first < 256) {
  check(Prim.arrayToBlob([Prim.natToNat8(first)]));
  var second = 0;
  while (second < 256) {
    check(Prim.arrayToBlob([Prim.natToNat8(first), Prim.natToNat8(second)]));
    second += 1;
  };
  first += 1;
};

var width = 3;
while (width <= 10) {
  var sample = 0;
  while (sample < 256) {
    let raw = Prim.Array_tabulate<Nat8>(width, func index {
      if (index + 1 == width) Prim.natToNat8(sample % 128)
      else Prim.natToNat8(128 + ((sample * 53 + index * 17) % 128))
    });
    check(Prim.arrayToBlob(raw));
    // Every prefix and a zero/nonzero suffix test exact consumption and safe
    // loads. Flip each byte's continuation bit to expose early termination.
    var count = 0;
    while (count < width) {
      check(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(count, func index {raw[index]})));
      check(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(width, func index {
        if (index == count) raw[index] ^ 128 else raw[index]
      })));
      count += 1;
    };
    for (suffix in ([0, 127, 128, 255] : [Nat8]).values()) {
      check(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(width + 1, func index {
        if (index == width) suffix else raw[index]
      })));
    };
    sample += 1;
  };
  width += 1;
};

// Exact signed and unsigned transitions, including the nine/ten-byte fallback.
var bits = 0;
while (bits <= 70) {
  let boundary : Nat = 2 ** bits;
  for (value in [(boundary - 1 : Nat), boundary, boundary + 1].values()) {
    switch (Wire.encode(value)) {
      case (#ok bytes) check(bytes);
      case (#err error) Prim.trap(debug_show error);
    };
    let signed : Int = value;
    for (number in [signed, -signed].values()) {
      switch (Wire.encode(number)) {
        case (#ok bytes) check(bytes);
        case (#err error) Prim.trap(debug_show error);
      };
    };
  };
  bits += 1;
};
