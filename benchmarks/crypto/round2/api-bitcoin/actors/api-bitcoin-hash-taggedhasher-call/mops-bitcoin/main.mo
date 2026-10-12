import Prim "mo:⛔";
import BA "mo:core/Array";
import BB "mo:core/Blob";
import H "mo:sha2/Sha256";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
func taggedHasher(tag:Text) : Blob -> Blob {
let tagHash=H.fromBlob(#sha256,Prim.encodeUtf8(tag));
func(input:Blob):Blob {let d=H.Digest(#sha256);d.writeBlob(tagHash);d.writeBlob(tagHash);d.writeBlob(input);d.sum()}
};transient let input : Blob = "\e5\7b\f0\4d\66\bd\0a\44\6f\3f\55\d7\a0\f1\ae\84\e9\9e\74\7c\05\41\72\68\24\f3\b4\15\3e\27\d0\e0";transient var cached=taggedHasher("TapTweak");
  public func configure() : async () { cached := taggedHasher("TapTweak"); };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := cached(input);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
