import Prim "mo:⛔";
import Curve "mo:fast/Secp256k1";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient var key : ?Curve.PreparedSchnorrPublicKey = null;
  func unwrap<T>(value : Curve.Result<T>) : T { switch value { case (#ok x) x; case (#err _) { assert false; loop {} } } };
  func preparedKey() : Curve.PreparedSchnorrPublicKey { switch key { case (?x) x; case null { assert false; loop {} } } };
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := (if (unwrap(Curve.schnorrVerify("\f9\30\8a\01\92\58\c3\10\49\34\4f\85\f8\9d\52\29\b5\31\c8\45\83\6f\99\b0\86\01\f1\13\bc\e0\36\f9", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", "\e9\07\83\1f\80\84\8d\10\69\a5\37\1b\40\24\10\36\4b\df\1c\5f\83\07\b0\08\4c\55\f1\ce\2d\ca\82\15\25\f6\6a\4a\85\ea\8b\71\e4\82\a7\4f\38\2d\2c\e5\eb\ee\e8\fd\b2\17\2f\47\7d\f4\90\0d\31\05\36\c0"))) "\01" else "\00");
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
