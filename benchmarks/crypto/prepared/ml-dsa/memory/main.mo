import MLDSA "mo:fast/MLDSA";
import Prim "mo:⛔";

// One identical Wasm serves every mode. All modes retain the same canonical
// inputs and equal-capacity root arrays; only the prepared objects differ.
persistent actor {
  type Configuration = {
    mode : Nat8; // 0 = no cache, 1 = public caches, 2 = secret caches.
    count : Nat;
    seed : Blob;
    publicKey : Blob;
    message : Blob;
    context : Blob;
    signature : Blob;
  };

  type Snapshot = {
    heapOccupiedBytes : Nat;
    totalAllocationBytes : Nat;
    reclaimedBytes : Nat;
    maxObservedPostGcHeapBytes : Nat;
    wasmMemoryBytes : Nat;
    collectorInstructions : Nat;
    mutatorInstructions : Nat;
    rootCount : Nat;
    configuredCount : Nat;
    mode : Nat8;
    phase : Nat8; // 0 = new, 1 = retained, 2 = dropped.
  };

  transient var configuration : ?Configuration = null;
  transient var publicKeys : [var ?MLDSA.PreparedPublicKey] = [var];
  transient var secretKeys : [var ?MLDSA.PreparedSecretKey] = [var];
  transient var configuredCount = 0;
  transient var mode : Nat8 = 0;
  transient var phase : Nat8 = 0;
  transient var rootCount = 0;
  transient var pressureRound = 0;
  transient var pressureChecksum = 0;

  func unwrap<T>(result : MLDSA.Result<T>) : T {
    switch (result) {
      case (#ok value) value;
      case (#err error) Prim.trap(debug_show error);
    }
  };

  public func configure(input : Configuration) : async () {
    assert phase == 0;
    assert input.mode <= 2;
    assert input.count > 0 and input.count <= 128;
    assert input.seed.size() == 32 and input.publicKey.size() == 1312;
    assert input.signature.size() == 2420 and input.context.size() <= 255;
    configuration := ?input;
    mode := input.mode;
    configuredCount := input.count;
    // Allocate both arrays in all modes. Keep their capacities after drop so
    // the comparison isolates prepared objects and their option wrappers.
    publicKeys := Prim.Array_init<?MLDSA.PreparedPublicKey>(input.count, null);
    secretKeys := Prim.Array_init<?MLDSA.PreparedSecretKey>(input.count, null);
    var i = 0;
    while (i < input.count) {
      if (input.mode == 1) {
        publicKeys[i] := ?unwrap(MLDSA.preparePublicKey(input.publicKey));
        rootCount += 1;
      } else if (input.mode == 2) {
        secretKeys[i] := ?unwrap(MLDSA.prepareSecretKey(input.seed));
        rootCount += 1;
      };
      i += 1;
    };
    phase := 1;
  };

  // Each message allocates a 32 MiB payload plus its array header, then drops
  // it. Four identical calls per stage move allocation across the 64 MiB RTS
  // partition boundary. A forced increment is not assumed to finish a cycle.
  public func pressure() : async () {
    assert phase != 0;
    let garbage = Prim.Array_init<Nat>(4_194_304, pressureRound);
    pressureChecksum := garbage[0] + garbage[garbage.size() - 1];
    pressureRound += 1;
  };

  public func drop() : async () {
    assert phase == 1;
    var i = 0;
    while (i < configuredCount) {
      publicKeys[i] := null;
      secretKeys[i] := null;
      i += 1;
    };
    rootCount := 0;
    phase := 2;
  };

  // Queries avoid adding verification/signing garbage to committed update
  // state. Check every rooted object after collection, not merely one alias.
  public query func verifyRetained() : async Bool {
    let input = switch (configuration) { case (?value) value; case null Prim.trap("not configured") };
    assert pressureRound == 0 or pressureChecksum == 2 * (pressureRound - 1);
    var i = 0;
    while (i < configuredCount) {
      if (phase == 1 and mode == 1) {
        let key = switch (publicKeys[i]) { case (?value) value; case null Prim.trap("missing public key") };
        assert MLDSA.verifyPrepared(key, input.message, input.signature, input.context) == #ok(true);
        switch (secretKeys[i]) { case null {}; case (?_) Prim.trap("unexpected secret key") };
      } else if (phase == 1 and mode == 2) {
        let key = switch (secretKeys[i]) { case (?value) value; case null Prim.trap("missing secret key") };
        assert MLDSA.signPrepared(key, input.message, input.context) == #ok(input.signature);
        switch (publicKeys[i]) { case null {}; case (?_) Prim.trap("unexpected public key") };
      } else {
        switch (publicKeys[i]) { case null {}; case (?_) Prim.trap("public key retained after drop") };
        switch (secretKeys[i]) { case null {}; case (?_) Prim.trap("secret key retained after drop") };
      };
      i += 1;
    };
    assert rootCount == (if (phase == 1 and mode != 0) configuredCount else 0);
    assert MLDSA.verify(input.publicKey, input.message, input.signature, input.context) == #ok(true);
    true
  };

  public query func snapshot() : async Snapshot {
    // Read counters before constructing/serializing the returned record.
    // Query allocations do not become committed update-state garbage.
    let heapOccupiedBytes = Prim.rts_heap_size();
    let totalAllocationBytes = Prim.rts_total_allocation();
    let reclaimedBytes = Prim.rts_reclaimed();
    let maxObservedPostGcHeapBytes = Prim.rts_max_live_size();
    let wasmMemoryBytes = Prim.rts_memory_size();
    let collectorInstructions = Prim.rts_collector_instructions();
    let mutatorInstructions = Prim.rts_mutator_instructions();
    {
      heapOccupiedBytes;
      totalAllocationBytes;
      reclaimedBytes;
      maxObservedPostGcHeapBytes;
      wasmMemoryBytes;
      collectorInstructions;
      mutatorInstructions;
      rootCount;
      configuredCount;
      mode;
      phase;
    }
  };
}
