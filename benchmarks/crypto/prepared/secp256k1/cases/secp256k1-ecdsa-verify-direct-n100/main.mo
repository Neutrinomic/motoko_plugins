import Prim "mo:⛔";
import Curve "mo:fast/Secp256k1";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient var key : ?Curve.PreparedPublicKey = null;
  func unwrap<T>(value : Curve.Result<T>) : T { switch value { case (#ok x) x; case (#err _) { assert false; loop {} } } };
  func preparedKey() : Curve.PreparedPublicKey { switch key { case (?x) x; case null { assert false; loop {} } } };
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    var remaining = 100; while (remaining > 0) { result := (if (unwrap(Curve.verifyPrehash("\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98", "\af\2b\db\e1\aa\9b\6e\c1\e2\ad\e1\d6\94\f4\1f\c7\1a\83\1d\02\68\e9\89\15\62\11\3d\8a\62\ad\d1\bf", "\58\db\65\7b\cd\63\10\38\be\a0\7b\49\41\17\2f\01\67\ac\a9\8f\12\b5\5e\31\76\bd\1c\35\43\5d\65\01\3a\78\e7\3d\8f\f8\ab\55\4e\13\c1\0f\63\90\d8\1a\88\2f\91\94\5d\62\75\49\38\82\67\61\70\b5\3a\57"))) "\01" else "\00"); remaining -= 1; };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };

  public query func memory() : async {
    heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat
  } {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
      totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
  public query func bytesResult() : async Blob { result };
}
