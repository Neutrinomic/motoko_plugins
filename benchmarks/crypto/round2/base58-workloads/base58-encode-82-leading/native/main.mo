import Prim "mo:⛔";
import B "mo:fast/Base58";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Text = "";
  transient let input : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\e2\65\e8\6b\ee\71\f4\77\fa\7d\00\83\06\89\0c\8f\12\95\18\9b\1e\a1\24\a7\2a\ad\30\b3\36\b9\3c\bf\42\c5\48\cb\4e\d1\54\d7\5a\dd\60\e3\66\e9\6c\ef\72\f5\78\fb\7e\01\84";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := B.encode(input);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.encodeUtf8(result) };
}
