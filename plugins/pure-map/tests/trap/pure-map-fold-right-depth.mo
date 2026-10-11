//MOC-FLAG --plugin ../../../../dist/pure-map
//MOC-FLAG -A M0236
import Map "../../motoko/Map";

// The final empty child is at depth 129 and must still trap.
var tree : Map.Map<Nat, Nat> = null;
var key = 0;
while (key < 129) {
  tree := ?(1, key + 1, key, key, tree, null);
  key += 1;
};
ignore Map.foldRight(tree, 129, func(k : Nat, _ : Nat, next : Nat) : Nat {
  assert k + 1 == next;
  k
});
