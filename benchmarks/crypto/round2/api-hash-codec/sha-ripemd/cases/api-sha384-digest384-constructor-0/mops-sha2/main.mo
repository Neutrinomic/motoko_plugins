import Prim "mo:⛔";
import H "mo:sha2/Sha512";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let input : Blob = "";
transient var state = H.Digest(#sha384);
  public func configure() : async () { state := H.Digest(#sha384); };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    state := H.Digest(#sha384);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { state.sum() };
}
