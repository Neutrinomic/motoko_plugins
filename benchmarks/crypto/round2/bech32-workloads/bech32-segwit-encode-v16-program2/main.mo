import Prim "mo:⛔";
import S "mo:fast/Segwit";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Text = "";
  transient var hrp : Text = ""; transient var version : Nat8 = 0; transient var input : Blob = "";
  public func configure() : async () { hrp := "bc"; version := 16; input := "\75\1e"; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (S.encode(hrp, version, input)) { case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected benchmark error") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.encodeUtf8(result) };
}
