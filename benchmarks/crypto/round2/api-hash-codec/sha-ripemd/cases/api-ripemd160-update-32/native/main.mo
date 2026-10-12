import Prim "mo:⛔";
import H "mo:fast/RIPEMD160";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let input : Blob = "\00\01\02\03\04\05\06\07\08\09\0a\0b\0c\0d\0e\0f\10\11\12\13\14\15\16\17\18\19\1a\1b\1c\1d\1e\1f";
transient var state : Blob = "";
transient var next : ?Blob = null;
func unwrap(value : ?Blob) : Blob { switch value { case (?v) v; case null Prim.trap("invalid state"); } };
  public func configure() : async () { state := H.init();state := unwrap(H.update(state, "\00\01\02\03\04\05\06\07\08\09\0a\0b\0c\0d\0e\0f\10")); };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    next := H.update(state, input);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { assert unwrap(H.finalize(state)) == "\c8\7d\a6\f8\7a\65\cb\cb\c4\b0\2b\fd\6d\01\e2\6f\80\47\b5\c4"; unwrap(H.finalize(unwrap(next))) };
}
