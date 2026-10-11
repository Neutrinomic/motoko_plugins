import Prim "mo:⛔";
import Map "Map";
actor {
type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
transient var count = 0;
transient var expected = 0;
transient var total = 0;
transient var overwritten = 0;
public func clear() : async () { total := 0; overwritten := 0 };
transient var mapNat32 : Map.Map<Nat32, Nat> = null;
transient var mapInt32 : Map.Map<Int32, Nat> = null;
public func configure(index : Nat) : async () {
  count := [1_000, 10_000, 100_000][index];
  mapNat32 := null; mapInt32 := null;
  var n = 0;
  while (n < count) {
    mapNat32 := Prim.pmap_add_static<Nat32, Nat>(mapNat32, Prim.natToNat32(n * 2), n);
    mapInt32 := Prim.pmap_add_static<Int32, Nat>(mapInt32, Prim.intToInt32(n * 2 - count), n);
    n += 1;
  };
};
public func Nat32getHit() : async Measurement {
  expected := 0;
  var n = 0;
  while (n < 1000) {
    expected += n % count;
    n += 1;
  };
  overwritten := 0;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc = 0;
  var i = 0;
  while (i < 1000) {
    let n = i % count;
    let key = Prim.natToNat32(n * 2);
    let ?value = Prim.pmap_get_static<Nat32, Nat>(mapNat32, key) else Prim.trap("missing"); acc += value;
    i += 1;
  };
  total := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
public func Nat32getMiss() : async Measurement {
  expected := 0;
  var n = 0;
  while (n < 1000) {
    expected += 1;
    n += 1;
  };
  overwritten := 0;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc = 0;
  var i = 0;
  while (i < 1000) {
    let n = i % count;
    let key = Prim.natToNat32(n * 2 + 1);
    assert Prim.pmap_get_static<Nat32, Nat>(mapNat32, key) == null; acc += 1;
    i += 1;
  };
  total := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
public func Nat32overwrite() : async Measurement {
  expected := 0;
  var n = 0;
  while (n < 1000) {
    expected += n % count + 1;
    n += 1;
  };
  overwritten := 1;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc = 0;
  var i = 0;
  while (i < 1000) {
    let n = i % count;
    let key = Prim.natToNat32(n * 2);
    mapNat32 := Prim.pmap_add_static<Nat32, Nat>(mapNat32, key, n + 1); acc += n + 1;
    i += 1;
  };
  total := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
public func Int32getHit() : async Measurement {
  expected := 0;
  var n = 0;
  while (n < 1000) {
    expected += n % count;
    n += 1;
  };
  overwritten := 0;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc = 0;
  var i = 0;
  while (i < 1000) {
    let n = i % count;
    let key = Prim.intToInt32(n * 2 - count);
    let ?value = Prim.pmap_get_static<Int32, Nat>(mapInt32, key) else Prim.trap("missing"); acc += value;
    i += 1;
  };
  total := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
public func Int32getMiss() : async Measurement {
  expected := 0;
  var n = 0;
  while (n < 1000) {
    expected += 1;
    n += 1;
  };
  overwritten := 0;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc = 0;
  var i = 0;
  while (i < 1000) {
    let n = i % count;
    let key = Prim.intToInt32(n * 2 + 1 - count);
    assert Prim.pmap_get_static<Int32, Nat>(mapInt32, key) == null; acc += 1;
    i += 1;
  };
  total := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
public func Int32overwrite() : async Measurement {
  expected := 0;
  var n = 0;
  while (n < 1000) {
    expected += n % count + 1;
    n += 1;
  };
  overwritten := 2;
  let beforeAllocation = Prim.rts_total_allocation();
  let beforeReclaimed = Prim.rts_reclaimed();
  let started = Prim.performanceCounter(0);
  var acc = 0;
  var i = 0;
  while (i < 1000) {
    let n = i % count;
    let key = Prim.intToInt32(n * 2 - count);
    mapInt32 := Prim.pmap_add_static<Int32, Nat>(mapInt32, key, n + 1); acc += n + 1;
    i += 1;
  };
  total := acc;
  let ended = Prim.performanceCounter(0);
  let afterAllocation = Prim.rts_total_allocation();
  let afterReclaimed = Prim.rts_reclaimed();
  {instructions = ended - started; allocated = afterAllocation - beforeAllocation;
   reclaimed = afterReclaimed - beforeReclaimed; outputSize = 2}
};
public query func bytesResult() : async Blob { assert total == expected; var i = 0; while (i < 1000 and overwritten != 0) { let n = i % count; if (overwritten == 1) { assert Prim.pmap_get_static<Nat32, Nat>(mapNat32, Prim.natToNat32(n * 2)) == ?(n + 1) } else { assert Prim.pmap_get_static<Int32, Nat>(mapInt32, Prim.intToInt32(n * 2 - count)) == ?(n + 1) }; i += 1 }; "ok" };
}
