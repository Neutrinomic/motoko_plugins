import Prim "mo:⛔";
import H "mo:blake3";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let input : Blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024, func(i) {Prim.natToNat8(i % 251)}));
transient let key : Blob = "\77\68\61\74\73\20\74\68\65\20\45\6c\76\69\73\68\20\77\6f\72\64\20\66\6f\72\20\66\72\69\65\6e\64";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := H.keyed_hash(key,input);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
