/// Compact schema-directed internal messages. Requires the `icwire` plugin.
/// The writer and reader must share the exact schema. Records contain only
/// consecutive field values; messages carry no header, type table or field IDs.
/// Schema changes require version handling at the application boundary.
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
