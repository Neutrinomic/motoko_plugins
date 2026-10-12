import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import B "mo:bitcoin/Bip32";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat32] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};

  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := some(B.arrayPathFromString("m/0/1"));
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(BA.tabulate<Nat8>(result.size()*4,func(i){Prim.natToNat8(Prim.nat32ToNat(result[i/4] >> Prim.natToNat32((i%4)*8)) % 256)})) };
}
