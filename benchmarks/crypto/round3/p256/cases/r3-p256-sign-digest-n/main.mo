import Prim "mo:⛔";
import P256 "mo:fast/P256";
persistent actor {
  transient let secret : Blob = "\c9\af\a9\d8\45\ba\75\16\6b\5c\21\57\67\b1\d6\93\4e\50\c3\db\36\e8\9b\12\7b\8a\62\2b\12\0f\67\21";
  transient let digest : Blob = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51";
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
    assert output == "\68\89\7a\78\df\51\05\8b\49\0c\60\12\25\1c\95\92\1a\bb\a9\6e\2e\48\8c\8c\c9\98\94\2e\44\0d\b9\b7\80\58\7f\b3\87\36\3a\1d\f2\c9\e8\3c\00\f8\ca\99\0f\c0\a5\5b\5e\47\09\46\49\9b\82\ca\3b\55\2a\87";
    output
  };
}
