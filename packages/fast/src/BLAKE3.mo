/// BLAKE3 hashing, keyed hashing, key derivation, and seekable extended output.
/// Requires only the `blake3` compiler plugin.
import Prim "mo:⛔";

module {
  public type Error = {
    #invalidKey; #invalidState; #outputTooLarge; #inputTooLong; #invalidSeek;
  };
  public type Result<T> = { #ok : T; #err : Error };
  /// Immutable state; contains key material in keyed/derive-key modes. Treat its
  /// bytes as private implementation data. Update returns a new independent state.
  public type State = Blob;

  /// Maximum bytes produced by a single XOF call (16 MiB).
  public let maxOutputBytes : Nat32 = 16_777_216;
  /// Compute the standard 32-byte BLAKE3 digest.
  public let digest = Prim.blake3_digest;
  /// Compute a 32-byte keyed hash. The key must contain exactly 32 bytes.
  public let keyedHash = Prim.blake3_keyed_hash;
  /// Derive a 32-byte key with BLAKE3's context domain separation. Context is
  /// UTF-8 text, conventionally an application-specific, globally unique string.
  public let deriveKey = Prim.blake3_derive_key;
  /// Read `length` bytes of the hash output starting at byte `offset`.
  /// Rejects output above maxOutputBytes or offset + length above Nat64 maximum.
  public let xof = Prim.blake3_xof;

  /// Create an empty unkeyed hash state.
  public let new = Prim.blake3_new;
  /// Create a keyed state. The key must contain exactly 32 bytes.
  public let newKeyed = Prim.blake3_new_keyed;
  /// Create a state for deriving key material under the supplied context.
  public let newDeriveKey = Prim.blake3_new_derive_key;
  /// Return an updated state without modifying the old state. Total input is
  /// limited to 2^64 - 1 bytes; malformed state returns #invalidState.
  public let update = Prim.blake3_update;
  /// Read extended output without consuming or modifying the state.
  public let finalizeXof = Prim.blake3_finalize_xof;
  /// Read the standard 32-byte digest without consuming the state.
  public func finalize(state : State) : Result<Blob> {
    Prim.blake3_finalize_xof(state, 0, 32)
  };
}
