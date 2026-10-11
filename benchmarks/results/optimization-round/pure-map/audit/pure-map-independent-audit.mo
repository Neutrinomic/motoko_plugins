//MOC-FLAG --plugin /srv/shared/code/motoko_experiments/optimization-round/pure-map/dist/pure-map
//MOC-FLAG --package candidate /srv/shared/code/motoko_experiments/optimization-round/pure-map/plugins/pure-map/motoko
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "mo:candidate/Map";
func cmp(a : Nat, b : Nat) : Map.Order { if (a < b) #less else if (a == b) #equal else #greater };
var n = 0;
while (n <= 24) {
  var tree = Map.empty<Nat, Nat>();
  var i = 0;
  while (i < n) { tree := Map.add(tree, cmp, (i * 17) % 29, i); i += 1 };
  // 12 is the inverse of 17 modulo 29: derive expected bindings independently.
  let ascending = Prim.Array_tabulate<(Nat, Nat)>(n, func(rank) {
    var key = 0;
    var seen = 0;
    loop {
      let value = (key * 12) % 29;
      if (value < n) {
        if (seen == rank) return (key, value);
        seen += 1;
      };
      key += 1;
    }
  });
  assert Map.toArray(tree) == ascending;
  Map.assertValid(tree, cmp);
  var start = 0;
  while (start <= n) {
    var end = start;
    while (end <= n) {
      for (reverse in [false, true].values()) {
        let view = { root = tree; start; end; reverse };
        let cursor = Map.replay(view);
        var offset = 0;
        while (offset < (end - start : Nat)) {
          let rank : Nat = if (reverse) (end - offset - 1 : Nat) else start + offset;
          assert cursor.next() == ?ascending[rank];
          offset += 1;
        };
        assert cursor.next() == null;
        assert cursor.next() == null;
        let again = Map.replay(cursor.snapshot);
        assert again.next() == (if (start == end) null else ?ascending[if (reverse) end - 1 else start]);
      };
      end += 1;
    };
    start += 1;
  };
  n += 1;
};
type Key = { rank : Nat; stamp : Nat };
type Value = { cell : { var n : Nat }; read : () -> Nat };
func compareKey(a : Key, b : Key) : Map.Order { cmp(a.rank, b.rank) };
let values = Prim.Array_tabulate<(Key, Value)>(137, func(i) {
  let cell = { var n = i };
  ({ rank = (i * 19) % 11; stamp = i }, { cell; read = func() : Nat { cell.n } })
});
let duplicates = Map.fromArray(values, compareKey);
Map.assertValid(duplicates, compareKey);
for ((key, value) in Map.entries(duplicates)) {
  var last = 0;
  var i = 0;
  while (i < values.size()) {
    if (values[i].0.rank == key.rank) last := i;
    i += 1;
  };
  assert key.stamp == last;
  values[last].1.cell.n += 1000;
  assert value.cell.n == last + 1000;
  assert value.read() == last + 1000;
};
let identity = Map.foldLeft<Key, Value, Nat>(duplicates, 0, func(count, _, value) {
  value.cell.n += 1;
  assert value.read() == value.cell.n;
  count + 1
});
assert identity == 11;
