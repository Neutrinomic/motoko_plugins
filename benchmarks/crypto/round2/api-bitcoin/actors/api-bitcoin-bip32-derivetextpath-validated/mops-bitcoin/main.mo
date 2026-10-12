import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import B "mo:bitcoin/Bip32";
import VF "mo:bitcoin/ec/Affine";
import VC "mo:bitcoin/ec/Curves";
import VT "mo:core/Text";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : ?B.ExtendedPublicKey = null;
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let parent=some(B.parse("xpub661MyMwAqRbcFW31YEwpkMuc5THy2PSt5bDMsktWQcFF8syAmRUapSCGu8ED9W6oDMSgv6Zz8idoc4a6mr8BDzTJY47LJhkJ8UB7WEGuduB",null));
transient let parentFingerprint : [Nat8] = [0,0,0,0];
func validateNode(key:B.ExtendedPublicKey, fingerprint:[Nat8]) {
  assert key.chaincode.size()==32;
  assert fingerprint.size()==4;
  if(key.depth==0) { assert key.index==0 and fingerprint==[0,0,0,0] };
  assert key.key.size()==33;
  let point=some(VF.fromBytes(key.key,VC.secp256k1));
  let canonical=VF.toBytes(point,true);
  assert canonical==key.key;
};
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
transient let path="m/0/1";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    switch(path.chars().next()){case(?'m' or ?'M'){assert parent.depth==0};case(_) {}};let indices=some(strictPath(path));validateNode(parent,parentFingerprint);assert Prim.nat8ToNat(parent.depth)+indices.size()<=255;result := ?some(parent.derivePath(#array(indices)));
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.encodeUtf8(some(result).serialize()) };
}
