import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import S "mo:bitcoin/bitcoin/Script";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat8] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let data:[Nat8]=Prim.blobToArray("\d9\e4\0f\82\c1\48\b2\82\94\bf\c7\f3\28\b7\b3\b5\a7\6a\08\3a\aa\31\3d\ec\7b\88\c1\ff\de\5e\54\48");
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    assert data.size()==32;let encoded=S.toBytes([#opcode(#OP_1),#data(data)]);result := BA.tabulate<Nat8>(encoded.size()-1,func(i){encoded[i+1]});
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(result) };
}
