// Test-only pre-fusion public wrapper from 7a0211b97d2da0910d6982ad5b7111df376f4f9f; never used in production.
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
  /// Packed group sums, <=128 points. Empty input is identity. These raw group
  /// operations do not confer possession of the corresponding secret keys.
  public let g1Aggregate = Prim.bls12_381_g1_aggregate;
  public let g2Aggregate = Prim.bls12_381_g2_aggregate;

  let icDST : Blob = "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_";
  let ethDST : Blob = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_";

  func pack(parts : [Blob]) : Blob {
    var size = 0;
    for (part in parts.values()) { size += part.size() };
    let output = Prim.Array_init<Nat8>(size, 0);
    var at = 0;
    for (part in parts.values()) {
      for (byte in part.values()) { output[at] := byte; at += 1 };
    };
    Prim.arrayMutToBlob(output)
  };
  // Called only after canonical validation and rejection of infinity.
  func negateG1(point : Blob) : Blob {
    let bytes = Prim.blobToArrayMut(point);
    bytes[0] := bytes[0] ^ 0x20;
    Prim.arrayMutToBlob(bytes)
  };
  func validG1(point : Blob) : Result<Blob> {
    switch (validateG1(point)) {
      case (#err(e)) #err(e);
      case (#ok(p)) { if (p == g1Identity) #err(#identity) else #ok(p) };
    }
  };
  func validG2(point : Blob) : Result<Blob> {
    switch (validateG2(point)) {
      case (#err(e)) #err(e);
      case (#ok(p)) { if (p == g2Identity) #err(#identity) else #ok(p) };
    }
  };

  // Keep tiny batches and early duplicate rejection allocation-free. Larger
  // batches use a bounded merge sort; equality still compares exact bytes.
  func differentMessages(messages : [Blob]) : Bool {
    let n = messages.size();
    let prefix = if (n < 16) n else 8;
    var i = 0;
    while (i < prefix) {
      var j = 0;
      while (j < i) {
        if (messages[i] == messages[j]) return false;
        j += 1;
      };
      i += 1;
    };
    if (n < 16) return true;
    var source = Prim.Array_tabulateVar<Blob>(n, func(i) { messages[i] });
    var target = Prim.Array_init<Blob>(n, "");
    var width = 1;
    while (width < n) {
      var start = 0;
      while (start < n) {
        let middle = if (start + width < n) start + width else n;
        let end = if (middle + width < n) middle + width else n;
        var left = start;
        var right = middle;
        var out = start;
        while (left < middle and right < end) {
          let a = source[left]; let b = source[right];
          let comparison : Int8 = if (a.size() < b.size()) -1 else if (a.size() > b.size()) 1 else Prim.blobCompare(a, b);
          if (comparison == 0) return false;
          if (comparison < 0) { target[out] := a; left += 1 }
          else { target[out] := b; right += 1 };
          out += 1;
        };
        while (left < middle) { target[out] := source[left]; left += 1; out += 1 };
        while (right < end) { target[out] := source[right]; right += 1; out += 1 };
        start := end;
      };
      let old = source; source := target; target := old;
      width *= 2;
    };
    true
  };

  /// Aggregate IC/basic signatures only over pairwise-distinct messages.
  /// Requires 1..127 entries and rejects duplicates before doing cryptography.
  public func aggregateVerifyIC(keys : [Blob], messages : [Blob], signature : Blob) : Result<Bool> {
    let n = keys.size();
    if (n != messages.size()) return #err(#invalidLength);
    if (n == 0) return #err(#emptyBatch);
    if (n > maxAggregateSize) return #err(#tooManyItems);
    if (not differentMessages(messages)) return #err(#duplicateMessage);
    var i = 0;
    let sig = switch (validG1(signature)) { case (#ok(p)) p; case (#err(e)) return #err(e) };
    let terms = Prim.Array_init<Blob>(n * 2 + 2, "");
    terms[0] := negateG1(sig); terms[1] := g2Generator;
    i := 0;
    while (i < n) {
      let key = switch (validG2(keys[i])) { case (#ok(p)) p; case (#err(e)) return #err(e) };
      let hashed = switch (hashToG1(messages[i], icDST)) { case (#ok(p)) p; case (#err(e)) return #err(e) };
      terms[i * 2 + 2] := hashed; terms[i * 2 + 3] := key;
      i += 1;
    };
    pairingCheck(pack(Prim.Array_tabulate<Blob>(terms.size(), func(i) { terms[i] })))
  };

  /// Verify every distinct key/proof byte pair within each call before aggregate use.
  /// Byte-identical pairs reuse only a successful check from this same call.
  /// Well-formed proofs that fail verification return #invalidProof. Malformed
  /// keys/proofs preserve decoding errors; no unchecked assertion flag exists.
  func checkProofs(keys : [Blob], proofs : [Blob]) : Result<()> {
    if (keys.size() != proofs.size()) return #err(#invalidLength);
    var i = 0;
    while (i < keys.size()) {
      // Reuse only a byte-identical pair already checked successfully in this
      // call. A new proof for a repeated key is always verified independently.
      var duplicate = false;
      var j = 0;
      while (j < i and not duplicate) {
        duplicate := keys[j] == keys[i] and proofs[j] == proofs[i];
        j += 1;
      };
      if (not duplicate) {
        switch (verifyEthereumProof(keys[i], proofs[i])) {
          case (#err(e)) return #err(e);
          case (#ok(false)) return #err(#invalidProof);
          case (#ok(true)) {};
        };
      };
      i += 1;
    };
    #ok(())
  };
  /// Ethereum aggregate verification with PoP verification for every key.
  /// Repeated messages up to 1024 bytes reuse their hash after possession is checked.
  /// Longer messages are hashed directly to bound byte-comparison work. 1..127 entries.
  public func aggregateVerifyEthereum(keys : [Blob], proofs : [Blob], messages : [Blob], signature : Blob) : Result<Bool> {
    let n = keys.size();
    if (n != messages.size() or n != proofs.size()) return #err(#invalidLength);
    if (n == 0) return #err(#emptyBatch);
    if (n > maxAggregateSize) return #err(#tooManyItems);
    let sig = switch (validG2(signature)) { case (#ok(p)) p; case (#err(e)) return #err(e) };
    switch (checkProofs(keys, proofs)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    let terms = Prim.Array_init<Blob>(n * 2 + 2, "");
    terms[0] := negateG1(g1Generator); terms[1] := sig;
    var i = 0;
    while (i < n) {
      var representative = i;
      var j = 0;
      // Keep pairwise byte comparisons bounded independently of message length.
      // Ethereum signing roots are 32 bytes; longer raw messages remain supported.
      let reusable = messages[i].size() <= 1024;
      while (reusable and j < i and representative == i) {
        if (messages[j] == messages[i]) representative := j;
        j += 1;
      };
      let hashed = if (representative < i) terms[representative * 2 + 3] else {
        switch (hashToG2(messages[i], ethDST)) { case (#ok(p)) p; case (#err(e)) return #err(e) }
      };
      terms[i * 2 + 2] := keys[i]; terms[i * 2 + 3] := hashed;
      i += 1;
    };
    pairingCheck(pack(Prim.Array_tabulate<Blob>(terms.size(), func(i) { terms[i] })))
  };

  /// Same-message Ethereum aggregate verification. Every key requires its PoP;
  /// the aggregate key is then verified in one two-term pairing. 1..128 entries.
  public func fastAggregateVerifyEthereum(keys : [Blob], proofs : [Blob], message : Blob, signature : Blob) : Result<Bool> {
    if (keys.size() != proofs.size()) return #err(#invalidLength);
    if (keys.size() == 0) return #err(#emptyBatch);
    if (keys.size() > maxBatchSize) return #err(#tooManyItems);
    switch (checkProofs(keys, proofs)) { case (#err(e)) return #err(e); case (#ok(())) {} };
    let key = switch (g1Aggregate(pack(keys))) { case (#ok(p)) p; case (#err(e)) return #err(e) };
    verifyEthereum(key, message, signature)
  };
}
