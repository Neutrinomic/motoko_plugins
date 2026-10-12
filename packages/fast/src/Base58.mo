/// Bitcoin Base58 with strict alphabet validation. Requires the `base58` plugin.
import Prim "mo:⛔";

module {
  public type Error = {
    /// Input or decoded output exceeds the documented bounds.
    #tooLarge;
    /// UTF-8 byte offset of the first character outside the Bitcoin alphabet.
    #invalidCharacter : Nat64;
  };
  public type Result<T> = { #ok : T; #err : Error };
  public let maxInputBytes : Nat = 4096;
  public let maxTextBytes : Nat = 5653;

  /// Encode a Blob, preserving each leading zero byte as `1`.
  /// Empty input produces empty text. Traps above `maxInputBytes`.
  public let encode = Prim.base58_encode;

  /// Decode canonical Bitcoin Base58. Whitespace, `0`, `O`, `I`, `l`, and
  /// non-ASCII characters are invalid. Empty text produces an empty Blob.
  /// Check input size first, then the complete alphabet, then decoded size.
  /// At most `maxTextBytes` UTF-8 input bytes and `maxInputBytes` output bytes
  /// are accepted; these bounds limit the quadratic conversion work.
  public let decode = Prim.base58_decode;
}
