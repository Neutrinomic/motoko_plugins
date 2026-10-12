import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import F "mo:bitcoin/ec/Affine";
import C "mo:bitcoin/ec/Curves";
import H "mo:bitcoin/Hash";
import S "mo:bitcoin/Segwit";
import P "mo:bitcoin/bitcoin/P2pkh";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Text = "";
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let key : [Nat8] = Prim.blobToArray("\03\3d\e4\db\4d\ba\29\cd\84\f7\60\25\cc\e8\ee\80\5d\b7\8a\91\62\63\3d\e0\a8\23\09\ba\4d\4b\dd\a0\94");
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    let point=some(F.fromBytes(key,C.secp256k1));assert F.isOnCurve(point);result := P.deriveAddress(#Mainnet,(key,C.secp256k1));
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.encodeUtf8(result) };
}
