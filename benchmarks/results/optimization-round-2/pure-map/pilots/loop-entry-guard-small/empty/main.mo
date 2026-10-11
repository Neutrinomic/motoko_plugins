import Prim "mo:⛔";
import Core "mo:core/pure/Map";
import Map "mo:pure-map/Map";
actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var coreInput : Core.Map<Nat64, Nat> = Core.empty();
  transient var pluginInput : Map.Map<Nat64, Nat> = Map.empty();
  transient var result : ?Nat = null;
  func compare(a : Nat64, b : Nat64) : Map.Order { if (a < b) #less else if (a == b) #equal else #greater };
  public func configure(index : Nat) : async () { assert index == 0; coreInput := Core.empty(); pluginInput := Map.empty() };
  public func clear() : async () { result := null };
  public query func bytesResult() : async Blob { assert result == null; "ok" };
  public func bench_core() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    var i = 0;
    while (i < 64) { result := Core.get(coreInput, compare, (42 : Nat64)); i += 1 };
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 2 }
  };
  public func bench_plugin_custom() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    var i = 0;
    while (i < 64) { result := Map.get(pluginInput, compare, (42 : Nat64)); i += 1 };
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 2 }
  };
  public func bench_plugin_static() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    var i = 0;
    while (i < 64) { result := Map.getNat64(pluginInput, (42 : Nat64)); i += 1 };
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 2 }
  };
}
