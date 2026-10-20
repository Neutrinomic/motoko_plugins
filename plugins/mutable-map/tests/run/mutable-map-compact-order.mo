//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src
//MOC-FLAG --package core $MOTOKO_CORE --sanity-checks -A M0236
import Prim "mo:⛔";
import Map "mo:fast/Map";
import Core "mo:core/Map";
import Nat "mo:core/Nat";
import Int "mo:core/Int";

// Independent Core tree checks keys around both compact boundaries, mixed
// boxed/compact operands, equal values and null payloads in searches and updates.
do {
  type Key = Nat;
  let compare = Nat.compare;
  let actual = Map.empty<Key, ?Nat>();
  let expected = Core.empty<Key, ?Nat>();
  let edges : [Key] = [
    0, 1, 2 ** 61 - 1, 2 ** 61, 2 ** 61 + 1,
    2 ** 62 - 1, 2 ** 62, 2 ** 127
  ];
  let keys = Prim.Array_tabulate<Key>(256 + edges.size(), func(index) {
    if (index < edges.size()) return edges[index];
    let i = Prim.abs((index : Int) - edges.size());
    switch (i % 4) {
      case 0 i;
      case 1 (2 ** 61 - i);
      case 2 (2 ** 61 + i);
      case _ (2 ** 127 + i);
    }
  });
  func check() {
    Map.assertValid(actual, compare);
    assert Map.size(actual) == Core.size(expected);
    assert Map.toArray(actual) == Core.toArray(expected);
  };
  var i = 0;
  while (i < keys.size()) {
    let key = keys[i * 173 % keys.size()];
    let value = if (i % 7 == 0) null else ?i;
    assert Prim.mmap_insert_static<Key, ?Nat>(actual, key, value) ==
      Core.insert(expected, compare, key, value);
    i += 1;
  };
  check();
  i := 0;
  while (i < keys.size()) {
    let key = keys[i];
    assert Prim.mmap_get_static<Key, ?Nat>(actual, key) ==
      Core.get(expected, compare, key);
    assert Prim.mmap_swap_static<Key, ?Nat>(actual, key, ?i) ==
      Core.swap(expected, compare, key, ?i);
    assert Prim.mmap_replace_static<Key, ?Nat>(actual, key, null) ==
      Core.replace(expected, compare, key, null);
    i += 1;
  };
  check();
  i := 0;
  while (i < keys.size()) {
    let key = keys[i * 181 % keys.size()];
    if (i % 2 == 0) {
      assert Prim.mmap_delete_static<Key, ?Nat>(actual, key) ==
        Core.delete(expected, compare, key);
    } else {
      assert Prim.mmap_take_static<Key, ?Nat>(actual, key) ==
        Core.take(expected, compare, key);
    };
    assert not Prim.mmap_delete_static<Key, ?Nat>(actual, key);
    if (i % 31 == 0) check();
    i += 1;
  };
  check();
  assert Map.isEmpty(actual);
};
do {
  type Key = Int;
  let compare = Int.compare;
  let actual = Map.empty<Key, ?Nat>();
  let expected = Core.empty<Key, ?Nat>();
  let edges : [Key] = [
    -(2 ** 127 : Int), -(2 ** 62 : Int), -(2 ** 61 : Int) - 1,
    -(2 ** 61 : Int), -(2 ** 61 : Int) + 1, -1, 0, 1,
    2 ** 61 - 1, 2 ** 61, 2 ** 61 + 1, 2 ** 127
  ];
  let keys = Prim.Array_tabulate<Key>(256 + edges.size(), func(index) {
    if (index < edges.size()) return edges[index];
    let i = Prim.abs((index : Int) - edges.size());
    switch (i % 8) {
      case 0 (i : Int);
      case 1 (-(i : Int));
      case 2 (2 ** 61 - i);
      case 3 (-(2 ** 61 : Int) + i);
      case 4 (2 ** 61 + i);
      case 5 (-(2 ** 61 : Int) - i);
      case 6 (2 ** 127 + i);
      case _ (-(2 ** 127 : Int) - i);
    }
  });
  func check() {
    Map.assertValid(actual, compare);
    assert Map.size(actual) == Core.size(expected);
    assert Map.toArray(actual) == Core.toArray(expected);
  };
  var i = 0;
  while (i < keys.size()) {
    let key = keys[i * 173 % keys.size()];
    let value = if (i % 7 == 0) null else ?i;
    assert Prim.mmap_insert_static<Key, ?Nat>(actual, key, value) ==
      Core.insert(expected, compare, key, value);
    i += 1;
  };
  check();
  i := 0;
  while (i < keys.size()) {
    let key = keys[i];
    assert Prim.mmap_get_static<Key, ?Nat>(actual, key) ==
      Core.get(expected, compare, key);
    assert Prim.mmap_swap_static<Key, ?Nat>(actual, key, ?i) ==
      Core.swap(expected, compare, key, ?i);
    assert Prim.mmap_replace_static<Key, ?Nat>(actual, key, null) ==
      Core.replace(expected, compare, key, null);
    i += 1;
  };
  check();
  i := 0;
  while (i < keys.size()) {
    let key = keys[i * 181 % keys.size()];
    if (i % 2 == 0) {
      assert Prim.mmap_delete_static<Key, ?Nat>(actual, key) ==
        Core.delete(expected, compare, key);
    } else {
      assert Prim.mmap_take_static<Key, ?Nat>(actual, key) ==
        Core.take(expected, compare, key);
    };
    assert not Prim.mmap_delete_static<Key, ?Nat>(actual, key);
    if (i % 31 == 0) check();
    i += 1;
  };
  check();
  assert Map.isEmpty(actual);
};
