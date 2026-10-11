//MOC-FLAG --plugin ../../../../dist/pure-set --package fast ../../../../packages/fast/src
//MOC-FLAG --sanity-checks --force-gc -A M0236
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Set "mo:fast/pure/Set";

actor {
  type Cell = {var value : Nat};
  type Item = {key : Nat; bytes : Blob; cell : Cell; read : () -> Nat};
  transient var original : Set.Set<Item> = null;
  transient var updated : Set.Set<Item> = null;
  transient var retained : ?(Set.Set<Item>, ?Item, Set.Set<Item>) = null;
  transient var cursor : Set.Iter<Item> = {next = func() : ?Item { null }};
  transient var stage = 0;
  transient var comparisons = 0;

  func compare(a : Item, b : Item) : Set.Order {
    if (a.key < b.key) #less else if (a.key == b.key) #equal else #greater
  };
  func allocatingCompare(a : Item, b : Item) : Set.Order {
    comparisons += 1;
    ignore Prim.Array_init<Nat>(2048, comparisons);
    assert Set.size(original) == 128;
    compare(a, b)
  };
  func verify(item : Item) {
    assert item.bytes.size() == 1048576;
    assert item.bytes[0] == 23 and item.bytes[1048575] == 23;
    assert item.cell.value == stage;
    assert item.read() == stage;
  };
  public func prepare() : async () {
    let cell : Cell = {var value = 0};
    let bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1048576,
      func(_ : Nat) : Nat8 { 23 }));
    let element = {key = 0; bytes; cell; read = func() : Nat { cell.value }};
    var index = 0;
    while (index < 128) {
      original := Set.add(original, compare, {element with key = index});
      index += 1;
    };
    updated := original;
    cursor := Set.values(original);
    retained := ?Prim.pset_split<Item>(original, compare, {element with key = 64});
  };
  public func change() : async () {
    let first = switch (Set.min(original)) {
      case (?item) item;
      case null Prim.trap("missing set element");
    };
    stage += 1;
    first.cell.value := stage;
    updated := Set.add(updated, allocatingCompare, {first with key = 128 + stage});
    assert comparisons > 0;
    verify(first);
  };
  public func check() : async () {
    assert stage == 2;
    assert Set.size(original) == 128 and Set.size(updated) == 130;
    Set.assertValid(updated, compare);
    var count = 0;
    for (item in cursor) {
      verify(item);
      assert item.key == count;
      count += 1;
    };
    assert count == 128;
    switch (cursor.next()) { case null {}; case _ Prim.trap("iterator not exhausted") };
    switch retained {
      case (?(left, ?middle, right)) {
        assert middle.key == 64;
        assert Set.size(left) == 64 and Set.size(right) == 63;
        verify(middle);
        for (item in Set.values(left)) verify(item);
        for (item in Set.values(right)) verify(item);
      };
      case _ Prim.trap("missing retained split result");
    };
  };
};

//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL ingress change "DIDL\x00\x00"
//CALL ingress check "DIDL\x00\x00"
