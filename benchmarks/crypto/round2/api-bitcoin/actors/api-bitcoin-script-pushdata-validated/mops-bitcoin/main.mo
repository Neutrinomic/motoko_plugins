import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import S "mo:bitcoin/bitcoin/Script";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat8] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let data:[Nat8]=Prim.blobToArray("\00\01\02\03\04\05\06\07\08\09\0a\0b\0c\0d\0e\0f\10\11\12\13\14\15\16\17\18\19\1a\1b\1c\1d\1e\1f\20\21\22\23\24\25\26\27\28\29\2a\2b\2c\2d\2e\2f\30\31\32\33\34\35\36\37\38\39\3a\3b\3c\3d\3e\3f\40\41\42\43\44\45\46\47\48\49\4a\4b\4c\4d\4e\4f");func build(data:[Nat8]):[Nat8] {
let n=data.size();assert n<=0xffff_ffff;
let instructions:S.Script=if(n==0){[#opcode(#OP_0)]}
else if(n==1 and data[0]==0x81){[#opcode(#OP_1NEGATE)]}
else if(n==1 and data[0]>=1 and data[0]<=16) {
let op:S.Opcode=switch(data[0]) {case(1)#OP_1;case(2)#OP_2;case(3)#OP_3;case(4)#OP_4;case(5)#OP_5;case(6)#OP_6;case(7)#OP_7;case(8)#OP_8;case(9)#OP_9;case(10)#OP_10;case(11)#OP_11;case(12)#OP_12;case(13)#OP_13;case(14)#OP_14;case(15)#OP_15;case(_)#OP_16};[#opcode(op)]
} else if(n < 76){[#data(data)]} else if(n<=255){[#opcode(#OP_PUSHDATA1),#data(data)]} else if(n<=65535){[#opcode(#OP_PUSHDATA2),#data(data)]} else { [#opcode(#OP_PUSHDATA4),#data(data)] };
let encoded=S.toBytes(instructions);
let start:Nat=if(encoded[0] < 253)1 else if(encoded[0]==253)3 else if(encoded[0]==254)5 else 9;
BA.tabulate<Nat8>(encoded.size()-start,func(i){encoded[start+i]})
};
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := build(data);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(result) };
}
