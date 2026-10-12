import Prim "mo:⛔";
import H "mo:fast/BLAKE3";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let chunks : [Blob] = []; transient var state = H.new();
  public func configure() : async () { state := H.new(); };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    for(chunk in chunks.vals()){state := switch(H.update(state,chunk)){case(#ok(value))value;case(#err(_))Prim.trap("unexpected error")}};result := switch(H.finalize(state)){case(#ok(value))value;case(#err(_))Prim.trap("unexpected error")};
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
