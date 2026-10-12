import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import H "mo:bitcoin/Hash";
import U "mo:bitcoin/ByteUtils";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat8] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let rawScript:[Nat8]=Prim.blobToArray("\20\3d\e4\db\4d\ba\29\cd\84\f7\60\25\cc\e8\ee\80\5d\b7\8a\91\62\63\3d\e0\a8\23\09\ba\4d\4b\dd\a0\94\ac");transient let leafVersion:Nat8=0xc0;
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    assert leafVersion & 1 == 0;assert rawScript.size()<=0xffff_ffff_ffff_ffff;result := H.taggedHash(BA.concat<Nat8>([leafVersion],BA.concat<Nat8>(U.writeVarint(rawScript.size()),rawScript)),"TapLeaf");
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(result) };
}
