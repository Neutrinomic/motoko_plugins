// Multi-message retention probe. Payload creation is deliberately included in
// allocation counters; post-collection heap is reported separately by the runner.
import Prim "mo:⛔";
import Fast "mo:fast/Queue";
import Core "mo:core/Queue";

actor {
  type Item = {id : Nat; bytes : Blob};
  type Snapshot = {
    size : Nat;
    heap : Nat;
    allocated : Nat;
    reclaimed : Nat;
    memory : Nat;
    maxLive : Nat;
    pushed : Nat;
    popped : Nat;
    nodes : Nat;
    spares : Nat;
    slots : Nat;
    payloads : Nat;
    payloadBytes : Nat;
  };
  let fast = Fast.empty<Item>();
  let core = Core.empty<Item>();
  var native = true;
  var payloadBytes = 4096;
  var nextId = 0;
  var frontId = 0;
  var pushed = 0;
  var popped = 0;

  func length() : Nat { if (native) fast.size() else core.size() };
  func check(item : Item, expected : Nat) {
    assert item.id == expected;
    assert item.bytes.size() == payloadBytes;
    if (payloadBytes > 0) {
      let expectedByte = Prim.natToNat8(expected % 251);
      assert item.bytes[0] == expectedByte;
      assert item.bytes[payloadBytes - 1] == expectedByte;
    }
  };
  func push() {
    let byte = Prim.natToNat8(nextId % 251);
    let item = {
      id = nextId;
      bytes = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(payloadBytes, func(_) { byte }));
    };
    if (native) fast.pushBack(item) else core.pushBack(item);
    nextId += 1;
    pushed += 1;
  };
  func pop() {
    let value = if (native) fast.popFront() else core.popFront();
    switch value {
      case null { assert false };
      case (?item) { check(item, frontId) };
    };
    frontId += 1;
    popped += 1;
  };

  public func configure(useNative : Bool, bytes : Nat) : async () {
    assert fast.isEmpty() and core.isEmpty();
    native := useNative;
    payloadBytes := bytes;
  };
  public func fill(count : Nat) : async () {
    var i = 0;
    while (i < count) { push(); i += 1 };
  };
  public func drain(count : Nat) : async () {
    assert count <= length();
    var i = 0;
    while (i < count) { pop(); i += 1 };
  };
  public func clear() : async () {
    if (native) fast.clear() else core.clear();
    frontId := nextId;
  };
  public func churn(count : Nat) : async () {
    assert length() > 0;
    var i = 0;
    while (i < count) { pop(); push(); i += 1 };
  };
  // The pinned RTS cannot evacuate its current 64 MiB allocation partition.
  // A 63 MiB scratch array followed by 2 MiB forces the old allocation
  // partition to close. The last scratch array is constant probe overhead;
  // the runner reports it rather than claiming raw occupied heap is live size.
  public func collectionPressure() : async () {
    ignore Prim.Array_init<Nat>(63 * 1024 * 1024 / 8, 0);
    ignore Prim.Array_init<Nat>(2 * 1024 * 1024 / 8, 0);
  };
  public query func verify() : async Nat {
    if (native) fast.assertValid();
    let iter = if (native) fast.values() else core.values();
    var expected = frontId;
    for (item in iter) { check(item, expected); expected += 1 };
    assert expected == nextId;
    let reverse = if (native) fast.reverseValues() else core.reverseValues();
    for (item in reverse) {
      assert expected > frontId;
      expected -= 1;
      check(item, expected);
    };
    assert expected == frontId;
    length()
  };
  public query func snapshot() : async Snapshot {
    let heap = Prim.rts_heap_size();
    let allocated = Prim.rts_total_allocation();
    let reclaimed = Prim.rts_reclaimed();
    var nodes = 0;
    var spares = 0;
    var slots = 0;
    var payloads = 0;
    var bytes = 0;
    if (native) {
      var current = fast.front;
      label walk loop {
        switch current {
          case null { break walk };
          case (?chunk) {
            nodes += 1;
            assert nodes <= length() + 1;
            slots += chunk.values.size();
            for (item in chunk.values.values()) {
              switch item {
                case null {};
                case (?value) { payloads += 1; bytes += value.bytes.size() };
              }
            };
            current := chunk.next;
          }
        }
      };
      switch (fast.spare) {
        case null {};
        case (?chunk) {
          assert chunk.start == 0 and chunk.count == 0;
          switch (chunk.previous) { case null {}; case _ assert false };
          switch (chunk.next) { case null {}; case _ assert false };
          for (item in chunk.values.values()) {
            switch item { case null {}; case _ assert false }
          };
          nodes += 1;
          spares += 1;
          slots += chunk.values.size();
        }
      };
      if (length() == 0) assert nodes <= 1;
    } else {
      var current = core.front;
      label walk loop {
        switch current {
          case null { break walk };
          case (?node) {
            nodes += 1;
            assert nodes <= length();
            slots += 1;
            payloads += 1;
            bytes += node.value.bytes.size();
            current := node.next;
          }
        }
      }
    };
    assert payloads == length();
    {
      size = length();
      heap;
      allocated;
      reclaimed;
      memory = Prim.rts_memory_size();
      maxLive = Prim.rts_max_live_size();
      pushed;
      popped;
      nodes;
      spares;
      slots;
      payloads;
      payloadBytes = bytes;
    }
  };
}
