/// BIP173 Bech32 and BIP350 Bech32m. Requires the `bech32` compiler plugin.
import Prim "mo:⛔";

module {
  public type Encoding = { #bech32; #bech32m };
  public type Error = {
    #invalidLength; #invalidHrp; #mixedCase; #invalidCharacter;
    #invalidChecksum; #invalidData; #invalidPadding; #invalidBitWidth;
  };
  public type Result<T> = { #ok : T; #err : Error };
  public type Decoded = { hrp : Text; data : Blob; encoding : Encoding };

  /// Encode 5-bit values (each byte 0..31). HRP is printable ASCII, 1..83
  /// characters; the complete result is at most 90 characters. Output is lowercase.
  /// Uppercase HRPs are normalized; mixed-case HRPs are rejected.
  public let encode = Prim.bech32_encode;

  /// Decode and verify either checksum variant. Accepts uniformly lowercase or
  /// uppercase ASCII and returns lowercase HRP plus data without checksum bytes.
  public let decode = Prim.bech32_decode;

  /// Convert groups of `fromBits` to `toBits` (both 1..8), most significant bit
  /// first. `pad = false` rejects excessive or nonzero trailing padding.
  /// Input and output are each limited to 16 MiB; values outside fromBits fail.
  public let convertBits = Prim.bech32_convert_bits;
}
