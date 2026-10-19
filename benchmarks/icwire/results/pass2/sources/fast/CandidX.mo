/// Canonical Candid encoding. Requires the `candidx` compiler plugin.
import Prim "mo:⛔";

module {
  public type Error = Text;
  public type Result = { #ok : Blob; #err : Error };

  /// Encode zero or more values, returning `Result`.
  /// `encode(a, b)` encodes two arguments; `encode((a, b))` encodes one tuple.
  /// The compiler specializes this alias at each call's concrete argument types.
  public let encode = Prim.to_candid_canonical;

  /// Fast conservative estimate of ordinary `to_candid` byte size, including
  /// its type header. Accepts the same shared arguments as `to_candid`.
  /// No encoding or scratch allocation; fixed-width arrays use their length.
  /// The estimate can reject values whose actual encoding fits a size limit.
  /// Returns `2 ** 61 - 1` on function references, depth > 256, more than
  /// 1,000,000 dynamic visits, or a saturated estimate. This sentinel exceeds
  /// every Blob size ordinary `to_candid` can successfully produce.
  /// This is an admission estimate, not the canonical encoder's exact size.
  public let estimateSize = Prim.candid_estimate_size;
}
