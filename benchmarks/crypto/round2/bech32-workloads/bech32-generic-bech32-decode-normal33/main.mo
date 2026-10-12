import Prim "mo:⛔";
import B "mo:fast/Bech32";
import Array "mo:core/Array";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : B.Decoded = { hrp = ""; data = ""; encoding = #bech32 };
  transient var input : Text = "";
  public func configure() : async () { input := "bc1qpzry9x8gf2tvdw0s3jn54khce6mua7lqe3tp0e"; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (B.decode(input)) { case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected benchmark error") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(Array.concat<Nat8>(Array.concat<Nat8>(Prim.blobToArray(Prim.encodeUtf8(result.hrp)), [0, if (result.encoding == #bech32) 0 else 1]), Prim.blobToArray(result.data))) };
}
