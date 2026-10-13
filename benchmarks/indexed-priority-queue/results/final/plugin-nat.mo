import Prim "mo:⛔";
import Nat "mo:core/Nat";
import Int "mo:core/Int";
import Q "mo:fast/IndexedPriorityQueue";
actor {
  type Key = Nat;
  type Pair = (Key, Nat);
  type Order = {#less; #equal; #greater};
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; checksum : Nat; count : Nat};
  type Memory = {heap : Nat; memory : Nat; allocated : Nat; reclaimed : Nat};
  func compareDeadline(a : {at : Int; ticket : Nat}, b : {at : Int; ticket : Nat}) : Order {
    if(a.at < b.at) #less else if(a.at > b.at) #greater else Nat.compare(a.ticket,b.ticket)
  };
  func comparePair(a : Pair, b : Pair) : Order { Nat.compare(b.0,a.0) };
  func key(i : Nat) : Key { i };
  func number(k : Key) : Nat { k };
  transient var queue = Q.empty<Key, Nat>(); transient var handles : [var ?Q.Handle<Key, Nat>] = [var];
  transient var configured = 0;
  transient var sink = 0;
  func add(i : Nat, priority : Key, value : Nat) { handles[i] := ?Q.push(queue, Nat.compare, priority, value) };
  func peek() : ?Pair { Q.peek(queue) };
  func peekPriority() : ?Key { Q.peekPriority(queue) };
  func pop() : ?Pair { Q.pop(queue, Nat.compare) };
  func get(i : Nat) : ?Pair { switch(handles[i]) {case (?h) Q.get(h); case null null} };
  func remove(i : Nat) : ?Pair { switch(handles[i]) {case (?h) Q.remove(h, Nat.compare); case null null} };
  func reschedule(i : Nat, priority : Key) : Bool { switch(handles[i]) {case (?h) Q.reschedule(h, Nat.compare, priority); case null false} };
  func replace(i : Nat, priority : Key, value : Nat) : ?Pair { switch(handles[i]) {case (?h) Q.replace(h, Nat.compare, priority, value); case null null} };
  func size() : Nat { Q.size(queue) };
  func value(pair : ?Pair) : Nat {switch pair {case (?(_,v)) v; case null 0}};
  public func configure(n : Nat, capacity : Nat) : async () {
    Q.clear(queue); handles := Prim.Array_init<?Q.Handle<Key, Nat>>(capacity, null);
    configured := n; sink := 0;
  };
  public func fill(start : Nat, count : Nat) : async () {
    var i = start;
    while(i < start + count) { let p : Nat = configured - i; add(i,key(p),p); i += 1 };
  };
  public func measure(operation : Nat, repetitions : Nat) : async Measurement {
    let ab = Prim.rts_total_allocation();
    let rb = Prim.rts_reclaimed();
    let before = Prim.performanceCounter(0);
    var checksum = 0;
    var i = 0;
    while(i < repetitions) {
      switch operation {
        case 0 {checksum += value(peek())};
        case 1 {checksum += value(get(i % configured))};
        case 2 {let p = configured + 1 + i; add(configured+i,key(p),p); checksum += p};
        case 3 {checksum += value(pop())};
        case 4 {checksum += value(remove(i))};
        case 5 {if(reschedule(i,key(configured+1+i))) checksum += 1};
        case 6 {checksum += value(replace(i,key(configured+1+i),configured+1+i))};
        case 7 {add(configured,key(0),i); checksum += value(pop())};
        case 8 {Q.clear(queue); handles := [var]};
        case 9 {switch(peekPriority()) {case (?k) checksum += number(k); case null {}}};
        case _ Prim.trap("unknown operation");
      };
      i += 1;
    };
    sink := checksum;
    let after = Prim.performanceCounter(0);
    let aa = Prim.rts_total_allocation();
    let ra = Prim.rts_reclaimed();
    {instructions = after - before; allocated = aa - ab; reclaimed = ra - rb; checksum; count = size()}
  };
  public query func memory() : async Memory {
    {heap = Prim.rts_heap_size(); memory = Prim.rts_memory_size();
      allocated = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
  public func validate() : async {count : Nat; sum : Nat; sorted : Bool} {
    var count = 0; var sum = 0; var previous = 0; var sorted = true;
    label drain loop { switch(pop()) {
      case null break drain;
      case (?(k,v)) {let p = number(k); if(count > 0 and p < previous) sorted := false;
        previous := p; count += 1; sum += v;};
    } };
    {count; sum; sorted}
  };
}
