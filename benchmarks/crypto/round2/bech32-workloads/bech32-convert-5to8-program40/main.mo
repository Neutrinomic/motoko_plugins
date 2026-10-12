import Prim "mo:⛔";
import B "mo:fast/Bech32";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient var input : Blob = "";
  public func configure() : async () { input := "\05\05\19\0b\16\01\02\0d\12\1b\0f\12\10\1c\0d\1a\00\0d\06\09\0b\17\11\07\0e\02\1c\10\04\12\1c\14\1b\14\13\06\1f\0e\00\01\09\0a\09\1d\18\09\0b\0e\16\1c\00\04\13\04\16\1b\04\11\16\1b\0d\1f\1a\08"; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (B.convertBits(input, 5, 8, false)) { case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected benchmark error") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
