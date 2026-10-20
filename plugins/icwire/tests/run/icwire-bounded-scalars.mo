//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err error) Prim.trap(debug_show error) }
};
func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected " # debug_show (kind, offset));
    case (#err error) assert error == {kind; offset = Prim.natToNat64(offset)};
  }
};
// Each scalar is atomic: every short capacity fails at its starting position.
// Literal goldens are independent of the ordinary encoder.
var cases = 0;
func scalar(bytes : Blob, encode : Nat -> Wire.Result<Blob>) {
  var capacity = 0;
  while (capacity < bytes.size()) {
    at(encode(capacity), "limit", 0);
    capacity += 1;
  };
  assert ok(encode(bytes.size())) == bytes;
  assert ok(encode(bytes.size() + 37)) == bytes;
  cases += 1;
};
scalar("", func n { Wire.encodeBounded(null, n) });
scalar("", func n { Wire.encodeBounded((), n) });
scalar("", func n { Wire.encodeBounded({}, n) });
scalar("\00", func n { Wire.encodeBounded(false, n) });
scalar("\01", func n { Wire.encodeBounded(true, n) });
scalar("\ff", func n { Wire.encodeBounded(255 : Nat8, n) });
scalar("\34\12", func n { Wire.encodeBounded(0x1234 : Nat16, n) });
scalar("\78\56\34\12", func n { Wire.encodeBounded(0x12345678 : Nat32, n) });
scalar("\ef\cd\ab\89\67\45\23\01", func n { Wire.encodeBounded(0x0123456789abcdef : Nat64, n) });
scalar("\80", func n { Wire.encodeBounded(-128 : Int8, n) });
scalar("\00\80", func n { Wire.encodeBounded(-32768 : Int16, n) });
scalar("\00\00\00\80", func n { Wire.encodeBounded(-2147483648 : Int32, n) });
scalar("\00\00\00\00\00\00\00\80", func n { Wire.encodeBounded(-9223372036854775808 : Int64, n) });
scalar("\00", func n { Wire.encodeBounded(0 : Nat, n) });
scalar("\80\01", func n { Wire.encodeBounded(128 : Nat, n) });
scalar("\bf\7f", func n { Wire.encodeBounded(-65 : Int, n) });
scalar("\c0\00", func n { Wire.encodeBounded(64 : Int, n) });
scalar("\00\f6\01\00", func n { Wire.encodeBounded('😀', n) });
scalar("\00\00\00\00\00\00\f8\3f", func n { Wire.encodeBounded(1.5 : Float, n) });
scalar("\00\00\c0\3f", func n { Wire.encodeBounded(1.5 : Float32, n) });
scalar("\00\00\00\00\00\00\00\80", func n { Wire.encodeBounded(-0.0 : Float, n) });
scalar("\00\00\00\80", func n { Wire.encodeBounded(-0.0 : Float32, n) });
scalar("\00", func n { Wire.encodeBounded("" : Blob, n) });
scalar("\02\00\ff", func n { Wire.encodeBounded("\00\ff" : Blob, n) });
scalar("\00", func n { Wire.encodeBounded("" : Text, n) });
scalar("\04a\e2\98\83", func n { Wire.encodeBounded("a☃" : Text, n) });
let principal = Prim.principalOfBlob("\04");
scalar("\01\04", func n { Wire.encodeBounded(principal, n) });
let longest = Prim.principalOfBlob("abcdefghijklmnopqrstuvwxyz123");
scalar("\1dabcdefghijklmnopqrstuvwxyz123", func n { Wire.encodeBounded(longest, n) });

// Concatenation produces runtime Text ropes; capacity counts UTF-8 bytes,
// including the complete length prefix, rather than characters or rope leaves.
var rope = "";
var index = 0;
while (index < 80) { rope #= "λ😀"; index += 1 };
let ropeBytes = ok(Wire.encode(rope));
assert ropeBytes.size() == 482;
scalar(ropeBytes, func n { Wire.encodeBounded(rope, n) });
let blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(128, func i { Prim.natToNat8(i) }));
let blobBytes = ok(Wire.encode(blob));
assert blobBytes.size() == 130;
scalar(blobBytes, func n { Wire.encodeBounded(blob, n) });

// Bound validation precedes inspecting even a zero-byte or non-finite value.
assert ok(Wire.encodeBounded((), 16_777_216)) == "";
assert ok(Wire.encodeBounded(7 : Nat8, 16_777_216)) == "\07";
for (bound in [16_777_217, 2 ** 63, 2 ** 512].values()) {
  at(Wire.encodeBounded((), bound), "limit", 0);
  at(Wire.encodeBounded(0.0 / 0.0 : Float, bound), "limit", 0);
};
// Once a valid bound is admitted, float validity wins over capacity at the
// same scalar. This also checks the fixed-width fast path's diagnostic retry.
for (capacity in [0, 1, 3, 4, 7, 8, 32].values()) {
  at(Wire.encodeBounded(0.0 / 0.0 : Float, capacity), "float", 0);
  at(Wire.encodeBounded(1.0 / 0.0 : Float, capacity), "float", 0);
  at(Wire.encodeBounded(-1.0 / 0.0 : Float32, capacity), "float", 0);
};

// Aliases retain intrinsic specialization, and both arguments evaluate once
// from left to right, including rejected bounds and encoding failures.
let codec = { encode = Wire.encodeBounded };
var visits = 0;
func value() : (Nat8, Blob) {
  assert visits % 2 == 0;
  visits += 1;
  (7, "\00\ff")
};
func bound(n : Nat) : Nat {
  assert visits % 2 == 1;
  visits += 1;
  n
};
assert ok(codec.encode(value(), bound(4))) == "\07\02\00\ff";
at(codec.encode(value(), bound(3)), "limit", 1);
at(codec.encode(value(), bound(16_777_217)), "limit", 0);
assert visits == 6;
assert cases == 30;
Prim.debugPrint("bounded scalars: 30");
