/// One-shot SHA-256. Requires the `sha256` compiler plugin.
import Prim "mo:⛔";

module {
  /// Compute the 32-byte digest of a Blob.
  public let digest = Prim.sha256;
}
