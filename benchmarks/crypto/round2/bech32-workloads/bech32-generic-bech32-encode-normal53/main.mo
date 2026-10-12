import Prim "mo:⛔";
import B "mo:fast/Bech32";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Text = "";
  transient var hrp : Text = ""; transient var input : Blob = "";
  public func configure() : async () { hrp := "bc"; input := "\03\0a\11\18\1f\06\0d\14\1b\02\09\10\17\1e\05\0c\13\1a\01\08\0f\16\1d\04\0b\12\19\00\07\0e\15\1c\03\0a\11\18\1f\06\0d\14\1b\02\09\10\17\1e\05\0c\13\1a\01\08\0f"; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (B.encode(hrp, input, #bech32)) { case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected benchmark error") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.encodeUtf8(result) };
}
