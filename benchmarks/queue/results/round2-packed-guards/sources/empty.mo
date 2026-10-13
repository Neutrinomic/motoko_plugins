import Prim "mo:⛔";
import Queue "mo:fast/Queue";

actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; calls : Nat; size : Nat};
  transient let queue = Queue.empty<Nat>();
  transient var operation = 0;
  transient var repetitions = 1024;
  transient var calls = 0;

  public func configure(state : Nat, op : Nat, count : Nat) : async () {
    assert state < 4 and op < 4;
    assert queue.isEmpty();
    operation := op;
    repetitions := count;
    calls := 0;
    if (state > 0) {
      var i = 0;
      while (i < 65) { queue.pushBack(i); i += 1 };
      i := 0;
      while (i < 65) {
        if (state == 2) assert queue.popBack() == ?(64 - i : Nat)
        else assert queue.popFront() == ?i;
        i += 1;
      };
      if (state == 3) queue.clear();
    };
    assert queue.isEmpty();
    queue.assertValid();
  };

  public func bench() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let before = Prim.performanceCounter(0);
    var i = 0;
    switch operation {
      case 0 { while (i < repetitions) { assert queue.peekFront() == null; i += 1 } };
      case 1 { while (i < repetitions) { assert queue.peekBack() == null; i += 1 } };
      case 2 { while (i < repetitions) { assert queue.popFront() == null; i += 1 } };
      case 3 { while (i < repetitions) { assert queue.popBack() == null; i += 1 } };
      case _ Prim.trap("bad operation");
    };
    calls := i;
    let after = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = after - before; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; calls; size = queue.size()}
  };

  public func validateRefill() : async Bool {
    assert queue.isEmpty();
    queue.assertValid();
    var i = 0;
    while (i < 65) { queue.pushBack(i); i += 1 };
    i := 0;
    while (i < 65) { assert queue.popFront() == ?i; i += 1 };
    queue.pushFront(11);
    queue.pushBack(12);
    assert queue.popFront() == ?11;
    assert queue.popBack() == ?12;
    assert queue.isEmpty();
    queue.assertValid();
    true
  };
}
