import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import S "mo:bitcoin/bitcoin/Script";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat8] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let data:[Nat8]=Prim.blobToArray("\e5\7b\f0\4d\66\bd\0a\44\6f\3f\55\d7\a0\f1\ae\84\e9\9e\74\7c\05\41\72\68\24\f3\b4\15\3e\27\d0\e0");transient let version:Nat8=2;
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    assert version<=16;assert data.size()>=2 and data.size()<=40;if(version==0){assert data.size()==20 or data.size()==32};let opcode:S.Opcode=switch(version){case(0)#OP_0;case(1)#OP_1;case(2)#OP_2;case(3)#OP_3;case(4)#OP_4;case(5)#OP_5;case(6)#OP_6;case(7)#OP_7;case(8)#OP_8;case(9)#OP_9;case(10)#OP_10;case(11)#OP_11;case(12)#OP_12;case(13)#OP_13;case(14)#OP_14;case(15)#OP_15;case(_)#OP_16};let encoded=S.toBytes([#opcode(opcode),#data(data)]);result := BA.tabulate<Nat8>(encoded.size()-1,func(i){encoded[i+1]});
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(result) };
}
