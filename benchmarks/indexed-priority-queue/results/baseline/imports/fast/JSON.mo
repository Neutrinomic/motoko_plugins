/// Typed JSON encoding and decoding. Requires the `json` compiler plugin.
import Prim "mo:⛔";

module {
  public type Error = {
    kind : Text;
    message : Text;
    /// JSON Pointer; the empty string identifies the root.
    path : Text;
    /// UTF-8 byte offset; zero for encoding errors.
    offset : Nat64;
  };
  public type Result<T> = { #ok : T; #err : Error };

  /// Encode one value as `Result<Text>`. For tuples, use `encode((a, b))`.
  public let encode = Prim.to_json;

  /// Decode text as `Result<T>` using an explicit concrete type: `decode<T>(text)`.
  public let decode = Prim.from_json;
}
