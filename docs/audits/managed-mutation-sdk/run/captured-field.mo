//MOC-FLAG --plugin /srv/shared/code/motoko_experiments/mutable-map-round/sdk/_build/compute-plugin-tests/mutation
//MOC-FLAG --sanity-checks
import Prim "mo:⛔";

// A public variable's MutBox is also captured by methods, not only by records.
let object_ = object {
  public var value : [var Nat] = [var 1];
  public func read() : [var Nat] { value };
  public func change(next : [var Nat]) { value := next };
};
let narrow : { var value : [var Nat] } = object_;
let next = [var 2];
Prim.fixtureMutWrite<[var Nat]>(narrow, next);
assert object_.read()[0] == 2;
object_.read()[0] := 33;
assert next[0] == 33;
object_.change([var 44]);
assert Prim.fixtureMutRead<[var Nat]>(narrow)[0] == 44;

// The selected container is evaluated once even if the RHS changes its holder.
let a = [var 1]; let b = [var 2]; var selected = a;
Prim.fixtureMutOperands<Nat>(func() { selected }, func() { 0 }, func() {
  selected := b;
  77
});
assert a[0] == 77 and b[0] == 2 and selected[0] == 2;
let first = Prim.fixtureMutRecord<Nat>(1);
let second = Prim.fixtureMutRecord<Nat>(2);
var chosen = first;
Prim.fixtureMutFieldOperands<Nat>(func() { chosen }, func() {
  chosen := second;
  88
});
assert first.value == 88 and second.value == 2;

// Mutating a record's optional payload preserves recursive aliases.
type Node = { var value : ?Node; var spare : ?Node; marker : Nat };
let x : Node = Prim.fixtureMutRecord<?Node>(null);
let y : Node = Prim.fixtureMutRecord<?Node>(?x);
Prim.fixtureMutWrite<?Node>(x, ?y);
switch (x.value) {
  case (?child) { child.spare := ?child };
  case null { assert false };
};
switch (y.spare) {
  case (?self) { self.value := null };
  case null { assert false };
};
switch (y.value) { case null {}; case (?_) { assert false } };

// Nested calls can return arrays/records with captured mutable references.
let counters = Prim.fixtureMutTabulate<[var Nat]>(64, func(i) {
  let inside = Prim.fixtureMutRecord<[var Nat]>([var i]);
  Prim.fixtureMutWrite<[var Nat]>(inside, [var i + 1]);
  inside.value
});
for (i in counters.keys()) { assert counters[i][0] == i + 1 };
