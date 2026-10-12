import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import F "mo:bitcoin/ec/Affine";
import C "mo:bitcoin/ec/Curves";
import B "mo:bitcoin/Bip32";
import H "mo:bitcoin/Hash";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat8] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let key:[Nat8]=Prim.blobToArray("\03\cb\ca\a9\c9\8c\87\7a\26\97\7d\00\82\5c\95\6a\23\8e\8d\dd\fb\d3\22\cc\e4\f7\4b\0b\5b\d6\ac\e4\a7");transient let chain:[Nat8]=Prim.blobToArray("\60\49\9f\80\1b\89\6d\83\17\9a\43\74\ae\b7\82\2a\ae\ac\ea\a0\db\1f\85\ee\3e\90\4c\4d\ef\bd\96\89");
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    let point=some(F.fromBytes(key,C.secp256k1));assert F.isOnCurve(point);let h=H.hash160(key);result := BA.tabulate<Nat8>(4,func(i){h[i]});
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(result) };
}
