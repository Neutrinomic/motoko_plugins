/// Deterministic CBOR encoding and typed decoding. Requires the `cbor` plugin.
import Prim "mo:⛔";

module {
  public type Error = {
    kind : Text;
    message : Text;
    /// Path using JSON Pointer escaping; the empty string identifies the root.
    path : Text;
    /// Input byte offset; zero for encoding errors.
    offset : Nat64;
  };
  public type Result<T> = { #ok : T; #err : Error };

  /// Encode one value as `Result<Blob>`. For tuples, use `encode((a, b))`.
  public let encode = Prim.to_cbor;

  /// Decode a Blob as `Result<T>` using an explicit concrete type: `decode<T>(bytes)`.
  public let decode = Prim.from_cbor;
}
