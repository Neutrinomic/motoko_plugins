import Prim "mo:⛔";
import B "mo:fast/Base58";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let input : Text = "p881X97MA2C6x5DzRcvBz9YNvjEDs6mbmkxKtz6tEigKPkiVqjB2wJ8WiVrpvffqd4S2Pf1C9CVfZqbN81AZGrx2LvJjhAj9EnZTeVCnSELyzRyfjcV88fUfQKV74gEpZG4aw9ULf6JMRS6PELGtpz31ey8WK5PNZBsPpjjZq1nbv6GhDBcBFYD4A92NTEW7bs1vsNY8Vrfjs18ifFnjLnL1x3yGPfDkmtwRr3g6amCmaH53HkAtKBQcBPzsiHrHy73qbdFJA6zfEaqx5ytjjADzsZCyCuT5S3Eys5FuhLCLB34KUoRLksrRM3Kzoxyy9sXSLeNHzN51UqTFr25HNRbsy8KS5";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch(B.decode(input)){case(#ok b)b;case(#err _)Prim.trap("invalid independent vector")};
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
