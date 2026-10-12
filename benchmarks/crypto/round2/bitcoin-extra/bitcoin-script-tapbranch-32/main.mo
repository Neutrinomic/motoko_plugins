import Prim "mo:⛔";
import T "mo:fast/Bitcoin/Transaction";
import S "mo:fast/Bitcoin/Script";
persistent actor {
  transient var result : Blob = "";
  transient let left : Blob = "\36\0f\84\03\59\42\24\3c\6a\36\53\7a\e2\f8\67\34\85\e6\c0\44\55\a0\a8\5a\0d\b1\96\90\f2\54\14\80";
 transient let right : Blob = "\27\04\2f\4e\6e\ca\7d\0b\2a\7e\e4\02\6d\f2\ec\fa\51\d3\33\9e\6d\12\2a\a0\99\11\8e\cd\85\63\ba\d9";
  public func configure() : async () {};
  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {
    let a=Prim.rts_total_allocation(); let r=Prim.rts_reclaimed(); let start=Prim.performanceCounter(0);
    let ?value=S.tapBranchHash(left,right) else Prim.trap("tapbranch"); result:=value;
    let stop=Prim.performanceCounter(0);let z=Prim.rts_total_allocation();let q=Prim.rts_reclaimed();
    {instructions=stop-start;allocated=z-a;reclaimed=q-r;outputSize=0}
  };
  public query func bytesResult() : async Blob { result };
}
