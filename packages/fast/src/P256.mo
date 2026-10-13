/// NIST P-256 (secp256r1 / prime256v1). Requires only the `p256` plugin.
/// Public keys use SEC1 compressed (33-byte) or uncompressed (65-byte) form.
/// Scalars and compact signature components use fixed-width big-endian bytes.
import Prim "mo:⛔";

module {
  public type Error = {
    #invalidSecretKey;
    #invalidPublicKey;
    #invalidDigest;
    #invalidSignature;
  };
  public type Result<T> = { #ok : T; #err : Error };

  /// Validated public-key comb for repeated verification. Caller-owned,
  /// immutable and garbage-collected; cannot be shared or stored as stable data.
  public type PreparedPublicKey = Prim.P256PreparedPublicKey;

  /// Validate an SEC1 public key and precompute its verification table once.
  public let preparePublicKey = Prim.p256_prepare_public_key;

  /// Verify using a prepared public key; validates digest then signature.
  /// Accepts the same high-S and low-S signatures as verifyPrehash.
  public let verifyPrehashPrepared = Prim.p256_verify_prehash_prepared;

  /// Derive a public key from an exactly 32-byte secret scalar in [1, n).
  public let publicKey = Prim.p256_public_key;

  /// Derive a compressed public key.
  public func derivePublicKey(secretKey : Blob) : Result<Blob> {
    publicKey(secretKey, true)
  };

  /// Validate and re-encode an SEC1 public key. Rejects infinity and hybrid keys.
  public let convertPublicKey = Prim.p256_convert_public_key;

  /// Deterministic RFC6979 HMAC-SHA256 signing of an exactly 32-byte digest.
  /// Returns compact r || s (64 bytes), preserving S as specified by RFC6979.
  /// Use normalizeSignature when the consuming protocol requires low-S.
  public let signPrehash = Prim.p256_sign_prehash;

  /// Verify a compact 64-byte signature against an exactly 32-byte digest.
  /// Accepts both high-S and low-S signatures. Invalid encodings return #err;
  /// a well-formed signature that does not verify returns #ok(false).
  /// Input validation order is public key, digest, then signature.
  public let verifyPrehash = Prim.p256_verify_prehash;

  /// Encode a valid compact signature as minimal ASN.1 DER (8–72 bytes).
  public let signatureToDer = Prim.p256_signature_to_der;

  /// Decode strict minimal ASN.1 DER into a compact 64-byte signature.
  /// Rejects trailing data, negative/overlong INTEGERs and r/s outside [1, n).
  public let signatureFromDer = Prim.p256_signature_from_der;

  /// Map S to min(S, n-S), preserving R. Rejects invalid compact signatures.
  public let normalizeSignature = Prim.p256_normalize_signature;
}
