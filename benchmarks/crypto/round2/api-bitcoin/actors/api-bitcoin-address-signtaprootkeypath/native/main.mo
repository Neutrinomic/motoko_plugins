import Prim "mo:⛔";
import M "mo:fast/Bitcoin/Address";
import BA "mo:core/Array";
import BB "mo:core/Blob";

persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let secret : Blob = "\2a\51\39\14\cd\57\98\43\08\a5\bd\99\8d\f0\4d\36\37\12\8e\6e\a6\f4\90\6d\b6\7f\ae\c8\f1\68\ab\e2";transient let digest : Blob="\e5\7b\f0\4d\66\bd\0a\44\6f\3f\55\d7\a0\f1\ae\84\e9\9e\74\7c\05\41\72\68\24\f3\b4\15\3e\27\d0\e0";transient let aux : Blob="\f6\bb\34\7e\a1\d3\a5\da\5e\ff\f7\3f\ed\1e\64\34\cb\0d\7d\d4\d9\99\8c\65\a0\5b\8a\0b\91\50\68\9f";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := unwrap(M.signTaprootKeyPath(secret,null,digest,aux));
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
