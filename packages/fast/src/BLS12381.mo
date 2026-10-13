/// BLS12-381 group arithmetic and signature verification. Requires `bls12-381`.
/// Points use IETF compressed encodings: G1=48 bytes, G2=96 bytes (imaginary x first).
/// Scalars are canonical 32-byte big-endian integers less than the scalar modulus.
/// Group operations permit infinity; signature profiles reject infinity keys/signatures.
import Prim "mo:⛔";
module {
  public type Error = {
    #invalidLength; #invalidPoint; #invalidScalar; #invalidField; #tooManyItems;
    #emptyBatch; #identity; #invalidProof; #duplicateMessage; #invalidArgument;
  };
  public type Result<T> = { #ok : T; #err : Error };
  /// Immutable local keys prepared by this plugin. These types cannot be forged
  /// from bytes, sent between actors, or stored across upgrades; retain the
  /// original public-key bytes when preparation must be repeated after upgrade.
  public type PreparedICPublicKey = Prim.BLS12381PreparedICPublicKey;
  public type PreparedEthereumPublicKey = Prim.BLS12381PreparedEthereumPublicKey;
  /// This distinct type additionally proves that the key's PoP was verified.
  public type PreparedEthereumPoPKey = Prim.BLS12381PreparedEthereumPoPKey;
  public let maxBatchSize : Nat = 128;
  /// General aggregate verification reserves one pairing term for the signature.
  public let maxAggregateSize : Nat = 127;
  public let g1Generator : Blob = "\97\f1\d3\a7\31\97\d7\94\26\95\63\8c\4f\a9\ac\0f\c3\68\8c\4f\97\74\b9\05\a1\4e\3a\3f\17\1b\ac\58\6c\55\e8\3f\f9\7a\1a\ef\fb\3a\f0\0a\db\22\c6\bb";
  public let g2Generator : Blob = "\93\e0\2b\60\52\71\9f\60\7d\ac\d3\a0\88\27\4f\65\59\6b\d0\d0\99\20\b6\1a\b5\da\61\bb\dc\7f\50\49\33\4c\f1\12\13\94\5d\57\e5\ac\7d\05\5d\04\2b\7e\02\4a\a2\b2\f0\8f\0a\91\26\08\05\27\2d\c5\10\51\c6\e4\7a\d4\fa\40\3b\02\b4\51\0b\64\7a\e3\d1\77\0b\ac\03\26\a8\05\bb\ef\d4\80\56\c8\c1\21\bd\b8";
  public let g1Identity : Blob = "\c0\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
  public let g2Identity : Blob = "\c0\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
  /// Canonical, on-curve, subgroup validation. Returns the canonical input.
  public let validateG1 = Prim.bls12_381_validate_g1;
  public let validateG2 = Prim.bls12_381_validate_g2;
  public let g1Add = Prim.bls12_381_g1_add;
  public let g2Add = Prim.bls12_381_g2_add;
  public let g1Mul = Prim.bls12_381_g1_mul;
  public let g2Mul = Prim.bls12_381_g2_mul;
  /// Packed concatenated points and 32-byte scalars, matching counts <=128.
  /// Empty MSM is the identity. Packed sizes are checked before computation.
  /// MSM is variable-time and is intended only for public scalars. Batches of
  /// two or three use Straus; four or more use bounded signed Pippenger buckets
  /// (33 stack slots) and temporary decoded-point storage.
  public let g1Msm = Prim.bls12_381_g1_msm;
  public let g2Msm = Prim.bls12_381_g2_msm;
  /// RFC9380 map plus effective cofactor clearing. Canonical Fp is 48-byte BE;
  /// Fp2 input is c0||c1 (real then imaginary), each 48-byte BE.
  public let mapToG1 = Prim.bls12_381_map_to_g1;
  public let mapToG2 = Prim.bls12_381_map_to_g2;
  /// RFC9380 random-oracle hash with caller-supplied nonempty domain separation tag.
  /// Oversized DSTs are normalized with SHA256 as specified by RFC9380.
  public let hashToG1 = Prim.bls12_381_hash_to_g1;
  public let hashToG2 = Prim.bls12_381_hash_to_g2;
  /// Product e(G1,G2)=1. Packed G1||G2 terms (144 bytes each), at most 128.
  /// Canonical/subgroup checks apply to every point; infinity is neutral;
  /// the empty product is true. This is a group primitive, not a signature API.
  public let pairingCheck = Prim.bls12_381_pairing_check;
  /// Raw IC BLS signature verification (G2 key, message, G1 signature).
  /// Message domain framing, e.g. ic-state-root, remains the caller's responsibility.
  public let verifyIC = Prim.bls12_381_verify_ic;
  /// Ethereum POP ciphersuite (G1 key, message, G2 signature).
  /// Message signing-root construction remains the caller's responsibility.
  public let verifyEthereum = Prim.bls12_381_verify_ethereum;
  public let verifyEthereumProof = Prim.bls12_381_verify_ethereum_pop;
  /// Validate a nonidentity IC key and precompute its pairing coefficients.
  /// Reuse the resulting local value for repeated signature verification.
  public let prepareICPublicKey = Prim.bls12_381_prepare_ic_public_key;
  /// Validate a nonidentity Ethereum key once for single-signature verification.
  /// This does not verify a proof of possession and cannot authorize aggregation.
  public let prepareEthereumPublicKey = Prim.bls12_381_prepare_ethereum_public_key;
  /// Validate the key and its PoP once, then retain the result for aggregation.
  /// A well-formed false proof returns #invalidProof; decoding errors are preserved.
  public let prepareEthereumPoPKey = Prim.bls12_381_prepare_ethereum_pop_key;
  /// Verify against an already prepared IC key. Message framing remains the
  /// caller's responsibility, exactly as with verifyIC.
  public let verifyICPrepared = Prim.bls12_381_verify_ic_prepared;
  /// Verify against a validated Ethereum key, without decoding the key again.
  public let verifyEthereumPrepared = Prim.bls12_381_verify_ethereum_prepared;
  /// Packed group sums, <=128 points. Empty input is identity. These raw group
  /// operations do not confer possession of the corresponding secret keys.
  public let g1Aggregate = Prim.bls12_381_g1_aggregate;
  public let g2Aggregate = Prim.bls12_381_g2_aggregate;

  /// Aggregate IC/basic signatures only over pairwise-distinct messages.
  /// Requires 1..127 entries and rejects duplicates before doing cryptography.
  public func aggregateVerifyIC(keys : [Blob], messages : [Blob], signature : Blob) : Result<Bool> {
    Prim.bls12_381_aggregate_verify_ic(keys, messages, signature)
  };

  /// Ethereum aggregate verification with PoP verification for every key.
  /// Only exact key/proof pairs checked successfully within this call are reused.
  /// Malformed keys/proofs preserve decoding errors; false proofs return #invalidProof.
  /// Repeated messages up to 1024 bytes reuse their hash. Requires 1..127 entries.
  public func aggregateVerifyEthereum(keys : [Blob], proofs : [Blob], messages : [Blob], signature : Blob) : Result<Bool> {
    Prim.bls12_381_aggregate_verify_ethereum(keys, proofs, messages, signature)
  };

  /// Same-message Ethereum aggregate verification. Every key requires its PoP;
  /// the aggregate key is then verified in one two-term pairing. 1..128 entries.
  public func fastAggregateVerifyEthereum(keys : [Blob], proofs : [Blob], message : Blob, signature : Blob) : Result<Bool> {
    Prim.bls12_381_fast_aggregate_verify_ethereum(keys, proofs, message, signature)
  };

  /// IC aggregate verification with prepared keys and pairwise-distinct messages.
  /// Requires 1..127 entries; duplicates are rejected before signature decoding.
  public func aggregateVerifyICPrepared(keys : [PreparedICPublicKey], messages : [Blob], signature : Blob) : Result<Bool> {
    Prim.bls12_381_aggregate_verify_ic_prepared(keys, messages, signature)
  };

  /// Ethereum aggregate verification with keys whose PoPs were already checked.
  /// Requires 1..127 entries; no proof verification is repeated within this call.
  public func aggregateVerifyEthereumPrepared(keys : [PreparedEthereumPoPKey], messages : [Blob], signature : Blob) : Result<Bool> {
    Prim.bls12_381_aggregate_verify_ethereum_prepared(keys, messages, signature)
  };

  /// Same-message Ethereum aggregation with proven keys. Requires 1..128 entries;
  /// the aggregate key must be nonidentity, as with fastAggregateVerifyEthereum.
  public func fastAggregateVerifyEthereumPrepared(keys : [PreparedEthereumPoPKey], message : Blob, signature : Blob) : Result<Bool> {
    Prim.bls12_381_fast_aggregate_verify_ethereum_prepared(keys, message, signature)
  };
}
