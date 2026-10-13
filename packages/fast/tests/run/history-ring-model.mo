//MOC-FLAG --package fast ../../src --plugin ../../../../dist/history-ring --sanity-checks -A M0236 -A M0155
import Ring "mo:fast/HistoryRing";
import Prim "mo:⛔";

// Independent flat-array oracle. Payloads deliberately differ from sequences.
func exercise(capacity : Nat) {
  let ring = Ring.empty<Nat>(capacity);
  var model : [Nat] = [];
  var next = 0;
  func slice(start : Nat, count : Nat) : [Nat] {
    Prim.Array_tabulate<Nat>(count, func(i) { model[start + i] })
  };
  func check() {
    let first = next - model.size();
    assert Ring.capacity(ring) == capacity;
    assert Ring.size(ring) == model.size();
    assert Ring.isEmpty(ring) == (model.size() == 0);
    assert Ring.firstSequence(ring) == first;
    assert Ring.nextSequence(ring) == next;
    assert Ring.toArray(ring) == model;
    let iterator = Ring.values(ring);
    var i = 0;
    while (i < model.size()) {
      assert Ring.get(ring, first + i) == ?model[i];
      assert iterator.next() == ?model[i];
      i += 1;
    };
    assert iterator.next() == null and iterator.next() == null;
    assert Ring.get(ring, next) == null;
    assert Ring.get(ring, 2 ** 140) == null;
    if (first > 0) assert Ring.get(ring, first - 1) == null;
    assert Ring.peekFront(ring) == (if (model.size() == 0) null else ?model[0]);
    assert Ring.peekBack(ring) == (if (model.size() == 0) null else ?model[model.size() - 1]);
    for (from in [0, first, first + 1, next, next + 1, 2 ** 140].values()) {
      for (limit in [0, 1, 7, capacity, 2 ** 140].values()) {
        let start = if (from < first) 0 else if (from >= next) model.size() else from - first;
        let available = model.size() - start;
        let count = if (limit < available) limit else available;
        assert Ring.page(ring, from, limit) == slice(start, count);
      }
    }
  };
  func append(value : Nat) {
    assert Ring.append(ring, value) == next;
    next += 1;
    if (capacity > 0) {
      let full = model.size() == capacity;
      let old = model;
      let length = if (full) old.size() else old.size() + 1;
      model := Prim.Array_tabulate<Nat>(length, func(i) {
        if (i + 1 == length) value else old[i + (if (full) 1 else 0)]
      });
    }
  };
  func drop(count : Nat) {
    let removed = if (count < model.size()) count else model.size();
    assert Ring.drop(ring, count) == removed;
    model := slice(removed, model.size() - removed);
  };
  func pop() {
    assert Ring.popFront(ring) == (if (model.size() == 0) null else ?model[0]);
    if (model.size() > 0) model := slice(1, model.size() - 1);
  };
  check();
  // Grow from a nonzero physical head, including split boundary chunks.
  var i = 0;
  while (i < 31) { append(i * 11); i += 1 };
  drop(17);
  i := 0;
  while (i < capacity * 3 + 3) {
    append(i * 13 + 5);
    if (i % 31 == 0) check();
    i += 1;
  };
  check();
  drop(63);
  check();
  i := 0;
  var random = capacity + 1;
  while (i < 1600) {
    random := (random * 48271) % 2147483647;
    switch (random % 17) {
      case (0) { Ring.clear(ring); model := [] };
      case (1) drop(random % 131);
      case (2) drop(2 ** 140);
      case (3) pop();
      case (4) pop();
      case (_) append(random);
    };
    if (i % 29 == 0) check();
    i += 1;
  };
  check();
  while (model.size() > 0) { pop(); check() };
  pop();
  drop(1);
  check();
  append(997);
  check();
};

for (capacity in [0, 1, 2, 3, 5, 31, 63, 64, 65, 66, 100, 127, 128, 129, 130, 255, 256, 257].values()) {
  exercise(capacity);
};

// A live tail can occupy the prefix of the same chunk as the removed head.
// Crossing the physical wrap must not free that still-live chunk.
for (capacity in [1, 5, 63, 64, 65, 100, 127, 128, 129].values()) {
  let ring = Ring.empty<Nat>(capacity);
  var i = 0;
  while (i <= capacity) { ignore Ring.append(ring, i); i += 1 };
  i := 1;
  while (i < capacity) { assert Ring.popFront(ring) == ?i; i += 1 };
  assert Ring.get(ring, capacity) == ?capacity;
  assert Ring.toArray(ring) == [capacity];
  assert Ring.popFront(ring) == ?capacity;
};

// Public sequence continuation near integer boundaries avoids billions of appends.
for (initial in [2 ** 30 - 2, 2 ** 60 - 2, 2 ** 61 - 2, 2 ** 64 - 2, 2 ** 140].values()) {
  let ring = Ring.emptyAt<Nat>(65, initial);
  var i = 0;
  while (i < 200) {
    assert Ring.append(ring, i * 7) == initial + i;
    i += 1;
  };
  assert Ring.firstSequence(ring) == initial + 135;
  assert Ring.nextSequence(ring) == initial + 200;
  assert Ring.get(ring, initial + 134) == null;
  assert Ring.get(ring, initial + 135) == ?945;
  assert Ring.page(ring, initial + 197, 2 ** 140) == [1379, 1386, 1393];
  assert Ring.drop(ring, 64) == 64;
  assert Ring.popFront(ring) == ?1393;
  assert Ring.append(ring, 999) == initial + 200;
  Ring.clear(ring);
  assert Ring.firstSequence(ring) == initial + 201;
  assert Ring.append(ring, 1) == initial + 201;
};

// Subtraction operands can straddle the compact representation boundary while
// the retained range itself is small. Check during the crossing, not only once
// both oldest and newest sequences have moved beyond it.
for (boundary in [2 ** 30, 2 ** 60, 2 ** 61, 2 ** 62, 2 ** 63, 2 ** 64, 2 ** 140].values()) {
  let initial = boundary - 4;
  let ring = Ring.emptyAt<Nat>(65, initial);
  var i = 0;
  while (i < 75) {
    assert Ring.append(ring, i) == initial + i;
    let firstValue = if (i < 65) 0 else i + 1 - 65;
    assert Ring.firstSequence(ring) == initial + firstValue;
    assert Ring.get(ring, initial + firstValue) == ?firstValue;
    assert Ring.get(ring, initial + i) == ?i;
    let page = Ring.page(ring, boundary - 1, 2 ** 140);
    let start = if (firstValue > 3) firstValue else 3;
    let length = if (i < start) 0 else i + 1 - start;
    assert page == Prim.Array_tabulate<Nat>(length, func(j) { start + j });
    assert Ring.page(ring, 0, 1) == [firstValue];
    i += 1;
  }
};

// The bulk-drop loop caches geometry across chunk release. Exercise both
// shared head/tail chunks and separate chunks, then append into the vacancies.
for (capacity in [1, 63, 64, 65, 100, 127, 128, 129, 257].values()) {
  for (offset in [0, 1, 63, 64, 65].values()) {
    for (amount in [0, 1, 63, 64, 65, capacity - 1, capacity, capacity + 1, 2 ** 140].values()) {
      let ring = Ring.empty<Nat>(capacity);
      var i = 0;
      while (i < capacity + offset) { ignore Ring.append(ring, i); i += 1 };
      let removed = if (amount < capacity) amount else capacity;
      assert Ring.drop(ring, amount) == removed;
      assert Ring.firstSequence(ring) == offset + removed;
      assert Ring.toArray(ring) == Prim.Array_tabulate<Nat>(capacity - removed, func(j) { offset + removed + j });
      while (i < capacity * 2 + offset + 3) { ignore Ring.append(ring, i); i += 1 };
      assert Ring.toArray(ring) == Prim.Array_tabulate<Nat>(capacity, func(j) { capacity + offset + 3 + j });
    }
  }
};

// A page ending exactly on a chunk boundary must not dereference the next
// directory entry: it can be absent after lazy allocation or a whole-chunk drop.
// Exercise zero-length pages and refilling detached chunks in the same states.
for (count in [63, 64, 65, 127, 128, 129, 191, 192, 193].values()) {
  let initial = 2 ** 64 - 3;
  let ring = Ring.emptyAt<Nat>(257, initial);
  var next = 0;
  var first = 0;
  func append(amount : Nat) {
    var n = 0;
    while (n < amount) {
      assert Ring.append(ring, next) == initial + next;
      next += 1;
      if (next - first > 257) first += 1;
      n += 1;
    }
  };
  func checkPages() {
    for (start in [0, first, 63, 64, 65, 127, 128, 129, 191, 192, next].values()) {
      for (limit in [0, 1, 63, 64, 65, 127, 128, 129, 192, 2 ** 140].values()) {
        let begin = if (start < first) first else if (start > next) next else start;
        let available = next - begin;
        let length = if (limit < available) limit else available;
        assert Ring.page(ring, initial + start, limit) == Prim.Array_tabulate<Nat>(length, func(i) { begin + i });
      }
    }
  };
  append(count);
  checkPages();
  let removed = if (count < 65) count else 65;
  assert Ring.drop(ring, 65) == removed;
  first += removed;
  checkPages();
  append(193);
  checkPages();
};
