//MOC-FLAG --plugin ../../../../dist/pure-map --package fast ../../../../packages/fast/src
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "mo:fast/pure/Map";

func compare(a : Nat, b : Nat) : Map.Order {
  if (a < b) #less else if (a == b) #equal else #greater
};

// Distinct key aliases with the same spelling must not share a scalar kernel.
module Unsigned { public type Key = Nat64 };
module Signed { public type Key = Int64 };
module Letters { public type Key = Text };
module Bytes { public type Key = Blob };
let unsigned0 = Prim.pmap_add_static<Unsigned.Key, Nat>(null, 0, 1);
let unsigned1 = Prim.pmap_add_static<Unsigned.Key, Nat>(unsigned0, 18446744073709551615, 2);
let signed0 = Prim.pmap_add_static<Signed.Key, Nat>(null, -9223372036854775808, 3);
let signed1 = Prim.pmap_add_static<Signed.Key, Nat>(signed0, 9223372036854775807, 4);
let text0 = Prim.pmap_add_static<Letters.Key, Nat>(null, "a☃", 5);
let text1 = Prim.pmap_add_static<Letters.Key, Nat>(text0, "a💫", 6);
let blob0 = Prim.pmap_add_static<Bytes.Key, Nat>(null, "\00\ff", 7);
let blob1 = Prim.pmap_add_static<Bytes.Key, Nat>(blob0, "\ff", 8);
assert Prim.pmap_get_static<Unsigned.Key, Nat>(unsigned1, 18446744073709551615) == ?2;
assert Prim.pmap_get_static<Signed.Key, Nat>(signed1, -9223372036854775808) == ?3;
assert Prim.pmap_get_static<Letters.Key, Nat>(text1, "a💫") == ?6;
assert Prim.pmap_get_static<Bytes.Key, Nat>(blob1, "\ff") == ?8;
assert Map.entries(unsigned1).next() == ?(0, 1);
assert Map.entries(signed1).next() == ?(-9223372036854775808, 3);
assert Map.entries(text1).next() == ?("a☃", 5);
assert Map.entries(blob1).next() == ?("\00\ff", 7);

// The alter kernel shares code within each nullable/plain payload layout.
// Instantiate every nullable shape together with ordinary values in one module.
let plain = Map.add(Map.empty<Nat, Nat>(), compare, 1, 10);
let nextPlain = Map.alter(plain, compare, 1, func (old : ?Nat) : ?Nat {
  assert old == ?10;
  ?11
});
assert Map.get(plain, compare, 1) == ?10;
assert Map.get(nextPlain, compare, 1) == ?11;

let nulls = Map.add(Map.empty<Nat, Null>(), compare, 1, null);
let nextNulls = Map.alter(nulls, compare, 1, func (old : ?Null) : ?Null {
  assert old == ?null;
  ?null
});
assert Map.get(nextNulls, compare, 1) == ?null;
let noNulls = Map.alter(nextNulls, compare, 1, func (old : ?Null) : ?Null {
  assert old == ?null;
  null
});
assert Map.get(noNulls, compare, 1) == null;
assert Map.get(nulls, compare, 1) == ?null;

let options = Map.add(Map.empty<Nat, ?Nat>(), compare, 1, null);
let nextOptions = Map.alter(options, compare, 1, func (old : ??Nat) : ??Nat {
  assert old == ?null;
  ??17
});
assert Map.get(options, compare, 1) == ?null;
assert Map.get(nextOptions, compare, 1) == ??17;
let nested = Map.add(Map.empty<Nat, ??Nat>(), compare, 1, ?null);
let nextNested = Map.alter(nested, compare, 1, func (old : ???Nat) : ???Nat {
  assert old == ??null;
  ???23
});
assert Map.get(nested, compare, 1) == ??null;
assert Map.get(nextNested, compare, 1) == ???23;

let anys = Map.add(Map.empty<Nat, Any>(), compare, 1, null);
var anyCalls = 0;
let nextAnys = Map.alter(anys, compare, 1, func (old : ?Any) : ?Any {
  switch old { case null assert false; case (?_) anyCalls += 1 };
  ?("opaque payload" : Any)
});
assert anyCalls == 1;
switch (Map.get(nextAnys, compare, 1)) {
  case null assert false;
  case (?_) {};
};

let cell = { var number = 0 };
type Payload = {cell : {var number : Nat}; read : () -> Nat};
let payload : Payload = { cell; read = func () : Nat { cell.number } };
let first = Map.add(Map.empty<Nat, Payload>(), compare, 1, payload);
let second = Map.alter(first, compare, 1, func (old : ?Payload) : ?Payload {
  switch old {
    case null Prim.trap("missing payload");
    case (?value) {
      value.cell.number += 1;
      assert Map.get(nextNested, compare, 1) == ???23;
      ?value
    };
  }
});
for (tree in [first, second].values()) {
  switch (Map.get(tree, compare, 1)) {
    case null assert false;
    case (?value) assert value.read() == 1;
  }
};

// Generic code uses the dynamic nullable layout even when called with a plain
// value. Its specialization must coexist with direct concrete instantiations.
func replace<T>(tree : Map.Map<Nat, T>, value : T) : Map.Map<Nat, T> {
  Map.alter(tree, compare, 1, func (_old : ?T) : ?T { ?value })
};
assert Map.get(replace(plain, 99), compare, 1) == ?99;
assert Map.get(replace(nested, null), compare, 1) == ?null;
