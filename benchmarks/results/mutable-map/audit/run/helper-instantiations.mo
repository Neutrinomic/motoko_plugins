//MOC-FLAG --plugin ../../../../../dist/mutable-map
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "../../../../../plugins/mutable-map/motoko/Map";
type Payload = {var n : Nat; read : () -> Nat};
type Key = ?{rank : Int; var identity : Nat};
func cmp(a : Key, b : Key) : Map.Order {
  switch (a, b) {
    case (null, null) #equal; case (null, _) #less; case (_, null) #greater;
    case (?a, ?b) { if (a.rank < b.rank) #less else if (a.rank == b.rank) #equal else #greater }
  }
};
var captured = 0;
let cell : Payload = {var n = 0; read = func() : Nat { captured += 1; captured }};
let map = Map.empty<Key, ??Payload>();
Map.add(map, cmp, null, null);
var i = 0;
while (i < 1200) {
  let key = ?{rank = i; var identity = i};
  let value : ??Payload = if (i % 3 == 0) null else if (i % 3 == 1) ?null else ??cell;
  Map.add(map, cmp, key, value);
  i += 1;
};
Map.assertValid(map, cmp);
switch (Map.get(map, cmp, null)) { case (?null) {}; case _ { assert false } };
let newKey = {rank = 5; var identity = 9000};
let old = Map.swap(map, cmp, ?newKey, ??cell);
switch old { case (???payload) { payload.n += 1; assert payload.read() == 1 }; case _ { assert false } };
switch (Map.getEntry(map, cmp, ?{rank = 5; var identity = 0})) {
  case (?(?stored, ??payload)) { stored.identity += 1; payload.n += 1 };
  case _ { assert false };
};
assert newKey.identity == 9001 and cell.n == 2;
let copied = Map.clone(map);
i := 0;
while (i < 1200) {
  let key = ?{rank = (i * 997 % 1200); var identity = 0};
  assert Map.delete(map, cmp, key);
  if (i % 29 == 0) Map.assertValid(map, cmp);
  i += 1;
};
switch (Map.take(map, cmp, null)) { case (?null) {}; case _ { assert false } };
Map.assertValid(map, cmp);
Map.assertValid(copied, cmp);
assert Map.size(copied) == 1201;
switch (Map.get(copied, cmp, ?newKey)) { case (???payload) { payload.n += 1; assert payload.read() == 2 }; case _ { assert false } };
assert cell.n == 3;

// Shared native helpers are used by every instantiation in this module.
// Scalar extremes exercise tagged, boxed and arbitrary-precision keys.
func numeric<K>(keys : [K], compare : (K, K) -> Map.Order) {
  let t = Map.empty<K, Float>();
  for (key in keys.values()) Map.add(t, compare, key, 3.5);
  for (key in keys.values()) { assert Map.get(t, compare, key) == ?3.5; assert Map.take(t, compare, key) == ?3.5 };
  assert Map.isEmpty(t);
};
numeric<Nat64>([0, 18446744073709551615, 9223372036854775808], func(a, b) { if (a < b) #less else if (a == b) #equal else #greater });
numeric<Int>([-99999999999999999999999999999999999, 0, 99999999999999999999999999999999999], func(a, b) { if (a < b) #less else if (a == b) #equal else #greater });
let bytes = Map.empty<Blob, () -> Nat>();
for (key in [("" : Blob), ("\00" : Blob), ("\ff" : Blob), ("\00\ff" : Blob)].values()) Map.addBlob(bytes, key, cell.read);
switch (Map.getBlob(bytes, ("\00\ff" : Blob))) { case (?f) { assert f() == 3 }; case null { assert false } };
let signed = Map.empty<Int64, ?Null>();
for (key in ([-9223372036854775808, 0, 9223372036854775807] : [Int64]).values()) Prim.mmap_add_static<Int64, ?Null>(signed, key, ?null);
assert Prim.mmap_get_static<Int64, ?Null>(signed, -9223372036854775808) == ??null;
assert Prim.mmap_take_static<Int64, ?Null>(signed, 9223372036854775807) == ??null;
let small = Map.empty<Int32, Bool>();
for (key in ([-2147483648, -1, 0, 2147483647] : [Int32]).values()) Prim.mmap_add_static<Int32, Bool>(small, key, true);
assert Prim.mmap_get_static<Int32, Bool>(small, -2147483648) == ?true;
assert Map.toArray(small) == [(-2147483648, true), (-1, true), (0, true), (2147483647, true)];
Prim.debugPrint("audit: generic helper sharing, nested options, key/payload aliases, closures and scalar extremes passed");
