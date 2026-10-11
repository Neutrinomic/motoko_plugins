//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "mo:fast/Map";
type Key = {order : Nat; var tag : Nat};
type Value = {var count : Nat; callback : () -> Nat};
func cmp(a : Key, b : Key) : Map.Order { if (a.order < b.order) #less else if (a.order == b.order) #equal else #greater };
let oldKey = {order = 1; var tag = 10};
let newKey = {order = 1; var tag = 20};
var closed = 0;
let payload = {var count = 0; callback = func() : Nat { closed += 1; closed }};
let self = Map.singleton<Key, ?Value>(oldKey, null);
switch (Map.get(self, cmp, oldKey)) { case (?null) {}; case _ { assert false } };
assert not Map.insert(self, cmp, newKey, ?payload);
let storedKey = switch (Map.getEntry(self, cmp, oldKey)) { case (?(key, ?value)) { value.count += 1; key }; case _ { assert false; oldKey } };
storedKey.tag := 30;
assert newKey.tag == 30 and oldKey.tag == 10;
assert payload.count == 1;
let copied = Map.clone(self);
Map.clear(self);
let retained = switch (Map.get(copied, cmp, newKey)) { case (??value) value; case _ { assert false; payload } };
retained.count += 1;
assert payload.count == 2;
assert retained.callback() == 1;
assert payload.callback() == 2;
let other = Map.empty<Nat, Nat>();
var comparisons = 0;
// Each Order branch consumes one callback result, preserving its effects and
// argument order while captured managed values survive allocation and reentry.
for (probe in [0, 1, 2].values()) {
  let before = comparisons;
  func reentrant(a : Key, b : Key) : Map.Order {
    assert a.order == probe and b.order == newKey.order;
    comparisons += 1;
    assert comparisons == before + 1;
    assert Map.size(copied) == 1;
    assert Map.containsKey(copied, cmp, newKey);
    Map.addNat(other, comparisons, comparisons);
    ignore Prim.Array_init<Nat>(64, comparisons);
    payload.count += 1;
    cmp(a, b)
  };
  let key : Key = {order = probe; var tag = 0};
  switch (Map.get(copied, reentrant, key)) {
    case (??value) {
      assert probe == 1;
      value.count += 1;
      assert value.count == payload.count;
      assert value.callback() == 3;
    };
    case null { assert probe != 1 };
    case (?null) { assert false };
  };
  assert comparisons == before + 1;
};
assert comparisons == 3;
assert Map.size(other) == comparisons;
Map.forEach(copied, func(key : Key, value : ?Value) {
  assert Map.containsKey(copied, cmp, key);
  switch value { case (?value) { value.count += 1 }; case null { assert false } };
  Map.clear(other);
});
assert Map.isEmpty(other);
assert Map.size(copied) == 1;
Map.assertValid(copied, cmp);
let nats = Map.empty<Nat64, ?Nat>();
Map.addNat64<?Nat>(nats, 0, null);
Map.addNat64<?Nat>(nats, 18446744073709551615, ?42);
assert Map.getNat64<?Nat>(nats, 0) == ?null;
assert Map.replaceNat64<?Nat>(nats, 18446744073709551615, ?43) == ??42;
Map.removeNat64<?Nat>(nats, 0);
assert Map.getNat64<?Nat>(nats, 0) == null;
let texts = Map.empty<Text, Nat>();
Map.addText(texts, "a", 1);
Map.addText(texts, "a\00", 2);
Map.addText(texts, "é", 3);
assert Map.getText(texts, "a\00") == ?2;
assert Map.replaceText(texts, "é", 4) == ?3;
Map.removeText(texts, "a");
assert Map.getText(texts, "a") == null;
let blobs = Map.empty<Blob, Nat>();
Map.addBlob<Nat>(blobs, "\00\ff", 1);
Map.addBlob<Nat>(blobs, "\00", 2);
assert Map.getBlob<Nat>(blobs, "\00\ff") == ?1;
assert Map.replaceBlob<Nat>(blobs, "\00", 3) == ?2;
Map.removeBlob<Nat>(blobs, "\00\ff");
assert Map.getBlob<Nat>(blobs, "\00\ff") == null;
