/// FIPS 204 ML-DSA-44 signatures. Requires only the `ml-dsa` plugin.
/// Secret keys are exactly 32-byte seeds. Generate seeds with a secure source
/// of entropy outside this pure module; every 32-byte string is accepted.
/// Public keys are 1312 bytes and signatures are 2420 bytes.
import Prim "mo:⛔";

module {
  public type Error = {
    #invalidSecretKey;
    #invalidPublicKey;
    #invalidSignature;
    #invalidContext;
    #invalidRandomness;
  };
  public type Result<T> = { #ok : T; #err : Error };

  /// Immutable validated public key with reusable verification preparation.
  /// Opaque, local and nonstable: retain it in transient state and prepare it
  /// again from the public-key Blob after an upgrade.
  public type PreparedPublicKey = Prim.MLDSAPreparedPublicKey;

  /// Immutable expanded secret key with reusable signing preparation.
  /// This holds secret material. It is opaque, local and nonstable; retain it
  /// in transient state and prepare it again from the secret seed after upgrade.
  public type PreparedSecretKey = Prim.MLDSAPreparedSecretKey;

  /// Prepare a 1312-byte public key once for repeated verification.
  /// Invalid public-key lengths return #err(#invalidPublicKey).
  public let preparePublicKey = Prim.mldsa_prepare_public_key;

  /// Expand a 32-byte secret seed once for repeated signing.
  /// Invalid seed lengths return #err(#invalidSecretKey).
  public let prepareSecretKey = Prim.mldsa_prepare_secret_key;

  /// Verify with a previously prepared public key. Argument order is prepared
  /// key, message, signature, context. Invalid signature length is checked
  /// before context length. Length-correct invalid signatures return #ok(false).
  public let verifyPrepared = Prim.mldsa_verify_prepared;

  /// Deterministic signing with a prepared secret key and rnd = 32 zero bytes.
  /// Context is at most 255 bytes. Preparation does not change signature bytes.
  public let signPrepared = Prim.mldsa_sign_prepared;

  /// Hedged signing with a prepared secret key and explicit 32-byte randomness.
  /// Argument order is prepared key, message, context, randomness. Context length
  /// is checked before randomness length; supply fresh secure randomness.
  public let signRandomizedPrepared = Prim.mldsa_sign_randomized_prepared;

  /// Deterministically generate the public key corresponding to a secret seed.
  /// This performs FIPS 204 key generation; no expanded secret key is retained.
  public let publicKey = Prim.mldsa_public_key;

  /// Deterministic FIPS 204 signing with rnd = 32 zero bytes.
  /// Context is at most 255 bytes; use the same context during verification.
  /// Each call expands the seed. It accepts the message, not a precomputed hash.
  public let sign = Prim.mldsa_sign;

  /// FIPS 204 hedged signing with an explicit, exactly 32-byte rnd value.
  /// Supply fresh cryptographically secure randomness for hedged signing.
  /// Argument order: secret seed, message, context, randomness.
  public let signRandomized = Prim.mldsa_sign_randomized;

  /// Verify a pure ML-DSA signature: public key, message, signature, context.
  /// Invalid key/signature lengths and overlong contexts return #err.
  /// Length-correct malformed or nonmatching signatures return #ok(false).
  /// Validation order is public-key length, signature length, then context.
  public let verify = Prim.mldsa_verify;
}
