// Prepared-SDK control: round3 ecdsa@8.0.1 verification adapter and independent native-matched literals.
import Prim "mo:prim";
import E "mo:ecdsa";
persistent actor {
  transient let curve = E.Curve(#secp256k1);

  type Result<T> = {#ok : T; #err : Text};
  func number(bytes : [Nat8], start : Nat, length : Nat) : Nat {
    var value = 0; var i = start;
    while (i < start + length) { value := value * 256 + Prim.nat8ToNat(bytes[i]); i += 1 };
    value
  };
  func parseKey(key : Blob) : Result<E.PublicKey> {
    let bytes = Prim.blobToArray(key);
    if (bytes.size() != 33 and bytes.size() != 65) return #err("invalid public key length");
    if (not ((bytes.size() == 33 and (bytes[0] == 2 or bytes[0] == 3)) or
      (bytes.size() == 65 and bytes[0] == 4))) return #err("invalid SEC1 prefix");
    E.publicKeyFromBytes(key.vals(), #raw({curve}))
  };
  func parseCompact(signature : Blob) : Result<E.Signature> {
    if (signature.size() != 64) return #err("invalid compact length");
    let bytes = Prim.blobToArray(signature);
    let r = number(bytes, 0, 32); let s = number(bytes, 32, 32);
    if (r == 0 or r >= curve.params.r or s == 0 or s >= curve.params.r)
      return #err("invalid signature scalar");
    #ok(E.Signature(r, s, curve))
  };
  func publicKey(secret : Blob, compressed : Bool) : Result<Blob> {
    if (secret.size() != 32) return #err("invalid secret key length");
    switch (E.privateKeyFromBytes(secret.vals(), #raw({curve}))) {
      case (#err(error)) #err(error);
      case (#ok(key)) #ok(Prim.arrayToBlob(key.getPublicKey().toBytes(
        if (compressed) #compressed else #uncompressed)));
    }
  };
  func convertPublicKey(key : Blob, compressed : Bool) : Result<Blob> {
    switch (parseKey(key)) {
      case (#err(error)) #err(error);
      case (#ok(key)) #ok(Prim.arrayToBlob(key.toBytes(
        if (compressed) #compressed else #uncompressed)));
    }
  };
  func verifyPrehash(key : Blob, digest : Blob, signature : Blob) : Result<Bool> {
    let publicKey = switch (parseKey(key)) {
      case (#err(error)) return #err(error); case (#ok(value)) value;
    };
    if (digest.size() != 32) return #err("invalid digest length");
    switch (parseCompact(signature)) {
      case (#err(error)) #err(error);
      case (#ok(value)) #ok(publicKey.verifyHashed(digest.vals(), value));
    }
  };
  func signatureToDer(signature : Blob) : Result<Blob> {
    switch (parseCompact(signature)) {
      case (#err(error)) #err(error);
      case (#ok(value)) #ok(Prim.arrayToBlob(value.toBytes(#der)));
    }
  };
  func signatureFromDer(der : Blob) : Result<Blob> {
    let bytes = Prim.blobToArray(der); let size = bytes.size();
    if (size < 8 or size > 72) return #err("invalid DER length");
    if (bytes[0] != 0x30 or Prim.nat8ToNat(bytes[1]) != size - 2 or bytes[2] != 2)
      return #err("invalid DER sequence");
    let rSize = Prim.nat8ToNat(bytes[3]);
    if (rSize == 0 or rSize > 33 or rSize + 6 > size) return #err("invalid DER R length");
    if (bytes[4] >= 128 or (rSize > 1 and bytes[4] == 0 and bytes[5] < 128))
      return #err("nonminimal or negative DER R");
    let sTag = 4 + rSize;
    if (bytes[sTag] != 2) return #err("invalid DER S tag");
    let sSize = Prim.nat8ToNat(bytes[sTag + 1]); let sStart = sTag + 2;
    if (sSize == 0 or sSize > 33 or sStart + sSize != size) return #err("invalid DER S length");
    if (bytes[sStart] >= 128 or (sSize > 1 and bytes[sStart] == 0 and bytes[sStart + 1] < 128))
      return #err("nonminimal or negative DER S");
    let r = number(bytes, 4, rSize); let s = number(bytes, sStart, sSize);
    if (r == 0 or r >= curve.params.r or s == 0 or s >= curve.params.r)
      return #err("invalid DER signature scalar");
    switch (E.signatureFromBytes(der.vals(), curve, #der)) {
      case (#err(error)) #err(error);
      case (#ok(value)) #ok(Prim.arrayToBlob(value.toBytes(#raw)));
    }
  };
  func normalizeSignature(signature : Blob) : Result<Blob> {
    switch (parseCompact(signature)) {
      case (#err(error)) #err(error);
      case (#ok(value)) {
        // Use the exact mathematical half-order: P-256's package rHalf uses floor,
        // but Signature's constructor compares with < rather than <=.
        let s = if (value.original_s > curve.params.r / 2)
          curve.params.r - value.original_s else value.original_s;
        #ok(Prim.arrayToBlob(E.Signature(value.original_r, s, curve).toBytes(#raw)))
      };
    }
  };

  transient let key : Blob = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98";
  transient let digest : Blob = "\af\2b\db\e1\aa\9b\6e\c1\e2\ad\e1\d6\94\f4\1f\c7\1a\83\1d\02\68\e9\89\15\62\11\3d\8a\62\ad\d1\bf";
  transient let signature : Blob = "\58\db\65\7b\cd\63\10\38\be\a0\7b\49\41\17\2f\01\67\ac\a9\8f\12\b5\5e\31\76\bd\1c\35\43\5d\65\01\3a\78\e7\3d\8f\f8\ab\55\4e\13\c1\0f\63\90\d8\1a\88\2f\91\94\5d\62\75\49\38\82\67\61\70\b5\3a\57";
  transient var result : Blob = "";
  func unwrap<T>(value : Result<T>) : T { switch value { case (#ok x) x; case (#err _) { assert false; loop {} } } };
  public func configure() : async () {};
  public func run() : async {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat} {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := (if (unwrap(verifyPrehash(key, digest, signature))) "\01" else "\00");
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop-start; allocated = allocatedAfter-allocatedBefore;
      reclaimed = reclaimedAfter-reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob {
    let actual = result;
    assert actual == "\01";
    actual
  };
  // Round three: queried outside the measured operation.
  public query func memory() : async {
    heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat
  } {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
     totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
}
