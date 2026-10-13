import Prim "mo:⛔";
import Ed25519 "mo:fast/Ed25519";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Ed25519.Result<Bool> = #err(#invalidSignature);
  transient var seed : Blob = "";
  transient var key : Blob = "";
  transient var message : Blob = "";
  transient var signature : Blob = "";
  public func configure() : async () { seed := "\5d\6e\7f\90\a1\b2\c3\d4\e5\f6\07\18\29\3a\4b\5c\6d\7e\8f\a0\b1\c2\d3\e4\f5\06\17\28\39\4a\5b\6c";
    key := "\9c\f4\65\7e\17\2f\50\63\40\18\ee\f0\6f\37\eb\6c\83\f2\0e\98\23\85\6f\fd\8d\b1\73\b9\1e\df\4d\ba";
    message := "\03\20\3d\5a\77\94\b1\ce\eb\08\25\42\5f\7c\99\b6\d3\f0\0d\2a\47\64\81\9e\bb\d8\f5\12\2f\4c\69\86";
    signature := "\40\46\6b\b9\16\f3\06\7b\80\a0\29\39\91\2a\f8\b2\db\83\4b\4f\79\89\5e\47\65\fc\77\1f\54\dc\25\51\f2\14\a1\93\e6\62\a4\b6\2c\b3\e1\98\97\da\9c\ff\e1\f4\9a\83\67\a6\b4\06\e9\40\41\e9\fd\e1\73\07";
    message := "\03\20\3d\5a\77\94\b1\ce\eb\08\25\42\5f\7c\99\b6\d3\f0\0d\2a\47\64\81\9e\bb\d8\f5\12\2f\4c\69\86\00"; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := Ed25519.verify(key, message, signature);
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
  public query func bytesResult() : async Blob { switch(result) { case (#ok true) "\01"; case (#ok false) "\00"; case (#err _) { assert false; "" } } };
}
