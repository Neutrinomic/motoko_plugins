import Prim "mo:⛔";
import B "mo:fast/Base58";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let input : Text = "CqG9DvV6jefSeKBsyDqNbEtTApVZf4tgG7BV3Z7Kz3PApqd8aTJNzQ5Hcka5XkjfqDGMp9zgwU3vo1f84jbsyg1FPkMUj3i4mw4HQ2tE2FPUbMiPFp3qJTUF8zyieiv2VvCutbBBuih6J2eXvzPEXNuNbA7nRrhYkvazFaaQuubz5hBW5FBHhAPD4pt1WeBLTM9n8qGChdtBcQkzZHAHartozWZA2AMJCJuFS71xjUHXqKQQd7ZzMENjiuz92yuUR8XxLCa25jiFRPEKVFii6Azs33U8rHPbEVfQqnpc3URH8HioRCVgEg2diDUsu6iPAa47aMRy56v7TtfBRzicbhsenfWq5G";
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
