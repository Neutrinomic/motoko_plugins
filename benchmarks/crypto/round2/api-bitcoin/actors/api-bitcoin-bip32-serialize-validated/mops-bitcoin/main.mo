import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import B "mo:bitcoin/Bip32";
import VF "mo:bitcoin/ec/Affine";
import VC "mo:bitcoin/ec/Curves";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Text = "";
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
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    validateNode(parent,parentFingerprint);result := parent.serialize();
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.encodeUtf8(result) };
}
