/// Pure Ed25519 (RFC8032), with canonical encodings and strict verification.
/// Requires only the `ed25519` compiler plugin. Keys are 32 bytes; signatures
/// are 64 bytes. Signing accepts the original message, not an Ed25519ph digest.
import Prim "mo:⛔";

module {
  public type Error = { #invalidSecretKey; #invalidPublicKey; #invalidSignature };
  public type Result<T> = { #ok : T; #err : Error };
  public type KeyPair = { secretKey : Blob; publicKey : Blob };

  /// Immutable, process-local validated public key and multiplication table.
  /// Handles may be retained in transient records/maps; they are not stable
  /// values and cannot be sent in shared calls or converted to Blob.
  public type PreparedPublicKey = Prim.Ed25519PreparedPublicKey;

  /// Immutable, process-local expanded secret key. Treat this handle as secret.
  /// Its managed payload persists until collected and is not erased on drop.
  public type PreparedSecretKey = Prim.Ed25519PreparedSecretKey;

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

  /// Validate a public key once and prepare its multiplication table. Uses the
  /// same canonical and non-small-order rules as validatePublicKey.
  public let preparePublicKey = Prim.ed25519_prepare_public_key;

  /// Expand an exactly 32-byte seed once and bind its derived public key.
  /// The caller owns the resulting handle; there is no hidden key cache.
  public let prepareSecretKey = Prim.ed25519_prepare_secret_key;

  /// Sign exact message bytes using a validated prepared secret key. Returns
  /// the same deterministic signature as sign; no recoverable input can fail.
  public let signPrepared = Prim.ed25519_sign_prepared;

  /// Verify with a prepared public key. Signature validation and the strict
  /// uncofactored equation are identical to verify; malformed signatures return
  /// #err(#invalidSignature), and well-formed mismatches return #ok(false).
  public let verifyPrepared = Prim.ed25519_verify_prepared;
}
