//MOC-FLAG --plugin ../../../../dist/mutable-set --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Set "mo:fast/Set";
func compare(a : Nat, b : Nat) : Set.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};
// Instantiate shared structural helpers with unboxed keys before heap keys.
let bits = Set.empty<Bool>();
assert Prim.mset_insert_static<Bool>(bits, false);
assert Prim.mset_insert_static<Bool>(bits, true);
assert not Prim.mset_insert_static<Bool>(bits, false);
assert Prim.mset_delete_static<Bool>(bits, true);
assert Set.toArray(bits) == [false];
let signed = Set.empty<Int>();
for (key in [-18446744073709551617, -1, 0, 18446744073709551617].values()) {
  assert Prim.mset_insert_static<Int>(signed, key);
  assert Prim.mset_contains_static<Int>(signed, key)
};
assert Set.toArray(signed) == [-18446744073709551617, -1, 0, 18446744073709551617];
assert Prim.mset_delete_static<Int>(signed, -18446744073709551617);
let self = Set.empty<Nat>();
var i = 0;
while (i < 2048) {
  // A permutation exercises both ends and the middle of each B-tree node.
  let key = (i * 997) % 2048;
  assert Set.insertNat(self, key);
  assert not Set.insert(self, compare, key);
  i += 1
};
assert Set.size(self) == 2048;
Set.assertValid(self, compare);
i := 0;
while (i < 2048) {
  assert Set.containsNat(self, i);
  assert Set.contains(self, compare, i);
  i += 1
};
let cloned = Set.clone(self);
i := 0;
while (i < 2048) {
  let key = (i * 997) % 2048;
  if (i % 2 == 0) assert Set.deleteNat(self, key)
  else assert Set.delete(self, compare, key);
  assert not Set.deleteNat(self, key);
  if (i % 31 == 0) Set.assertValid(self, compare);
  i += 1
};
assert Set.isEmpty(self);
assert Set.size(cloned) == 2048;
Set.assertValid(self, compare);
Set.assertValid(cloned, compare);

// Keys need not be Shared. Option injection must distinguish absent slots from
// stored null, and callback helpers must work across types in one program.
func nullable(a : ?Nat, b : ?Nat) : Set.Order {
  switch (a, b) {
    case (null, null) #equal;
    case (null, _) #less;
    case (_, null) #greater;
    case (?a, ?b) compare(a, b)
  }
};
let options = Set.empty<?Nat>();
assert Set.insert(options, nullable, null);
i := 0;
while (i < 512) { Set.add(options, nullable, ?i); i += 1 };
Set.assertValid(options, nullable);
assert Set.contains(options, nullable, null);
assert not Set.insert(options, nullable, null);
assert Set.delete(options, nullable, null);
i := 0;
while (i < 512) {
  assert Set.contains(options, nullable, ?i);
  assert Set.delete(options, nullable, ?i);
  i += 1
};
assert Set.isEmpty(options);

type Item = {rank : Nat; var touched : Nat; callback : () -> Nat};
func items(a : Item, b : Item) : Set.Order { compare(a.rank, b.rank) };
var calls = 0;
let first : Item = {rank = 1; var touched = 0; callback = func() : Nat { calls += 1; calls }};
let second : Item = {rank = 1; var touched = 0; callback = first.callback};
let objects = Set.singleton<Item>(first);
assert not Set.insert(objects, items, second);
let retained = switch (Set.min(objects)) { case (?x) x; case null Prim.trap("missing") };
retained.touched += 1;
assert first.touched == 0 and second.touched == 1;
assert retained.callback() == 1;
let copiedObjects = Set.clone(objects);
Set.clear(objects);
assert Set.contains(copiedObjects, items, first);
assert Set.delete(copiedObjects, items, first);
assert Set.isEmpty(copiedObjects);

let words = Set.empty<Text>();
for (word in ["a", "a\00", "é", "🐈"].values()) {
  assert Set.insertText(words, word);
  assert Set.containsText(words, word)
};
Set.removeText(words, "a\00");
assert not Set.containsText(words, "a\00");
let bytes = Set.empty<Blob>();
assert Set.insertBlob(bytes, "");
assert Set.insertBlob(bytes, "\00");
assert Set.insertBlob(bytes, "\ff");
assert Set.deleteBlob(bytes, "\00");
assert Set.toArray(bytes) == ["", "\ff"];
let wide = Set.empty<Nat64>();
Set.addNat64(wide, 18446744073709551615);
assert Set.containsNat64(wide, 18446744073709551615);
Set.removeNat64(wide, 18446744073709551615);
assert Set.isEmpty(wide);

let big = Set.empty<Nat>();
assert Set.insertNat(big, 18446744073709551616);
assert Set.insertNat(big, 1);
assert Set.containsNat(big, 18446744073709551616);
assert Set.toArray(big) == [1, 18446744073709551616];
assert Set.deleteNat(big, 18446744073709551616);
func nested(a : ??Nat, b : ??Nat) : Set.Order {
  switch (a, b) {
    case (null, null) #equal;
    case (null, _) #less;
    case (_, null) #greater;
    case (?a, ?b) nullable(a, b)
  }
};
let nestedSet = Set.empty<??Nat>();
for (key in ([null, ?null, ??0, ??1] : [??Nat]).values()) {
  assert Set.insert(nestedSet, nested, key);
  assert Set.contains(nestedSet, nested, key)
};
assert Set.toArray(nestedSet) == [null, ?null, ??0, ??1];
Set.assertValid(nestedSet, nested);
for (key in ([?null, ??0, null, ??1] : [??Nat]).values()) {
  assert Set.delete(nestedSet, nested, key);
  Set.assertValid(nestedSet, nested)
};
assert Set.isEmpty(nestedSet);
