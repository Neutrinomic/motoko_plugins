/// Pure Ed25519 (RFC8032), with canonical encodings and strict verification.
/// Requires only the `ed25519` compiler plugin. Keys are 32 bytes; signatures
/// are 64 bytes. Signing accepts the original message, not an Ed25519ph digest.
import Prim "mo:⛔";

module {
  public type Error = { #invalidSecretKey; #invalidPublicKey; #invalidSignature };
  public type Result<T> = { #ok : T; #err : Error };
  public type KeyPair = { secretKey : Blob; publicKey : Blob };

  /// Derive the public key from an exactly 32-byte secret seed. Every 32-byte
  /// seed is accepted. Use cryptographically random bytes for real keys.
  public let derivePublicKey = Prim.ed25519_public_key;

  /// Create a key pair from caller-supplied randomness. The secret key is the
  /// seed itself, retained by reference; this function does not generate entropy.
  public func keyPairFromSeed(seed : Blob) : Result<KeyPair> {
    switch (derivePublicKey(seed)) {
      case (#ok publicKey) #ok { secretKey = seed; publicKey };
      case (#err error) #err error;
    }
  };

  /// Return #ok(true) for a canonical, on-curve, non-small-order public key.
  /// Invalid keys return #err(#invalidPublicKey). This is not a proof that a
  /// key belongs to someone, nor a prime-subgroup membership test.
  public let validatePublicKey = Prim.ed25519_validate_public_key;

  /// Deterministic pure Ed25519 signing of the exact message bytes with a
  /// 32-byte seed. Public keys are derived internally, preventing mismatched
  /// seed/public-key signing. No prehash or context variant is selected.
  public let sign = Prim.ed25519_sign;

  /// Verify the exact message bytes. Validate the public key first, then the
  /// signature. A/R must be canonical, on-curve and not small-order; S < L.
  /// The uncofactored equation is checked. Invalid encodings return #err;
  /// a well-formed signature that does not verify returns #ok(false).
  public let verify = Prim.ed25519_verify;
}
