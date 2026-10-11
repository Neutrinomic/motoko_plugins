//MOC-FLAG --plugin ../../../../dist/pure-set --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Set "mo:fast/pure/Set";

func compare(a : Nat, b : Nat) : Set.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};
var set = Set.empty<Nat>();
var i = 0;
while (i < 257) {
  let key = (i * 73) % 257;
  let (next, inserted) = Set.insert(set, compare, key);
  assert inserted;
  set := next;
  Set.assertValid(set, compare);
  i += 1;
};
let original = set;
i := 0;
while (i < 257) {
  assert Set.contains(set, compare, i);
  assert Set.get(set, compare, i) == ?i;
  assert Set.select(set, i) == ?i;
  assert Set.rank(set, compare, i) == i;
  assert Set.indexOf(set, compare, i) == ?i;
  assert not Set.insert(set, compare, i).1;
  i += 1;
};
assert Set.select(set, 257) == null;
assert Set.select(set, 18446744073709551616) == null;
let (lower, middle, upper) = Set.splitLookup(set, compare, 128);
assert middle == ?128;
assert Set.size(lower) == 128 and Set.size(upper) == 128;
assert Set.equal(Set.joinDisjoint(lower, compare, 128, upper), set, compare);
assert Set.size(Set.concatDisjoint(lower, compare, upper)) == 256;
i := 0;
while (i < 257) {
  let key = (i * 91) % 257;
  let (next, removed) = Set.delete(set, compare, key);
  assert removed;
  set := next;
  assert not Set.delete(set, compare, key).1;
  Set.assertValid(set, compare);
  i += 1;
};
assert Set.isEmpty(set);
assert Set.size(original) == 257;

// Nullable keys require a real option layer around a stored null, in both
// concrete primitive calls and generic wrappers.
func optional(a : ?Nat, b : ?Nat) : Set.Order {
  switch (a, b) {
    case (null, null) #equal;
    case (null, _) #less;
    case (_, null) #greater;
    case (?a, ?b) compare(a, b);
  }
};
let optionSet = Set.fromArray<?Nat>([?2, null, ?1, null], optional);
assert Set.size(optionSet) == 3;
assert Set.get(optionSet, optional, null) == ?null;
assert Set.select(optionSet, 0) == ?null;
assert Set.splitLookup(optionSet, optional, null).1 == ?null;
assert Prim.pset_get<?Nat>(optionSet, optional, null) == ?null;
assert Prim.pset_select<?Nat>(optionSet, 0) == ?null;
assert Prim.pset_split<?Nat>(optionSet, optional, null).1 == ?null;
assert Set.get(optionSet, optional, ?3) == null;
assert Set.toArray(Set.remove(optionSet, optional, null)) == [?1, ?2];

// Reference-bearing elements survive copy-on-write and never get cloned.
type Item = {key : Nat; var payload : Nat};
func itemCompare(a : Item, b : Item) : Set.Order { compare(a.key, b.key) };
let first : Item = {key = 1; var payload = 10};
let equal : Item = {key = 1; var payload = 20};
let items = Set.singleton(first);
let more = Set.add(items, itemCompare, {key = 2; var payload = 30});
let duplicate = Set.add(more, itemCompare, equal);
first.payload := 100;
switch (Set.get(duplicate, itemCompare, equal)) {
  case (?stored) { assert stored.payload == 100 };
  case null { assert false };
};
switch (Set.get(items, itemCompare, equal)) {
  case (?stored) { assert stored.payload == 100 };
  case null { assert false };
};
assert Set.size(items) == 1 and Set.size(more) == 2;

// Static scalar kernels coexist with generic nullable/reference kernels.
let max64 : Nat64 = 18446744073709551615;
let words = Set.addNat64(Set.addNat64(Set.empty<Nat64>(), max64), 0);
assert Set.toArray(words) == [(0 : Nat64), max64];
assert Set.getNat64(words, max64) == ?max64;
assert Set.deleteNat64(words, max64).1;
let huge : Nat = 18446744073709551616000;
let naturals = Set.addNat(Set.addNat(null, huge), 0);
assert Set.toArray(naturals) == [0, huge];
assert Set.containsNat(naturals, huge);
let texts = Set.addText(Set.addText(null, "☃"), "💫");
assert Set.toArray(texts) == ["☃", "💫"];
assert Set.getText(texts, "💫") == ?"💫";
let bytes = Set.addBlob(Set.addBlob(null, "\ff"), "\00\ff");
assert Set.toArray(bytes) == ["\00\ff", "\ff"];
assert Set.getBlob(bytes, "\ff") == ?"\ff";

module Unsigned { public type Key = Nat64 };
module Signed { public type Key = Int64 };
let unsigned = Prim.pset_add_static<Unsigned.Key>(null, max64);
let signed = Prim.pset_add_static<Signed.Key>(null, -9223372036854775808);
assert Prim.pset_get_static<Unsigned.Key>(unsigned, max64) == ?max64;
assert Prim.pset_get_static<Signed.Key>(signed, -9223372036854775808) == ?(-9223372036854775808);
