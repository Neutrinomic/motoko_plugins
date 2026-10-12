import Prim "mo:⛔";
import T "mo:fast/Bitcoin/Transaction";
import S "mo:fast/Bitcoin/Script";
persistent actor {
  transient var result : Blob = "";
  transient let input : Blob = "\01\0c\17\22\2d\38\43\4e\59\64\6f\7a\85\90\9b\a6\b1\bc\c7\d2";
  public func configure() : async () {};
  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {
    let a=Prim.rts_total_allocation(); let r=Prim.rts_reclaimed(); let start=Prim.performanceCounter(0);
    let ?value=S.p2sh(input) else Prim.trap("script"); result:=value;
    let stop=Prim.performanceCounter(0);let z=Prim.rts_total_allocation();let q=Prim.rts_reclaimed();
    {instructions=stop-start;allocated=z-a;reclaimed=q-r;outputSize=0}
  };
  public query func bytesResult() : async Blob { result };
}
