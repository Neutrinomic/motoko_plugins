import Prim "mo:⛔";
import B "mo:fast/Base58Check";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let input : Text = "13p53kFicsFQWKrmyXHm5KJdnpR1JtA12efDMRUz1VycEJUPzYEakyiCz8m2iX9zJjNcrMfbSo3vMyjyJ9qmLdg8eK6wgAcYXrXd9xLCCReKp43";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (B.decode(input)) { case (#ok(value)) value; case (#err(_)) Prim.trap("unexpected result") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
