//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Map "mo:fast/pure/Map";

func compare(a : Nat, b : Nat) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};

// An application can forge an unbalanced chain. Lookup must stop deterministically
// before exhausting the native or interpreter stack, without trusting height.
var tree : Map.Map<Nat, Nat> = null;
var remaining = 129;
while (remaining > 0) {
  remaining -= 1;
  tree := ?(1, 1, remaining, remaining, null, tree);
};
ignore Map.get(tree, compare, 200);
