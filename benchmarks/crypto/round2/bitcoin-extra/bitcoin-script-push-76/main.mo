import Prim "mo:⛔";
import T "mo:fast/Bitcoin/Transaction";
import S "mo:fast/Bitcoin/Script";
persistent actor {
  transient var result : Blob = "";
  transient let input : Blob = "\07\14\21\2e\3b\48\55\62\6f\7c\89\96\a3\b0\bd\ca\d7\e4\f1\fe\0b\18\25\32\3f\4c\59\66\73\80\8d\9a\a7\b4\c1\ce\db\e8\f5\02\0f\1c\29\36\43\50\5d\6a\77\84\91\9e\ab\b8\c5\d2\df\ec\f9\06\13\20\2d\3a\47\54\61\6e\7b\88\95\a2\af\bc\c9\d6";
  public func configure() : async () {};
  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {
    let a=Prim.rts_total_allocation(); let r=Prim.rts_reclaimed(); let start=Prim.performanceCounter(0);
    let ?value=S.pushData(input) else Prim.trap("push"); result:=value;
    let stop=Prim.performanceCounter(0);let z=Prim.rts_total_allocation();let q=Prim.rts_reclaimed();
    {instructions=stop-start;allocated=z-a;reclaimed=q-r;outputSize=0}
  };
  public query func bytesResult() : async Blob { result };
}
