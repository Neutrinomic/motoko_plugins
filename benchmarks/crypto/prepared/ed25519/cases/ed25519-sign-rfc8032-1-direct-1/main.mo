import Prim "mo:⛔";
import Ed "mo:fast/Ed25519";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Ed.Result<Blob> = #err(#invalidSignature);

  transient var seed : Blob = "";
  transient var key : Blob = "";
  transient var message : Blob = "";
  transient var signature : Blob = "";
  func must<T>(value : Ed.Result<T>) : T {
    switch value { case (#ok result) result; case (#err _) Prim.trap("unexpected fixture error") }
  };
  public func configure() : async () { seed := "\9d\61\b1\9d\ef\fd\5a\60\ba\84\4a\f4\92\ec\2c\c4\44\49\c5\69\7b\32\69\19\70\3b\ac\03\1c\ae\7f\60";
    key := "\d7\5a\98\01\82\b1\0a\b7\d5\4b\fe\d3\c9\64\07\3a\0e\e1\72\f3\da\a6\23\25\af\02\1a\68\f7\07\51\1a";
    message := "";
    signature := "\e5\56\43\00\c3\60\ac\72\90\86\e2\cc\80\6e\82\8a\84\87\7f\1e\b8\e5\d9\74\d8\73\e0\65\22\49\01\55\5f\b8\82\15\90\a3\3b\ac\c6\1e\39\70\1c\f9\b4\6b\d2\5b\f5\f0\59\5b\be\24\65\51\41\43\8e\7a\10\0b"; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := Ed.sign(seed, message);
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
  public query func bytesResult() : async Blob { must(result) };
}
