/// One-shot SHA-256. Requires the `sha256` compiler plugin.
import Prim "mo:⛔";

module {
  /// Compute the 32-byte digest of a Blob.
  public let digest = Prim.sha256;

  /// Hash the concatenation of these Blobs without copying their payloads.
  /// Empty parts are allowed. The result equals digest of the joined bytes.
  public let digestParts = Prim.sha256_parts;
}
