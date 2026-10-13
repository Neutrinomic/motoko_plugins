//MOC-FLAG --package fast ../../src --plugin ../../../../dist/history-ring --sanity-checks -A M0236 -A M0155
import Ring "mo:fast/HistoryRing";

// Instantiate immediate storage before heap payloads, catching accidentally
// reused type-specific native helpers and representation-sensitive null slots.
let immediate = Ring.empty<Bool>(65);
var i = 0;
while (i < 200) { ignore Ring.append(immediate, i % 2 == 0); i += 1 };
assert Ring.toArray(immediate).size() == 65;
assert Ring.popFront(immediate) == ?false;
let nulls = Ring.empty<Null>(65);
i := 0;
while (i < 200) { ignore Ring.append(nulls, null); i += 1 };
assert Ring.get(nulls, 199) == ?null;
assert Ring.popFront(nulls) == ?null;
let nullable = Ring.empty<?Null>(65);
i := 0;
while (i < 200) { ignore Ring.append(nullable, if (i % 2 == 0) null else ?null); i += 1 };
assert Ring.get(nullable, 199) == ??null;
assert Ring.popFront(nullable) == ??null;
assert Ring.popFront(nullable) == ?null;

type Cell = {var count : Nat};
type Payload = {name : Text; cell : Cell; read : () -> Nat; self : [var ?Payload]};
let cell : Cell = {var count = 0};
let cycle : [var ?Payload] = [var null];
let value : Payload = {name = "shared 🌍"; cell; read = func() : Nat { cell.count }; self = cycle};
cycle[0] := ?value;
let ring = Ring.empty<?Payload>(129);
let alias = ring;
i := 0;
while (i < 400) {
  assert Ring.append(alias, if (i % 7 == 0) null else ?value) == i;
  i += 1;
};
let snapshot = Ring.page(ring, 300, 30);
assert snapshot.size() == 30;
cell.count := 99;
func verify(payload : ?Payload) {
  switch payload {
    case null {};
    case (?p) {
      assert p.name == "shared 🌍" and p.cell.count == 99 and p.read() == 99;
      switch (p.self[0]) { case (?self) assert self.read() == 99; case null assert false };
      p.cell.count := 100;
      assert cell.count == 100;
      p.cell.count := 99;
    }
  }
};
for (payload in Ring.values(ring)) verify(payload);
assert Ring.drop(alias, 128) == 128;
assert Ring.size(ring) == 1;
Ring.clear(alias);
assert Ring.isEmpty(ring);
for (payload in snapshot.values()) verify(payload);
assert Ring.append(ring, ?value) == 400;
switch (Ring.popFront(alias)) { case (??p) verify(?p); case _ assert false };
switch (Ring.popFront(ring)) { case null {}; case _ assert false };

let integers = Ring.empty<Int>(2);
ignore Ring.append(integers, -(2 ** 180));
ignore Ring.append(integers, 2 ** 200);
assert Ring.toArray(integers) == [-(2 ** 180), 2 ** 200];
let functions = Ring.empty<() -> Nat>(1);
ignore Ring.append(functions, value.read);
switch (Ring.get(functions, 0)) { case (?read) assert read() == 99; case _ assert false };
