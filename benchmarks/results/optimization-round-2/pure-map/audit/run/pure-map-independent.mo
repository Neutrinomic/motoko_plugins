//MOC-FLAG --plugin ../../../../../../dist/pure-map
//MOC-FLAG --sanity-checks -A M0236
import Prim "mo:⛔";
import Map "../../../../../../plugins/pure-map/motoko/Map";

type Key = { order : Nat; serial : Nat; cell : {var revision : Nat} };
type Payload = { read : () -> Nat };
func compare(a : Nat, b : Nat) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};
func keyCompare(a : Key, b : Key) : Map.Order { compare(a.order, b.order) };

// Independently derive the winning original object for every equivalence class.
// Sizes straddle all merge widths through 64, including incomplete final runs.
var n = 0;
while (n <= 65) {
  var pattern = 0;
  while (pattern < 6) {
    let input = Prim.Array_tabulate<(Key, Payload)>(n, func(i : Nat) : (Key, Payload) {
      let order = switch pattern {
        case 0 i;
        case 1 (Prim.abs(n - i));
        case 2 0;
        case 3 ((i * 13) % 7);
        case 4 (i / 3);
        case _ (Prim.abs(n - i) / 3);
      };
      let cell = {var revision = i};
      ({order; serial = i; cell}, {read = func() : Nat {cell.revision}})
    });
    for (tree in [Map.fromArray(input, keyCompare), Map.fromIter(input.values(), keyCompare)].values()) {
      Map.assertValid(tree, keyCompare);
      var actualCount = 0;
      var previous : ?Nat = null;
      for ((key, payload) in Map.entries(tree)) {
        switch previous {case null {}; case (?p) assert p < key.order};
        previous := ?key.order;
        var expected : ?Nat = null;
        var j = 0;
        while (j < n) {
          if (input[j].0.order == key.order) expected := ?j;
          j += 1;
        };
        let last = switch expected {case (?i) i; case null {assert false; 0}};
        assert key.serial == last;
        input[last].0.cell.revision := n + 100;
        assert key.cell.revision == n + 100;
        assert payload.read() == n + 100;
        input[last].0.cell.revision := last;
        actualCount += 1;
      };
      assert actualCount == Map.size(tree);
      // Calculate the expected native search callback sequence from the node
      // representation, including both directions and every absent interval.
      var wanted = 0;
      while (wanted <= n + 1) {
        var cursor = tree;
        var seen = 0;
        let needle : Key = {order = wanted; serial = 9999; cell = {var revision = 0}};
        func checkCompare(a : Key, b : Key) : Map.Order {
          let node = switch cursor {case (?node) node; case null Prim.trap("unexpected search comparison")};
          assert a.order == wanted and b.serial == node.2.serial;
          let order = keyCompare(a, b);
          cursor := if (order == #less) node.4 else if (order == #greater) node.5 else null;
          seen += 1;
          order
        };
        let found = Map.getEntry(tree, checkCompare, needle);
        var expected : ?Nat = null;
        var j = 0;
        while (j < n) {if (input[j].0.order == wanted) expected := ?j; j += 1};
        switch (found, expected) {
          case (null, null) {};
          case (?(key, value), ?i) {assert key.serial == i and value.read() == i};
          case _ assert false;
        };
        if (n == 0) assert seen == 0 else assert seen > 0;
        switch cursor {case null {}; case _ assert false};
        wanted += 1;
      };
    };
    pattern += 1;
  };
  n += 1;
};

// Leftward static search has the same depth boundary and optional-value result
// shape as the generic path; null payloads must remain present as ?null.
var chain : Map.Map<Nat, ?Nat> = null;
var key = 0;
while (key < 128) {chain := ?(1, 1, key, null, chain, null); key += 1};
assert Map.getNat(chain, 0) == ?null;
assert Map.get(chain, compare, 0) == ?null;
assert Map.getNat(chain, 129) == null;
