//MOC-FLAG --plugin ../../../../dist/pure-set --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Set "mo:fast/pure/Set";
func compare(a : Nat, b : Nat) : Set.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};
ignore Set.joinDisjoint(Set.singleton(3), compare, 2, Set.singleton(4));
