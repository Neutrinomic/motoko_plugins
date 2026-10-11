//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Map "mo:fast/pure/Map";

// Deliberately skewed data reaches the last permitted empty-child depth.
// The fold guard depends on actual traversal depth, not stored height.
var tree : Map.Map<Nat, Nat> = null;
var key = 128;
while (key > 0) {
  key -= 1;
  tree := ?(1, 128 - key, key, key * 3, null, tree);
};
let state = {var calls = 0};
let result = Map.foldLeft(tree, state, func(acc : {var calls : Nat}, k : Nat, v : Nat) : {var calls : Nat} {
  assert k == acc.calls and v == k * 3;
  acc.calls += 1;
  acc
});
assert result.calls == 128 and state.calls == 128;
assert Map.foldRight(tree, 128, func(k : Nat, v : Nat, next : Nat) : Nat {
  assert k + 1 == next and v == k * 3;
  k
}) == 0;
assert Map.foldLeft<Nat, Nat, Nat>(null, 7, func(_, _, _) { assert false; 0 }) == 7;
assert Map.foldRight<Nat, Nat, Nat>(null, 7, func(_, _, _) { assert false; 0 }) == 7;
