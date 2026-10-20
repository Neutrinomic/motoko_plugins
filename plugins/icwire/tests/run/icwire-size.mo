//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

let rejected : Nat = 2_305_843_009_213_693_951;
assert Wire.estimateSize(()) == 0;
assert Wire.estimateSize(null) == 0;
assert Wire.estimateSize((42 : Nat, -65 : Int, "λ" : Text)) == 6;
assert Wire.estimateSize((true, null : ?Nat, ?(128 : Nat))) == 5;
assert Wire.estimateSize([1, 2, 3] : [Nat64]) == 25;
assert Wire.estimateSize([(), (), ()]) == 1;
assert Wire.estimateSize(0.0 / 0.0 : Float) == 8;
assert Wire.estimateSize(1.0 / 0.0 : Float32) == 4;
assert Wire.estimateSize([0.0 / 0.0, 1.0 / 0.0] : [Float]) == 17;
assert Wire.estimateSize(Prim.principalOfBlob("\04")) == 2;
assert Wire.estimateSize({ a = 7 : Nat8; b = "\00\ff" : Blob; c = null : ?Text }) == 5;
type Choice = { #_0_; #_1_ : [Int]; #_2_ : Text };
for (value in ([#_0_, #_1_([-65, -64, -1, 0, 63, 64, 128]), #_2_("λ😀")] : [Choice]).values()) {
  assert Wire.estimateSize(value) == Wire.unwrap(Wire.encode(value)).size();
};
for (value in ([0, 1, 63, 64, 127, 128, 255, 16383, 16384, 2 ** 63 - 1, 2 ** 63, 2 ** 128, 2 ** 512] : [Nat]).values()) {
  assert Wire.estimateSize(value) == Wire.unwrap(Wire.encode(value)).size();
  let signed : Int = value;
  let positiveSize = Wire.unwrap(Wire.encode(signed)).size();
  let negativeSize = Wire.unwrap(Wire.encode(-signed - 1)).size();
  assert Wire.estimateSize(signed) == positiveSize;
  assert Wire.estimateSize(-signed - 1) == negativeSize;
};
type Chain = ?(Nat8, Chain);
func chain(n : Nat) : Chain {
  var value : Chain = null;
  var count = n;
  while (count > 0) { value := ?(8, value); count -= 1 };
  value
};
assert Wire.estimateSize(chain(63)) == 127;
assert Wire.estimateSize(chain(64)) == rejected;
type Nest = { #next : Nest; #end : [Nat8] };
func nest(n : Nat, values : [Nat8]) : Nest {
  var value : Nest = #end(values);
  var count = n;
  while (count > 0) { value := #next(value); count -= 1 };
  value
};
assert Wire.estimateSize(nest(126, [])) == 128;
assert Wire.estimateSize(nest(126, [1])) == rejected;
assert Wire.estimateSize(nest(127, [])) == rejected;
let largestNat : Nat = 2 ** (4096 * 7) - 1;
let signedBoundary : Int = 2 ** (4096 * 7 - 1);
assert Wire.estimateSize(largestNat) == 4096;
assert Wire.estimateSize(largestNat + 1) == rejected;
assert Wire.estimateSize(signedBoundary - 1) == 4096;
assert Wire.estimateSize(-signedBoundary) == 4096;
assert Wire.estimateSize(signedBoundary) == rejected;
assert Wire.estimateSize(-signedBoundary - 1) == rejected;

// Intrinsic aliases specialize and evaluate their argument exactly once.
let codec = { size = Wire.estimateSize };
var visits = 0;
assert codec.size(do { visits += 1; "\00" : Blob }) == 2;
assert visits == 1;
assert Wire.unwrap(#ok 7) == 7;
assert Wire.toOption(Wire.decode<Nat>("\07")) == ?7;
assert Wire.toOption(Wire.decode<Nat>("\80")) == null;
