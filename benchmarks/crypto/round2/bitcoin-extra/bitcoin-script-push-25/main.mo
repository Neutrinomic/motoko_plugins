import Prim "mo:⛔";
import T "mo:fast/Bitcoin/Transaction";
import S "mo:fast/Bitcoin/Script";
persistent actor {
  transient var result : Blob = "";
  transient let input : Blob = "\07\14\21\2e\3b\48\55\62\6f\7c\89\96\a3\b0\bd\ca\d7\e4\f1\fe\0b\18\25\32\3f";
  public func configure() : async () {};
  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {
    let a=Prim.rts_total_allocation(); let r=Prim.rts_reclaimed(); let start=Prim.performanceCounter(0);
    let ?value=S.pushData(input) else Prim.trap("push"); result:=value;
    let stop=Prim.performanceCounter(0);let z=Prim.rts_total_allocation();let q=Prim.rts_reclaimed();
    {instructions=stop-start;allocated=z-a;reclaimed=q-r;outputSize=0}
  };
  public query func bytesResult() : async Blob { result };
}
