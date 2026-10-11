import Prim "mo:⛔";
actor {
  type Measurement = { instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat };
  transient var repetitions = 0;
  transient var checksum = 0;
  transient var expected = 0;
  transient var call0 : () -> Nat = func () : Nat { 1 };
  transient var call1 : Nat -> Nat = func (n : Nat) : Nat { n + 1 };
  transient var call2 : (Nat, Nat) -> Nat = func (a : Nat, b : Nat) : Nat { a + b };
  public func configure(index : Nat) : async () { repetitions := [0, 1, 4096][index] };
  public func clear() : async () { checksum := 0; expected := 0 };
  public func callback0() : async Measurement {
    expected := repetitions;
    let allocated0 = Prim.rts_total_allocation();
    let reclaimed0 = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    var result = 0;
    var i = 0;
    while (i < repetitions) {
      result += Prim.fixtureApply0<Nat>(call0);
      i += 1;
    };
    checksum := result;
    let stopped = Prim.performanceCounter(0);
    {instructions = stopped - started; allocated = Prim.rts_total_allocation() - allocated0;
     reclaimed = Prim.rts_reclaimed() - reclaimed0; outputSize = 2}
  };
  public func callback1() : async Measurement {
    expected := repetitions * (repetitions + 1) / 2;
    let allocated0 = Prim.rts_total_allocation();
    let reclaimed0 = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    var result = 0;
    var i = 0;
    while (i < repetitions) {
      result += Prim.fixtureApply<Nat, Nat>(call1, i);
      i += 1;
    };
    checksum := result;
    let stopped = Prim.performanceCounter(0);
    {instructions = stopped - started; allocated = Prim.rts_total_allocation() - allocated0;
     reclaimed = Prim.rts_reclaimed() - reclaimed0; outputSize = 2}
  };
  public func callback2() : async Measurement {
    expected := repetitions * (repetitions + 1) / 2;
    let allocated0 = Prim.rts_total_allocation();
    let reclaimed0 = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    var result = 0;
    var i = 0;
    while (i < repetitions) {
      result += Prim.fixtureApply2<Nat, Nat, Nat>(call2, i, 1);
      i += 1;
    };
    checksum := result;
    let stopped = Prim.performanceCounter(0);
    {instructions = stopped - started; allocated = Prim.rts_total_allocation() - allocated0;
     reclaimed = Prim.rts_reclaimed() - reclaimed0; outputSize = 2}
  };
  public query func bytesResult() : async Blob { assert checksum == expected; "ok" };
}
