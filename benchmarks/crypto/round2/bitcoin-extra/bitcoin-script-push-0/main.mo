import Prim "mo:⛔";
import T "mo:fast/Bitcoin/Transaction";
import S "mo:fast/Bitcoin/Script";
persistent actor {
  transient var result : Blob = "";
  transient let input : Blob = "";
  public func configure() : async () {};
  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {
    let a=Prim.rts_total_allocation(); let r=Prim.rts_reclaimed(); let start=Prim.performanceCounter(0);
    let ?value=S.pushData(input) else Prim.trap("push"); result:=value;
    let stop=Prim.performanceCounter(0);let z=Prim.rts_total_allocation();let q=Prim.rts_reclaimed();
    {instructions=stop-start;allocated=z-a;reclaimed=q-r;outputSize=0}
  };
  public query func bytesResult() : async Blob { result };
}
