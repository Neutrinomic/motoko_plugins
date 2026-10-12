import Prim "mo:⛔";
import B "mo:fast/Bech32";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient var input : Blob = "";
  public func configure() : async () { input := "\07\14\01\0e\1b\08\15\02\0f\1c\09\16\03\10\1d\0a\17\04\11\1e\0b\18\05\12\1f\0c\19\06\13\00\0d\1a\07\14\01\0e\1b\08\15\02\0f"; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (B.convertBits(input, 5, 5, false)) { case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected benchmark error") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
