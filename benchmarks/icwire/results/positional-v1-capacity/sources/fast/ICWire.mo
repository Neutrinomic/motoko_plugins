/// Compact schema-directed internal messages. Requires the `icwire` plugin.
/// The writer and reader must agree on scalar and collection types. Records
/// support added optional fields and skip unknown fields; unknown variant cases
/// fail. This is a versioned internal format, not a public Candid interface.
import Prim "mo:⛔";

module {
  public type Error = {
    kind : Text;
    /// Absolute input byte offset, or output position for encoding errors.
    offset : Nat64;
  };
  public type Result<T> = { #ok : T; #err : Error };

  /// Encode exactly one immutable value. Parenthesize tuples: `encode((a, b))`.
  public let encode = Prim.to_icwire;

  /// Decode a complete message using an explicit concrete type.
  public let decode = Prim.from_icwire;
}
