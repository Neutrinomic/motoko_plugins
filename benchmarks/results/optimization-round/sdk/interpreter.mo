import Prim "mo:⛔";
type Item = {
  value : Nat; children : [(Text, ?Nat)]; callback : Nat -> Nat
};
let identity = Prim.fixtureIdentity;
func generic<T>(value : T) : T { identity<T>(value) };
var item : Item = {
  value = 1; children = [("a", ?2), ("b", null)]; callback = func(n) { n + 1 }
};
var index = 0;
while (index < 1000000) {
  item := generic<Item>(item);
  index += 1;
};
assert item.value == 1;
assert item.children == [("a", ?2), ("b", null)];
assert item.callback(1) == 2;
