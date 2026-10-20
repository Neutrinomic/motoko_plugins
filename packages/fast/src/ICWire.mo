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

  /// Encode in one traversal using a caller-provided total encoded byte bound.
  /// The output contains only actual bytes, with the same format as `encode`.
  /// Bounds are at most 16 MiB; exceeding the bound returns `#err`.
  /// Reserved capacity is charged until GC, so use a close bound.
  public let encodeBounded = Prim.to_icwire_bounded;

  /// Decode a complete message using an explicit concrete type.
  public let decode = Prim.from_icwire;

  /// Encode trusted data directly; failures trap with the same diagnostic as
  /// `unwrap(encode(value))`, without allocating a successful Result wrapper.
  public let encodeOrTrap = Prim.to_icwire_or_trap;

  /// Decode directly, trapping with `unwrap(decode<T>(bytes))` diagnostics.
  /// Use ordinary `decode` when malformed input needs a recoverable result.
  public let decodeOrTrap = Prim.from_icwire_or_trap;

  /// The same caller-bounded encoding as `encodeBounded`, with direct success
  /// and the identical diagnostic trap on failure.
  public let encodeBoundedOrTrap = Prim.to_icwire_bounded_or_trap;

  /// Exact encoded byte size without encoding or scratch allocation.
  /// Fixed-width arrays use their length rather than visiting each element.
  /// Returns `2 ** 61 - 1` when a byte, node, depth or integer bound is exceeded.
  /// This sizes floats without checking finiteness; encoding still rejects NaN
  /// and infinity. This function is a size bound, not an encodability check.
  public let estimateSize = Prim.icwire_estimate_size;

  /// Extract a trusted codec result, trapping with its diagnostic on failure.
  public func unwrap<T>(result : Result<T>) : T {
    switch result {
      case (#ok value) value;
      case (#err error) Prim.trap("ICWire " # error.kind # " at byte " # debug_show error.offset);
    }
  };

  /// Adapt a decoder result to an optional value.
  public func toOption<T>(result : Result<T>) : ?T {
    switch result { case (#ok value) ?value; case (#err _) null }
  };
}
