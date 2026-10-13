import Prim "mo:⛔";
import P256 "mo:fast/P256";
persistent actor {
  transient let secret : Blob = "\c9\af\a9\d8\45\ba\75\16\6b\5c\21\57\67\b1\d6\93\4e\50\c3\db\36\e8\9b\12\7b\8a\62\2b\12\0f\67\21";
  transient let digest : Blob = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff";
  transient var result : P256.Result<Blob> = #ok("");
  public func configure() : async () {};
  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {
    let beforeAllocated = Prim.rts_total_allocation();
    let beforeReclaimed = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := P256.signPrehash(secret, digest);
    let instructions = Prim.performanceCounter(0) - start;
    {instructions; allocated = Prim.rts_total_allocation() - beforeAllocated;
      reclaimed = Prim.rts_reclaimed() - beforeReclaimed; outputSize = 64}
  };
  // Observed outside the timed operation.
  public query func memory() : async {
    heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat
  } {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
     totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
  public query func bytesResult() : async Blob {
    let #ok(output) = result else Prim.trap("signature error");
    assert output == "\1f\2a\db\c5\4b\88\76\4c\27\9f\68\9f\c9\50\59\59\fc\9e\73\e8\0d\c2\08\89\a4\e0\be\91\86\5d\e7\5b\9d\10\9b\65\e2\fb\fc\0a\e4\2b\a0\b2\e5\f0\36\70\cd\45\8c\ff\48\82\df\67\83\f3\d9\3d\60\7d\17\55";
    output
  };
}
