//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "mo:fast/pure/Map";

func compare(a : Nat, b : Nat) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};

// The native search checks depth before testing the node. A hit at depth 127
// is accepted, as is a miss into null at depth 127. The trap fixture covers 128.
var chain : Map.Map<Nat, Nat> = null;
var remaining = 128;
while (remaining > 0) {
  remaining -= 1;
  chain := ?(1, 1, remaining, remaining + 100, null, chain);
};
var calls = 0;
func checkedCompare(a : Nat, b : Nat) : Map.Order {
  assert a == 127 and b == calls;
  calls += 1;
  // Reenter search and allocate while the outer cursor remains live.
  assert Map.getNat(Map.singleton(5, 50), 5) == ?50;
  ignore Prim.Array_init<Nat>(64, calls);
  compare(a, b)
};
assert Map.get(chain, checkedCompare, 127) == ?227;
assert calls == 128;
assert Map.getNat(chain, 127) == ?227;
assert Map.getEntry(chain, compare, 127) == ?(127, 227);
assert Map.containsKey(chain, compare, 127);
switch chain {
  case null assert false;
  case (?node) {
    assert Map.get(node.5, compare, 128) == null;
    assert Map.getNat(node.5, 128) == null;
  }
};
assert Map.get(Map.empty<Nat, Nat>(), compare, 0) == null;

// Comparator-equal object keys retain the last original key and value objects
// after stable merging. Changing their non-ordering cells remains observable.
type Key = {order : Nat; cell : {var revision : Nat}};
type Payload = {cell : {var revision : Nat}; read : () -> Nat};
let input = Prim.Array_tabulate<(Key, Payload)>(257, func(i : Nat) : (Key, Payload) {
  let cell = {var revision = i};
  ({order = (i * 11) % 17; cell}, {cell; read = func() : Nat {cell.revision}})
});
func keyCompare(a : Key, b : Key) : Map.Order { compare(a.order, b.order) };
let arrayMap = Map.fromArray(input, keyCompare);
let iterMap = Map.fromIter(input.values(), keyCompare);
for (tree in [arrayMap, iterMap].values()) {
  Map.assertValid(tree, keyCompare);
  assert Map.size(tree) == 17;
  for ((key, value) in Map.entries(tree)) {
    var last = 0;
    var i = 0;
    while (i < input.size()) {
      if (input[i].0.order == key.order) last := i;
      i += 1;
    };
    assert key.cell.revision == last;
    assert value.read() == last;
    input[last].0.cell.revision := last + 1000;
    assert key.cell.revision == last + 1000;
    assert value.cell.revision == last + 1000;
    assert value.read() == last + 1000;
    input[last].0.cell.revision := last;
  }
};
