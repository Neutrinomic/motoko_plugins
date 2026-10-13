//MOC-FLAG --plugin ../../../dist/queue --plugin ../../../dist/history-ring --plugin ../../../dist/indexed-priority-queue --plugin ../../../dist/mutable-map --plugin ../../../dist/mutable-set
//MOC-FLAG --package fast ../../../packages/fast/src --package core $MOTOKO_CORE
import Queue "mo:fast/Queue";
import HistoryRing "mo:fast/HistoryRing";
import Priority "mo:fast/IndexedPriorityQueue";
import Map "mo:fast/Map";
import Set "mo:fast/Set";
import Nat "mo:core/Nat";

// Pass the same managed values and handles through five compiler-only plugins.
type Payload = { id : Nat; var visits : Nat; optional : ?Null };
let queue = Queue.empty<Payload>();
let history = HistoryRing.empty<Payload>(5);
let pending = Priority.empty<Nat, Payload>();
let handles = Map.empty<Nat, Priority.Handle<Nat, Payload>>();
let seen = Set.empty<Nat>();

var id = 0;
while (id < 80) {
  queue.pushBack({ id; var visits = 0; optional = ?null });
  id += 1;
};
while (not queue.isEmpty()) {
  let value = switch (queue.popFront()) {
    case (?value) value;
    case null { assert false; loop {} };
  };
  assert history.append(value) == value.id;
  Map.add(handles, Nat.compare, value.id,
    pending.push(Nat.compare, (80 - value.id : Nat), value));
};
assert history.firstSequence() == 75;
assert history.nextSequence() == 80;
let page = history.page(0, 2);
assert page.size() == 2 and page[0].id == 75 and page[1].id == 76;

let cancelled = switch (handles.get(Nat.compare, 10)) {
  case (?handle) handle;
  case null { assert false; loop {} };
};
switch (cancelled.remove(Nat.compare)) {
  case (?(priority, value)) { assert priority == 70 and value.id == 10 };
  case null assert false;
};
switch (cancelled.get()) { case null {}; case _ assert false };
assert not cancelled.reschedule(Nat.compare, 0);

let accelerated = switch (handles.get(Nat.compare, 75)) {
  case (?handle) handle;
  case null { assert false; loop {} };
};
assert accelerated.reschedule(Nat.compare, 0);
switch (accelerated.get()) {
  case (?(_, value)) { value.visits += 1 };
  case null assert false;
};
switch (history.get(75)) {
  case (?value) { assert value.visits == 1 and value.optional == ?null };
  case null assert false;
};
var previous = 0;
while (not pending.isEmpty()) {
  switch (pending.pop(Nat.compare)) {
    case (?(priority, value)) {
      assert priority >= previous;
      previous := priority;
      assert seen.insert(Nat.compare, value.id);
      let handle = switch (handles.get(Nat.compare, value.id)) {
        case (?handle) handle;
        case null { assert false; loop {} };
      };
      switch (handle.get()) { case null {}; case _ assert false };
    };
    case null assert false;
  }
};
assert seen.size() == 79;
assert not seen.contains(Nat.compare, 10);
queue.clear();
history.clear();
pending.clear();
Map.clear(handles);
seen.clear();
assert history.nextSequence() == 80;
