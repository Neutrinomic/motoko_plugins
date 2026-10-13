import Prim "mo:⛔";
import P256 "mo:fast/P256";
persistent actor {
  transient let publicKey : Blob = "\02\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96";
  transient let digest : Blob = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff";
  transient let signature : Blob = "\77\b4\7b\05\c7\ef\c7\af\6d\a2\28\f9\97\27\ae\7c\f6\fc\3a\a8\0c\36\66\3e\c4\a5\6b\2f\7a\a3\2f\89\bc\70\ca\0c\1e\8f\45\30\ed\6e\cf\30\88\a1\f4\7d\ad\8b\cf\10\fd\61\e1\ff\72\7d\d7\7b\14\78\10\b5";
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
