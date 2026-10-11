//MOC-FLAG --plugin ../../../../dist/pure-map
//MOC-FLAG -A M0236
import Map "../../motoko/Map";

// The final empty child is at depth 129 and must still trap.
var tree : Map.Map<Nat, Nat> = null;
var key = 129;
while (key > 0) {
  key -= 1;
  tree := ?(1, 129 - key, key, key, null, tree);
};
ignore Map.foldLeft(tree, 0, func(next : Nat, k : Nat, _ : Nat) : Nat {
  assert k == next;
  next + 1
});
