/// secp256k1 arithmetic, deterministic ECDSA, and BIP340 Schnorr.
/// Requires only the `secp256k1` compiler plugin.
import Prim "mo:⛔";

module {
  public type Error = {
    #invalidSecretKey; #invalidPublicKey; #invalidScalar; #invalidDigest;
    #invalidSignature; #invalidAuxiliaryRandomness; #pointAtInfinity;
  };
  public type Result<T> = { #ok : T; #err : Error };

  /// Opaque cached ECDSA verification key. Create with preparePublicKey.
  /// Use the original public-key bytes for key equality or map keys.
  /// Local only: not shared or stable; rebuild from the public key after upgrade.
  public type PreparedPublicKey = Prim.Secp256k1PreparedPublicKey;
  /// Opaque cached BIP340 verification key, normalized to the even-Y point.
  /// Local only: not shared or stable; rebuild from the x-only key after upgrade.
  public type PreparedSchnorrPublicKey = Prim.Secp256k1PreparedSchnorrPublicKey;
  /// Opaque cached BIP340 signing key. Contains secret key material.
  /// Local only: not shared or stable. Managed copies remain until GC, with no
  /// secure-erasure guarantee; keep this value as private as the original secret.
  public type PreparedSchnorrSecretKey = Prim.Secp256k1PreparedSchnorrSecretKey;

  /// Secret keys are exactly 32 big-endian bytes, in [1, n). Output is SEC1 compressed.
  public let derivePublicKey = Prim.secp256k1_derivePublicKey;
  public let compressPublicKey = Prim.secp256k1_compressPublicKey;
  public let decompressPublicKey = Prim.secp256k1_decompressPublicKey;

  /// Accepts canonical SEC1 compressed (33) or uncompressed (65) public keys.
  public func convertPublicKey(key : Blob, compressed : Bool) : Result<Blob> {
    if (compressed) compressPublicKey(key) else decompressPublicKey(key)
  };
  public func publicKey(secret : Blob, compressed : Bool) : Result<Blob> {
    switch (derivePublicKey(secret)) {
      case (#err(error)) #err(error);
      case (#ok(key)) { if (compressed) #ok(key) else decompressPublicKey(key) };
    }
  };

  /// All point outputs use SEC1 compressed encoding; infinity is a typed error.
  public let pointAdd = Prim.secp256k1_pointAdd;
  /// Scalars are exactly 32 big-endian bytes in [0,n), including zero.
  public let pointMultiply = Prim.secp256k1_pointMultiply;
  public let baseMultiply = Prim.secp256k1_baseMultiply;
  /// Compute P + tweak*G, allowing a zero tweak, rejecting tweak >= n.
  public let tweakPublicKey = Prim.secp256k1_tweakPublicKey;

  /// RFC6979/HMAC-SHA256 signing of an already-hashed 32-byte digest.
  /// Returns compact r||s (64 bytes), normalized to low-S. Does not hash the digest again.
  public let signPrehash = Prim.secp256k1_signPrehash;
  /// Standard ECDSA verification accepts both low-S and high-S compact signatures.
  /// Invalid encodings are errors; well-formed signatures with a failed equation are #ok(false).
  public let verifyPrehash = Prim.secp256k1_verifyPrehash;
  /// Validate a canonical SEC1 key once and cache data for repeated ECDSA verification.
  public let preparePublicKey = Prim.secp256k1_preparePublicKey;
  /// Same digest, compact-signature and error rules as verifyPrehash.
  public let verifyPrehashPrepared = Prim.secp256k1_verifyPrehashPrepared;
  /// DER conversion enforces minimal positive integers and rejects trailing data.
  public let signatureToDer = Prim.secp256k1_signatureToDer;
  public let signatureFromDer = Prim.secp256k1_signatureFromDer;
  public let normalizeSignature = Prim.secp256k1_normalizeSignature;

  /// Extract the x coordinate from a validated SEC1 public key (does not derive a key).
  public let xOnlyPublicKey = Prim.secp256k1_xOnlyPublicKey;
  /// BIP340 signs the supplied message bytes directly, supporting every message length.
  /// aux must be exactly 32 bytes; callers supply auxiliary randomness explicitly.
  public let schnorrSign = Prim.secp256k1_schnorrSign;
  public let schnorrVerify = Prim.secp256k1_schnorrVerify;
  /// Validate an x-only key once and cache data for repeated BIP340 verification.
  public let prepareSchnorrPublicKey = Prim.secp256k1_prepareSchnorrPublicKey;
  /// Same message, signature and error rules as schnorrVerify.
  public let schnorrVerifyPrepared = Prim.secp256k1_schnorrVerifyPrepared;
  /// Derive the public point and normalize the secret once for repeated signing.
  /// Accepts the same 32-byte secret key as schnorrSign; the result is secret.
  public let prepareSchnorrSecretKey = Prim.secp256k1_prepareSchnorrSecretKey;
  /// Sign raw message bytes with a cached secret key; aux must be exactly 32 bytes.
  public let schnorrSignPrepared = Prim.secp256k1_schnorrSignPrepared;
  /// Lift the x-only key to even Y and add tweak*G. Compressed SEC1 output retains
  /// the output parity for Taproot control blocks; caller computes the tagged tweak hash.
  public let tweakXOnlyPublicKey = Prim.secp256k1_tweakXOnlyPublicKey;
  /// BIP341 secret tweak: normalize the internal secret to the even-Y public
  /// point, then add the canonical tweak. A zero result is #pointAtInfinity.
  /// Secret scalar arithmetic stays inside the native plugin operation.
  public let tweakXOnlySecretKey = Prim.secp256k1_tweakXOnlySecretKey;
}
