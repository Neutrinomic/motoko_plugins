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
