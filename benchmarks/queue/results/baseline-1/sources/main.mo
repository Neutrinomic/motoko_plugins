import Prim "mo:⛔";
import Fast "mo:fast/Queue";
import Core "mo:core/Queue";

actor {
  type Measurement = {
    instructions : Nat64; allocated : Nat; reclaimed : Nat;
    checksum : Nat; size : Nat; operations : Nat;
  };
  transient var fast = Fast.empty<Nat>();
  transient var core = Core.empty<Nat>();
  transient var input : [Nat] = [];
  transient var selected = 0;
  transient var length = 0;
  transient var repetitions = 0;
  transient var checksum = 0;

  public func configure(implementation : Nat, operation : Nat, count : Nat) : async () {
    fast.clear(); core.clear(); input := [];
    selected := operation; length := count;
    repetitions := if (operation == 4 or operation == 5) {
      if (count == 0) 1 else count
    } else if (operation >= 6 and operation <= 8) {
      if (count < 1024) 1024 else count
    } else count;
    checksum := 0;
    if (operation == 11) {
      input := Prim.Array_tabulate<Nat>(count, func(i) { i });
    } else if (operation >= 2) {
      var i = 0;
      if (implementation == 0) {
        while (i < count) { core.pushBack(i); i += 1 };
      } else {
        while (i < count) { fast.pushBack(i); i += 1 };
      };
    };
  };
  func unwrap(value : ?Nat) : Nat { switch value { case (?v) v; case null 0 } };
  func runFast() {
    var i = 0;
    switch selected {
      case 0 { while (i < repetitions) { fast.pushBack(i); i += 1 } };
      case 1 { while (i < repetitions) { fast.pushFront(i); i += 1 } };
      case 2 { while (i < repetitions) { checksum += unwrap(fast.popFront()); i += 1 } };
      case 3 { while (i < repetitions) { checksum += unwrap(fast.popBack()); i += 1 } };
      case 4 { while (i < repetitions) { checksum += unwrap(fast.peekFront()); i += 1 } };
      case 5 { while (i < repetitions) { checksum += unwrap(fast.peekBack()); i += 1 } };
      case 6 { while (i < repetitions) { fast.pushBack(length + i); checksum += unwrap(fast.popFront()); i += 1 } };
      case 7 { while (i < repetitions) { fast.pushBack(length + i); checksum += unwrap(fast.popBack()); i += 1 } };
      case 8 {
        while (i < repetitions) {
          if (i % 2 == 0) { fast.pushFront(length + i); checksum += unwrap(fast.popBack()) }
          else { fast.pushBack(length + i); checksum += unwrap(fast.popFront()) };
          i += 1;
        }
      };
      case 9 { for (value in fast.values()) { checksum += value } };
      case 10 { for (value in fast.reverseValues()) { checksum += value } };
      case 11 { fast := Fast.fromArray(input); checksum := fast.size() };
      case 12 { let result = fast.toArray(); checksum := result.size(); if (result.size() > 0) checksum += result[result.size() - 1] };
      case 13 { fast := fast.clone(); checksum := fast.size() };
      case _ Prim.trap("unknown operation");
    }
  };
  func runCore() {
    var i = 0;
    switch selected {
      case 0 { while (i < repetitions) { core.pushBack(i); i += 1 } };
      case 1 { while (i < repetitions) { core.pushFront(i); i += 1 } };
      case 2 { while (i < repetitions) { checksum += unwrap(core.popFront()); i += 1 } };
      case 3 { while (i < repetitions) { checksum += unwrap(core.popBack()); i += 1 } };
      case 4 { while (i < repetitions) { checksum += unwrap(core.peekFront()); i += 1 } };
      case 5 { while (i < repetitions) { checksum += unwrap(core.peekBack()); i += 1 } };
      case 6 { while (i < repetitions) { core.pushBack(length + i); checksum += unwrap(core.popFront()); i += 1 } };
      case 7 { while (i < repetitions) { core.pushBack(length + i); checksum += unwrap(core.popBack()); i += 1 } };
      case 8 {
        while (i < repetitions) {
          if (i % 2 == 0) { core.pushFront(length + i); checksum += unwrap(core.popBack()) }
          else { core.pushBack(length + i); checksum += unwrap(core.popFront()) };
          i += 1;
        }
      };
      case 9 { for (value in core.values()) { checksum += value } };
      case 10 { for (value in core.reverseValues()) { checksum += value } };
      case 11 { core := Core.fromArray(input); checksum := core.size() };
      case 12 { let result = core.toArray(); checksum := result.size(); if (result.size() > 0) checksum += result[result.size() - 1] };
      case 13 { core := core.clone(); checksum := core.size() };
      case _ Prim.trap("unknown operation");
    }
  };
  public func bench(implementation : Nat) : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let before = Prim.performanceCounter(0);
    if (implementation == 0) runCore() else runFast();
    let after = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = after - before; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; checksum;
      size = if (implementation == 0) core.size() else fast.size(); operations = repetitions }
  };
  public query func validate(implementation : Nat) : async [Nat] {
    if (implementation == 0) core.toArray() else { fast.assertValid(); fast.toArray() }
  };
}
