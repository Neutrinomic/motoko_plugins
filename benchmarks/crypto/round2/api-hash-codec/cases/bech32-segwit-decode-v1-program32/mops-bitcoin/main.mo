import Prim "mo:⛔";
import S "mo:bitcoin/Segwit";
import Array "mo:core/Array";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : (Text, S.WitnessProgram) = ("", {version = 0; program = []});
  transient let input : Text = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (S.decode(input)) { case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected result") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(Array.concat<Nat8>(Array.concat<Nat8>(Prim.blobToArray(Prim.encodeUtf8(result.0)), [0, result.1.version]), result.1.program)) };
}
