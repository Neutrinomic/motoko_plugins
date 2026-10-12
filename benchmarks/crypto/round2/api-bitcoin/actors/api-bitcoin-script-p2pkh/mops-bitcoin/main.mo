import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import S "mo:bitcoin/bitcoin/Script";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat8] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};

  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    let encoded=S.toBytes([#opcode(#OP_DUP),#opcode(#OP_HASH160),#data(Prim.blobToArray("\dd\d6\2b\c6\c2\57\00\5b\db\3b\f4\8a\ec\61\84\d5\23\34\24\9b")),#opcode(#OP_EQUALVERIFY),#opcode(#OP_CHECKSIG)]);result := BA.tabulate<Nat8>(encoded.size()-1,func(i){encoded[i+1]});
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(result) };
}
