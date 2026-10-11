//MOC-FLAG --plugin ../../../../dist/pure-map
//MOC-FLAG -A M0236
import Map "../../motoko/Map";

func compare(a : Nat, b : Nat) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};

// Each consumed count fits, but adding the root to this forged left count would
// exceed the native rank bound. Both evaluators must trap instead of wrapping.
let left : Map.Map<Nat, Nat> = ?(1, 9223372036854775807, 1, 10, null, null);
let tree : Map.Map<Nat, Nat> = ?(2, 1, 2, 20, left, null);
ignore Map.rank(tree, compare, 3);
