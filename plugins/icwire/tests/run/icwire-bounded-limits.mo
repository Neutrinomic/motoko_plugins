//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err error) Prim.trap(debug_show error) }
};
func limit<T>(result : Wire.Result<T>, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected limit at " # debug_show offset);
    case (#err error) assert error == {kind = "limit"; offset = Prim.natToNat64(offset)};
  }
};
func repeated(width : Nat, body : Nat8, last : Nat8) : Blob {
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(width, func i { if (i + 1 == width) last else body }))
};
// Independent byte patterns cross compact integers, managed limbs and the
// largest accepted arbitrary integer. Width is wire bytes, not machine bits.
for (width in [9, 10, 18, 19, 63, 64, 65, 127, 128, 129, 1024, 4096].values()) {
  let natural : Nat = 2 ** (width * 7) - 1;
  let positive : Int = 2 ** (width * 7 - 1) - 1;
  let negative : Int = -(positive + 1);
  let natBytes = repeated(width, 255, 127);
  let positiveBytes = repeated(width, 255, 63);
  let negativeBytes = repeated(width, 128, 64);
  assert ok(Wire.encodeBounded(natural, width)) == natBytes;
  assert ok(Wire.encodeBounded(positive, width)) == positiveBytes;
  assert ok(Wire.encodeBounded(negative, width)) == negativeBytes;
  assert ok(Wire.encodeBounded(natural, width + 100)) == natBytes;
  assert ok(Wire.encodeBounded(positive, width + 100)) == positiveBytes;
  assert ok(Wire.encodeBounded(negative, width + 100)) == negativeBytes;
  limit(Wire.encodeBounded(natural, Prim.abs((width : Int) - 1)), 0);
  limit(Wire.encodeBounded(positive, Prim.abs((width : Int) - 1)), 0);
  limit(Wire.encodeBounded(negative, Prim.abs((width : Int) - 1)), 0);
  assert ok(Wire.decode<Nat>(natBytes)) == natural;
  assert ok(Wire.decode<Int>(positiveBytes)) == positive;
  assert ok(Wire.decode<Int>(negativeBytes)) == negative;
  let nested = (?(negative), [natural], positive);
  let encoded = ok(Wire.encodeBounded(nested, width * 3 + 2));
  assert encoded == ok(Wire.encode(nested));
  assert ok(Wire.decode<(?Int, [Nat], Int)>(encoded)) == nested;
  limit(Wire.encodeBounded((7 : Nat8, negative), width), 1);
};
let excessiveNat : Nat = 2 ** (4096 * 7);
let excessiveInt : Int = 2 ** (4096 * 7 - 1);
limit(Wire.encodeBounded(excessiveNat, 16_777_216), 0);
limit(Wire.encodeBounded(excessiveInt, 16_777_216), 0);
limit(Wire.encodeBounded(-excessiveInt - 1, 16_777_216), 0);
limit(Wire.encodeBounded((7 : Nat8, excessiveNat), 16_777_216), 1);

type Chain = ?(Nat8, Chain);
func chain(n : Nat) : Chain {
  var result : Chain = null;
  var remaining = n;
  while (remaining > 0) { result := ?(8, result); remaining -= 1 };
  result
};
let allowed = chain(63);
let chainBytes = ok(Wire.encodeBounded(allowed, 127));
assert chainBytes == ok(Wire.encode(allowed));
assert ok(Wire.decode<Chain>(chainBytes)) == allowed;
limit(Wire.encodeBounded(allowed, 126), 126);
limit(Wire.encodeBounded(chain(64), 1024), 127);
type Nest = {#next : Nest; #end : [Nat8]};
func nest(n : Nat, values : [Nat8]) : Nest {
  var result : Nest = #end(values);
  var remaining = n;
  while (remaining > 0) { result := #next(result); remaining -= 1 };
  result
};
let emptyDeep = nest(126, []);
assert ok(Wire.encodeBounded(emptyDeep, 128)) == ok(Wire.encode(emptyDeep));
limit(Wire.encodeBounded(nest(126, [1]), 1024), 128);
limit(Wire.encodeBounded(nest(127, []), 1024), 128);

// A scalar-free collection still charges one node per value. Collection
// admission precedes even the length prefix and does not depend on byte space.
let tooMany = Prim.Array_tabulate<Null>(1_000_000, func _ { null });
limit(Wire.encodeBounded(tooMany, 0), 0);
limit(Wire.encodeBounded(tooMany, 3), 0);
limit(Wire.encodeBounded((7 : Nat8, tooMany), 4096), 1);
// The root array and 999,999 zero-byte children use exactly one million nodes.
let most = Prim.Array_tabulate<Null>(999_999, func _ { null });
assert ok(Wire.encodeBounded(most, 3)) == "\bf\84\3d";
limit(Wire.encodeBounded(most, 2), 0);
limit(Wire.encodeBounded((null, most), 3), 0);
Prim.debugPrint("bounded limits: ok");
