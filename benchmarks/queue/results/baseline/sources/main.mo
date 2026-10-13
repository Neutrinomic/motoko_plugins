import Prim "mo:⛔";
import Fast "mo:fast/Queue";
import Core "mo:core/Queue";

persistent actor {
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
    Fast.clear(fast); Core.clear(core); input := [];
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
        while (i < count) { Core.pushBack(core, i); i += 1 };
      } else {
        while (i < count) { Fast.pushBack(fast, i); i += 1 };
      };
    };
  };
  func unwrap(value : ?Nat) : Nat { switch value { case (?v) v; case null 0 } };
  func runFast() {
    var i = 0;
    switch selected {
      case 0 { while (i < repetitions) { Fast.pushBack(fast, i); i += 1 } };
      case 1 { while (i < repetitions) { Fast.pushFront(fast, i); i += 1 } };
      case 2 { while (i < repetitions) { checksum += unwrap(Fast.popFront(fast)); i += 1 } };
      case 3 { while (i < repetitions) { checksum += unwrap(Fast.popBack(fast)); i += 1 } };
      case 4 { while (i < repetitions) { checksum += unwrap(Fast.peekFront(fast)); i += 1 } };
      case 5 { while (i < repetitions) { checksum += unwrap(Fast.peekBack(fast)); i += 1 } };
      case 6 { while (i < repetitions) { Fast.pushBack(fast, length + i); checksum += unwrap(Fast.popFront(fast)); i += 1 } };
      case 7 { while (i < repetitions) { Fast.pushBack(fast, length + i); checksum += unwrap(Fast.popBack(fast)); i += 1 } };
      case 8 {
        while (i < repetitions) {
          if (i % 2 == 0) { Fast.pushFront(fast, length + i); checksum += unwrap(Fast.popBack(fast)) }
          else { Fast.pushBack(fast, length + i); checksum += unwrap(Fast.popFront(fast)) };
          i += 1;
        }
      };
      case 9 { for (value in Fast.values(fast)) { checksum += value } };
      case 10 { for (value in Fast.reverseValues(fast)) { checksum += value } };
      case 11 { fast := Fast.fromArray(input); checksum := Fast.size(fast) };
      case 12 { let result = Fast.toArray(fast); checksum := result.size(); if (result.size() > 0) checksum += result[result.size() - 1] };
      case 13 { fast := Fast.clone(fast); checksum := Fast.size(fast) };
      case _ Prim.trap("unknown operation");
    }
  };
  func runCore() {
    var i = 0;
    switch selected {
      case 0 { while (i < repetitions) { Core.pushBack(core, i); i += 1 } };
      case 1 { while (i < repetitions) { Core.pushFront(core, i); i += 1 } };
      case 2 { while (i < repetitions) { checksum += unwrap(Core.popFront(core)); i += 1 } };
      case 3 { while (i < repetitions) { checksum += unwrap(Core.popBack(core)); i += 1 } };
      case 4 { while (i < repetitions) { checksum += unwrap(Core.peekFront(core)); i += 1 } };
      case 5 { while (i < repetitions) { checksum += unwrap(Core.peekBack(core)); i += 1 } };
      case 6 { while (i < repetitions) { Core.pushBack(core, length + i); checksum += unwrap(Core.popFront(core)); i += 1 } };
      case 7 { while (i < repetitions) { Core.pushBack(core, length + i); checksum += unwrap(Core.popBack(core)); i += 1 } };
      case 8 {
        while (i < repetitions) {
          if (i % 2 == 0) { Core.pushFront(core, length + i); checksum += unwrap(Core.popBack(core)) }
          else { Core.pushBack(core, length + i); checksum += unwrap(Core.popFront(core)) };
          i += 1;
        }
      };
      case 9 { for (value in Core.values(core)) { checksum += value } };
      case 10 { for (value in Core.reverseValues(core)) { checksum += value } };
      case 11 { core := Core.fromArray(input); checksum := Core.size(core) };
      case 12 { let result = Core.toArray(core); checksum := result.size(); if (result.size() > 0) checksum += result[result.size() - 1] };
      case 13 { core := Core.clone(core); checksum := Core.size(core) };
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
      size = if (implementation == 0) Core.size(core) else Fast.size(fast); operations = repetitions }
  };
  public query func validate(implementation : Nat) : async [Nat] {
    if (implementation == 0) Core.toArray(core) else { Fast.assertValid(fast); Fast.toArray(fast) }
  };
}
