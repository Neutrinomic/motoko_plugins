import Prim "mo:⛔";
import P256 "mo:fast/P256";
persistent actor {
  transient let secret : Blob = "\c9\af\a9\d8\45\ba\75\16\6b\5c\21\57\67\b1\d6\93\4e\50\c3\db\36\e8\9b\12\7b\8a\62\2b\12\0f\67\21";
  transient let digest : Blob = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50";
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
    assert output == "\c6\75\c4\3e\82\9a\5e\83\8b\e6\01\45\15\bc\c7\d8\2f\b8\d3\05\3c\77\0d\32\d3\22\a9\e9\e3\55\30\e7\49\99\6e\b9\5b\9f\44\71\48\4b\96\cd\60\fe\f8\0a\14\f6\50\4e\d7\27\9e\13\34\04\a6\1e\1a\b8\ae\e5";
    output
  };
}
