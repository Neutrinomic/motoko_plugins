import Prim "mo:⛔";
import Ring "mo:fast/HistoryRing";
import Queue "mo:core/Queue";

actor {
  type Measurement = { instructions : Nat64; allocated : Nat; reclaimed : Nat; checksum : Nat; size : Nat; first : Nat; next : Nat; operations : Nat };
  type Memory = { heap : Nat; memory : Nat; allocated : Nat; reclaimed : Nat; maxLive : Nat; size : Nat };
  transient var fast = true;
  transient var capacity = 0;
  transient var ring = Ring.empty<Nat>(0);
  transient var queue = Queue.empty<Nat>();
  transient var next = 0;
  transient var blobs = Ring.empty<Blob>(0);
  transient var blobQueue = Queue.empty<Blob>();
  transient var blobNext = 0;
  func size() : Nat { if (fast) Ring.size(ring) else Queue.size(queue) };
  func append(value : Nat) : Nat {
    if (fast) Ring.append(ring, value) else {
      let sequence = next;
      next += 1;
      Queue.pushBack(queue, value);
      if (Queue.size(queue) > capacity) ignore Queue.popFront(queue);
      sequence
    }
  };
  func get(sequence : Nat) : ?Nat {
    if (fast) Ring.get(ring, sequence) else {
      let first = next - Queue.size(queue);
      if (sequence < first or sequence >= next) return null;
      let iterator = Queue.values(queue);
      var skip = sequence - first;
      while (skip > 0) { ignore iterator.next(); skip -= 1 };
      iterator.next()
    }
  };
  func page(from : Nat, limit : Nat) : [Nat] {
    if (fast) Ring.page(ring, from, limit) else {
      let first = next - Queue.size(queue);
      let start = if (from < first) first else from;
      if (start >= next) return [];
      let count = if (limit < next - start) limit else next - start;
      let iterator = Queue.values(queue);
      var skip = start - first;
      while (skip > 0) { ignore iterator.next(); skip -= 1 };
      Prim.Array_tabulate<Nat>(count, func(_) {
        let ?value = iterator.next() else Prim.trap("missing queue value"); value
      })
    }
  };
  func drop(count : Nat) : Nat {
    if (fast) Ring.drop(ring, count) else {
      let amount = if (count < Queue.size(queue)) count else Queue.size(queue);
      var i = 0;
      while (i < amount) { ignore Queue.popFront(queue); i += 1 };
      amount
    }
  };
  public func configure(useFast : Bool, cap : Nat, fill : Bool) : async () {
    fast := useFast; capacity := cap;
    ring := Ring.empty<Nat>(cap); queue := Queue.empty<Nat>(); next := 0;
    blobs := Ring.empty<Blob>(0); blobQueue := Queue.empty<Blob>(); blobNext := 0;
    if (fill) { var i = 0; while (i < cap) { assert append(i) == i; i += 1 } }
  };
  public func bench(operation : Nat, repetitions : Nat, pageLength : Nat) : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    var checksum : Nat32 = 0;
    var operations = 0;
    switch operation {
      case (0 or 1) {
        var i = 0;
        while (i < repetitions) { let value = if (fast) Ring.nextSequence(ring) else next; checksum +%= Prim.natToNat32(append(value)); i += 1 };
        operations := repetitions;
      };
      case 2 {
        let finish = if (fast) Ring.nextSequence(ring) else next;
        let sequence = if (size() > 0) finish - size() / 2 - 1 else finish;
        var i = 0;
        while (i < repetitions) { switch (get(sequence)) { case (?value) checksum +%= Prim.natToNat32(value); case null {} }; i += 1 };
        operations := repetitions;
      };
      case 3 {
        let finish = if (fast) Ring.nextSequence(ring) else next;
        let from = if (size() > pageLength) finish - pageLength else 0;
        var i = 0;
        while (i < repetitions) { for (value in page(from, pageLength).values()) checksum +%= Prim.natToNat32(value); i += 1 };
        operations := repetitions;
      };
      case 4 { operations := drop(repetitions); checksum := Prim.natToNat32(operations) };
      case 5 {
        var i = 0;
        while (i < repetitions) {
          switch (if (fast) Ring.popFront(ring) else Queue.popFront(queue)) {
            case (?value) checksum +%= Prim.natToNat32(value);
            case null {};
          };
          i += 1;
        };
        operations := repetitions;
      };
      case _ Prim.trap("unknown operation");
    };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    let finish = if (fast) Ring.nextSequence(ring) else next;
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore; reclaimed = reclaimedAfter - reclaimedBefore;
     checksum = Prim.nat32ToNat(checksum); size = size(); first = finish - size(); next = finish; operations}
  };
  // Runs after timing and memory sampling; exact sequence checks detect order
  // errors that the deliberately cheap wrapping benchmark checksum cannot.
  public query func verify() : async {count : Nat; first : Nat; next : Nat; slots : Nat} {
    let count = size();
    let finish = if (fast) Ring.nextSequence(ring) else next;
    let first = finish - count;
    var sequence = first;
    let values = if (fast) Ring.values(ring) else Queue.values(queue);
    for (value in values) { assert value == sequence; sequence += 1 };
    assert sequence == finish;
    var slots = 0;
    if (fast) {
      for (entry in ring.chunks.values()) switch entry {
        case null {};
        case (?chunk) for (value in chunk.values()) switch value {
          case null {};
          case (?_) slots += 1;
        };
      };
      assert slots == count;
    };
    {count; first; next = finish; slots}
  };
  public query func memory() : async Memory {
    {heap = Prim.rts_heap_size(); memory = Prim.rts_memory_size(); allocated = Prim.rts_total_allocation();
     reclaimed = Prim.rts_reclaimed(); maxLive = Prim.rts_max_live_size(); size = if (blobNext == 0) size() else if (fast) Ring.size(blobs) else Queue.size(blobQueue)}
  };
  public func configureChurn(useFast : Bool, cap : Nat) : async () {
    fast := useFast; capacity := cap; ring := Ring.empty<Nat>(0); queue := Queue.empty<Nat>(); next := 0;
    blobs := Ring.empty<Blob>(cap); blobQueue := Queue.empty<Blob>(); blobNext := 0;
  };
  public func churn(count : Nat, bytes : Nat) : async Nat {
    var i = 0;
    while (i < count) {
      let value = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(bytes, func(j) { Prim.natToNat8((blobNext + j) % 251) }));
      if (fast) { assert Ring.append(blobs, value) == blobNext } else {
        Queue.pushBack(blobQueue, value);
        if (Queue.size(blobQueue) > capacity) ignore Queue.popFront(blobQueue)
      };
      blobNext += 1; i += 1;
    };
    if (fast) Ring.size(blobs) else Queue.size(blobQueue)
  };
  // Benchmark-only inspection of the documented-private representation proves
  // dropped payload references are absent independently of partition GC timing.
  public query func storage() : async {directory : Nat; chunks : Nat; slots : Nat; bytes : Nat} {
    var chunks = 0; var slots = 0; var bytes = 0;
    for (entry in blobs.chunks.values()) switch entry {
      case null {};
      case (?chunk) {
        chunks += 1;
        for (value in chunk.values()) switch value {
          case null {};
          case (?blob) {slots += 1; bytes += blob.size()};
        };
      };
    };
    {directory = blobs.chunks.size(); chunks; slots; bytes}
  };
  public func dropChurn(count : Nat) : async Nat {
    if (fast) Ring.drop(blobs, count) else {
      let amount = if (count < Queue.size(blobQueue)) count else Queue.size(blobQueue);
      var i = 0;
      while (i < amount) { ignore Queue.popFront(blobQueue); i += 1 };
      amount
    }
  };
  public func clearChurn() : async () { Ring.clear(blobs); Queue.clear(blobQueue) };
  public query func validateChurn(bytes : Nat) : async Nat {
    let values = if (fast) Ring.values(blobs) else Queue.values(blobQueue);
    var sequence = blobNext - (if (fast) Ring.size(blobs) else Queue.size(blobQueue));
    var checksum = 0;
    for (value in values) {
      assert value.size() == bytes;
      var j = 0;
      for (byte in value.values()) { assert Prim.nat8ToNat(byte) == (sequence + j) % 251; checksum += Prim.nat8ToNat(byte); j += 1 };
      sequence += 1;
    };
    assert sequence == blobNext;
    checksum
  };
}

