import Prim "mo:⛔";
import S "mo:fast/Segwit";
import Array "mo:core/Array";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : S.Decoded = { hrp = ""; version = 0; program = "" };
  transient var input : Text = "";
  public func configure() : async () { input := "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0"; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (S.decode(input)) { case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected benchmark error") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(Array.concat<Nat8>(Array.concat<Nat8>(Prim.blobToArray(Prim.encodeUtf8(result.hrp)), [0, result.version]), Prim.blobToArray(result.program))) };
}
