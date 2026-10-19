//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err e) Prim.trap(debug_show e) }
};
func limit<T>(result : Wire.Result<T>) {
  switch result { case (#ok _) Prim.trap("expected limit"); case (#err e) assert e.kind == "limit" }
};
type Chain = ?(Nat8, Chain);
func chain(n : Nat) : Chain {
  var value : Chain = null;
  var count = n;
  while (count > 0) { value := ?(8, value); count -= 1 };
  value
};
let allowed = chain(63);
assert ok(Wire.decode<Chain>(ok(Wire.encode(allowed)))) == allowed;
limit(Wire.encode(chain(64)));
let header : [Nat8] = [73, 67, 87, 49];
let tooDeep = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(133, func i {
  if (i < 4) header[i] else if (i == 132) 0 else if (i % 2 == 0) 1 else 8
}));
limit(Wire.decode<Chain>(tooDeep));
// A zero-byte element still consumes work. Reject before allocating the array.
limit(Wire.decode<[Null]>("ICW1\40\42\0f\00"));
// Exactly 4096 canonical integer bytes is accepted; a 4097th is never read.
let large : Nat = 2 ** (4095 * 7);
let encoded = ok(Wire.encode(large));
assert encoded.size() == 4100;
assert ok(Wire.decode<Nat>(encoded)) == large;
limit(Wire.encode(large * 128));
let largestNat : Nat = 2 ** (4096 * 7) - 1;
let largestNatBytes = ok(Wire.encode(largestNat));
assert largestNatBytes.size() == 4100;
assert ok(Wire.decode<Nat>(largestNatBytes)) == largestNat;
let signedBoundary : Int = 2 ** (4096 * 7 - 1);
for (value in [signedBoundary - 1, -signedBoundary].values()) {
  let bytes = ok(Wire.encode(value));
  assert bytes.size() == 4100;
  assert ok(Wire.decode<Int>(bytes)) == value;
};
limit(Wire.encode(signedBoundary));
limit(Wire.encode(-signedBoundary - 1));
let unbounded = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(4101, func i {
  if (i < 4) header[i] else if (i == 4100) 1 else 128
}));
limit(Wire.decode<Nat>(unbounded));
limit(Wire.decode<Int>(unbounded));
