import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import P "mo:bitcoin/bitcoin/P2pkh";
import A "mo:bitcoin/bitcoin/Address";
import S "mo:bitcoin/bitcoin/Script";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat8] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};

  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    let decoded=unwrap(P.decodeAddress("1MDxuFtB1R7AqqZxN7ugSwExCmuyhNyJyK"));assert decoded.network == #Mainnet;let s=unwrap(A.scriptPubKey(#p2pkh("1MDxuFtB1R7AqqZxN7ugSwExCmuyhNyJyK")));let bytes=S.toBytes(s);result := BA.tabulate<Nat8>(bytes.size()-1,func(i){bytes[i+1]});
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(result) };
}
