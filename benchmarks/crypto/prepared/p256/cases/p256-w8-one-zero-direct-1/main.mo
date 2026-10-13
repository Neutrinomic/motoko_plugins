import Prim "mo:⛔";
import P256 "mo:fast/P256";
persistent actor {
  transient let publicKey : Blob = "\03\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96";
  transient let digest : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
  transient let signature : Blob = "\0e\6b\3b\b6\8d\65\aa\64\51\04\de\3a\bb\94\cb\c6\f5\68\e2\d5\5e\a5\11\d0\e6\d3\00\e1\77\00\21\59\16\7a\fc\0b\51\8b\d6\38\53\cc\c1\b5\29\2e\27\02\4c\55\7c\89\24\ca\3d\ec\81\d5\96\51\b9\02\17\94";
  transient var result : P256.Result<Bool> = #ok false;
  transient var prepared : ?P256.PreparedPublicKey = null;
  public func configure() : async () {  };
  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
     var i = 0; while (i < 1) { result := P256.verifyPrehash(publicKey, digest, signature); i += 1 };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 1}
  };
  public query func memory() : async {heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat} {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
      totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
  public query func bytesResult() : async Blob {
    let answer = result;
    let #ok(value) = answer else Prim.trap("verification error");
    assert value == true;
    if (value) "\01" else "\00"
  };
}
