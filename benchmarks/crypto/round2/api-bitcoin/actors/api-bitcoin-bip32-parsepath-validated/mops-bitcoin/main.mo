import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import B "mo:bitcoin/Bip32";
import VT "mo:core/Text";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Nat32] = [];
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};

func strictPath(path:Text):?[Nat32] {
  let segments=BA.fromIter(VT.split(path,#char '/'));
  if(segments.size()==0) return null;
  let start:Nat=if(segments[0]=="m" or segments[0]=="M")1 else 0;
  let size=segments.size()-start;
  if(size > 255)return null;
  if(size==0)return ?[];
  var normalized="";
  var i=start;
  while(i < segments.size()) {
    let s=segments[i];
    if(s.size()==0)return null;
    for(c in s.chars()) {if(c < '0' or c > '9')return null};
    if(i > start)normalized#="/";
    normalized#=s;
    i+=1;
  };
  let indices=switch(B.arrayPathFromString(normalized)){case(?v)v;case(null)return null};
  for(index in indices.values()) {if(index>=0x80000000)return null};
  ?indices
};
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := some(strictPath("m/0/1"));
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(BA.tabulate<Nat8>(result.size()*4,func(i){Prim.natToNat8(Prim.nat32ToNat(result[i/4] >> Prim.natToNat32((i%4)*8)) % 256)})) };
}
