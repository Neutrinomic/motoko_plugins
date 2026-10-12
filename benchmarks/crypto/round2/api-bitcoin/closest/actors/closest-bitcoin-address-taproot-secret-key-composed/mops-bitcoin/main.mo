import Prim "mo:⛔";
import A "mo:core/Array";
import V "mo:core/VarArray";
import J "mo:bitcoin/ec/Jacobi";
import C "mo:bitcoin/ec/Curves";
import U "mo:bitcoin/Common";
import H "mo:bitcoin/Hash";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let secret:Blob="\2a\51\39\14\cd\57\98\43\08\a5\bd\99\8d\f0\4d\36\37\12\8e\6e\a6\f4\90\6d\b6\7f\ae\c8\f1\68\ab\e2";
func scalar(bytes:Blob, allowZero:Bool):Nat {
  assert bytes.size()==32;
  let n=U.readBE256(Prim.blobToArray(bytes),0);
  assert n < C.secp256k1.r and (allowZero or n!=0);
  n
};
func tweakXOnlySecretKey(secret:Blob,tweak:Blob):Blob {
  let d=scalar(secret,false);
  let t=scalar(tweak,true);
  // This is the already-audited public Jacobi/Common composition from the
  // curve benchmark peer, with variable-time Nat/NAF reference arithmetic.
  let normalized:Nat=switch(J.toAffine(J.mulBase(d,C.secp256k1))) {
    case(#infinity(_)) Prim.trap("invalid secret");
    case(#point(_,y,_)) {if(y.value%2==0)d else C.secp256k1.r-d};
  };
  let sum=(normalized+t)%C.secp256k1.r;
  assert sum!=0;
  let bytes=V.repeat<Nat8>(0,32);
  U.writeBE256(bytes,0,sum);
  Prim.arrayToBlob(bytes.toArray())
};
func taprootSecretKey(secret:Blob,merkleRoot:?Blob):Blob {
  let d=scalar(secret,false);
  let encodedPublic=J.toBytes(J.mulBase(d,C.secp256k1),true);
  let internal=A.tabulate<Nat8>(32,func(i){encodedPublic[i+1]});
  let message=switch(merkleRoot){
    case(null)internal;
    case(?root){assert root.size()==32;A.concat(internal,Prim.blobToArray(root))};
  };
  let tweak=Prim.arrayToBlob(H.taggedHash(message,"TapTweak"));
  tweakXOnlySecretKey(secret,tweak)
};
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := taprootSecretKey(secret,null);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
