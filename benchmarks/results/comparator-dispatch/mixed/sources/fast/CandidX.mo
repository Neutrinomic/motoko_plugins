/// Canonical Candid encoding. Requires the `candidx` compiler plugin.
import Prim "mo:⛔";

module {
  public type Error = Text;
  public type Result = { #ok : Blob; #err : Error };

  /// Encode zero or more values, returning `Result`.
  /// `encode(a, b)` encodes two arguments; `encode((a, b))` encodes one tuple.
  /// The compiler specializes this alias at each call's concrete argument types.
  public let encode = Prim.to_candid_canonical;
}
