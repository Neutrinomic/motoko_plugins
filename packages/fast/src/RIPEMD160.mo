/// RIPEMD-160 hashing. Requires only the `ripemd160` compiler plugin.
import Prim "mo:⛔";

module {
  /// A canonical 104-byte immutable state. It can be retained in stable storage
  /// or branched to hash different suffixes. Treat its encoding as opaque.
  public type State = Blob;

  /// Compute the 20-byte RIPEMD-160 digest of a Blob.
  public let digest = Prim.ripemd160_digest;
  /// Start a new incremental hash.
  public let init = Prim.ripemd160_init;
  /// Return the next state, leaving the old state unchanged. Returns null for
  /// malformed states or when total input exceeds 2^61 - 1 bytes.
  public let update = Prim.ripemd160_update;
  /// Compute a digest without consuming the state. Returns null for malformed
  /// states; a valid state can be finalized repeatedly and updated afterwards.
  public let finalize = Prim.ripemd160_finalize;

  /// Convenient mutable streaming API. Each write holds at most 104 state
  /// bytes, independent of total message length. A rejected write preserves
  /// the old state and returns false.
  public class Digest() {
    var state : Blob = Prim.ripemd160_init();

    public func write(data : Blob) : Bool {
      switch (Prim.ripemd160_update(state, data)) {
        case null false;
        case (?next) { state := next; true };
      }
    };

    public func sum() : Blob {
      switch (Prim.ripemd160_finalize(state)) {
        case (?result) result;
        case null Prim.trap("RIPEMD160: invalid internal state");
      }
    };

    public func reset() { state := Prim.ripemd160_init() };
  };
}
