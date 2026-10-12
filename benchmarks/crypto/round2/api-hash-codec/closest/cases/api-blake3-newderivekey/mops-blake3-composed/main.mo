import Prim "mo:⛔";
import H "mo:blake3";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  
  func withFlags(state : H.Hasher, flags : Nat8) : H.Hasher {
    let chunk = state.chunk;
    {
      key = state.key; cvStackLen = state.cvStackLen; cvStack = state.cvStack;
      chunk = {
        cv = chunk.cv; chunkCounter = chunk.chunkCounter; buf = chunk.buf;
        bufLen = chunk.bufLen; blocksCompressed = chunk.blocksCompressed; flags;
      };
    }
  };
  func newDerive(context : Text) : H.Hasher {
    let contextState = withFlags(H.hasherInit(), Prim.natToNat8(H.DERIVE_KEY_CONTEXT));
    let contextKey = H.hasherFinalize(H.hasherUpdate(contextState, Prim.blobToArray(Prim.encodeUtf8(context))), 32);
    withFlags(H.hasherInitKeyed(contextKey), Prim.natToNat8(H.DERIVE_KEY_MATERIAL))
  };

 transient let context : Text = "BLAKE3 2019-12-27 16:29:52 test vectors context"; transient var state = H.hasherInit();
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    state := newDerive(context);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.arrayToBlob(H.hasherFinalize(state, 32)) };
}
