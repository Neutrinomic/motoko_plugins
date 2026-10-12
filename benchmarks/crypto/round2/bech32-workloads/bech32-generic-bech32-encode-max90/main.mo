import Prim "mo:⛔";
import B "mo:fast/Bech32";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Text = "";
  transient var hrp : Text = ""; transient var input : Blob = "";
  public func configure() : async () { hrp := "bc"; input := "\05\10\1b\06\11\1c\07\12\1d\08\13\1e\09\14\1f\0a\15\00\0b\16\01\0c\17\02\0d\18\03\0e\19\04\0f\1a\05\10\1b\06\11\1c\07\12\1d\08\13\1e\09\14\1f\0a\15\00\0b\16\01\0c\17\02\0d\18\03\0e\19\04\0f\1a\05\10\1b\06\11\1c\07\12\1d\08\13\1e\09\14\1f\0a\15"; };
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
