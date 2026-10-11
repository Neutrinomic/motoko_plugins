import Prim "mo:⛔";
actor {
  type Measurement = {
    instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat
  };
  type Item = {index : Nat; nested : [Nat]};
  transient var count = 0;
  transient var active = 0;
  transient var scalars : [Nat] = [];
  transient var records : [Item] = [];

  public func configure(index : Nat) : async () {
    count := [0, 1, 257, 4096][index];
  };
  public func clear() : async () { scalars := []; records := [] };
  public func scalar() : async Measurement {
    active := 0;
    let beforeAllocation = Prim.rts_total_allocation();
    let beforeReclaimed = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    scalars := Prim.fixtureTabulate<Nat>(count, func(index) { index });
    let ended = Prim.performanceCounter(0);
    let afterAllocation = Prim.rts_total_allocation();
    let afterReclaimed = Prim.rts_reclaimed();
    { instructions = ended - started;
      allocated = afterAllocation - beforeAllocation;
      reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2 }
  };
  public func nested() : async Measurement {
    active := 1;
    let beforeAllocation = Prim.rts_total_allocation();
    let beforeReclaimed = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    records := Prim.fixtureTabulate<Item>(count, func(index) {
      {index; nested = Prim.fixtureTabulate<Nat>(3, func(offset) { index + offset })}
    });
    let ended = Prim.performanceCounter(0);
    let afterAllocation = Prim.rts_total_allocation();
    let afterReclaimed = Prim.rts_reclaimed();
    { instructions = ended - started;
      allocated = afterAllocation - beforeAllocation;
      reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2 }
  };
  public query func bytesResult() : async Blob {
    var index = 0;
    if (active == 0) {
      assert scalars.size() == count;
      for (value in scalars.values()) { assert value == index; index += 1 };
    } else {
      assert records.size() == count;
      for (value in records.values()) {
        assert value.index == index;
        assert value.nested == [index, index + 1, index + 2];
        index += 1;
      };
    };
    "ok"
  };
}
