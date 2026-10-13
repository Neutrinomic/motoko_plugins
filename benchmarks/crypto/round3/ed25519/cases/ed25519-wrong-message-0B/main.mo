import Prim "mo:⛔";
import Ed25519 "mo:fast/Ed25519";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Ed25519.Result<Bool> = #err(#invalidSignature);
  transient var seed : Blob = "";
  transient var key : Blob = "";
  transient var message : Blob = "";
  transient var signature : Blob = "";
  public func configure() : async () { seed := "\00\11\22\33\44\55\66\77\88\99\aa\bb\cc\dd\ee\ff\10\21\32\43\54\65\76\87\98\a9\ba\cb\dc\ed\fe\0f";
    key := "\e5\48\22\84\bb\7e\f3\45\cf\2f\79\65\fd\35\4f\6a\7d\c6\32\d2\e9\65\83\56\e8\c2\ee\71\dd\18\4d\a3";
    message := "";
    signature := "\35\da\82\0e\18\b4\86\75\60\0e\64\d5\69\8f\99\37\01\a7\e1\5e\c9\b4\3b\3c\8b\56\36\f5\e1\02\a9\d8\9a\8d\9c\94\11\11\4d\0a\b1\50\ba\46\45\26\9c\9b\14\7d\f1\5e\e2\d0\02\74\95\83\6c\c2\51\60\80\0b";
    message := "\00"; };
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
