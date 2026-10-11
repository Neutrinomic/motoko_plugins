import Prim "mo:⛔";
import SHA256 "mo:sha2/Sha256";
actor {
  type Measurement = { instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat };
  transient var bytes : Blob = "";
  transient var output : Blob = "";
  public func configure(index : Nat) : async () {
    let sizes : [Nat] = [0, 1, 31, 32, 33, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 1024, 65536, 1048576];
    var state : Nat32 = 0x9e37_79b9;
    bytes := Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(sizes[index], func(_) {
      state := state ^ (state << 13);
      state := state ^ (state >> 17);
      state := state ^ (state << 5);
      Prim.natToNat8(Prim.nat32ToNat(state & 255))
    }));
  };
  public func clear() : async () { output := "" };
  public query func bytesResult() : async Blob { output };
  public func plugin() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    output := Prim.sha256(bytes);
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = output.size() }
  };
  public func native() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    output := SHA256.fromBlob(#sha256, bytes);
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = output.size() }
  };
}
