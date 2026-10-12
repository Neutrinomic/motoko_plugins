/// BIP32 extended public keys, composed from the HMAC-SHA2, secp256k1,
/// SHA256, RIPEMD160 and Base58 plugins. Supports xpub and tpub encodings.
///
/// Public derivation accepts only non-hardened child indices. Existing keys
/// reached through hardened private derivation can still be imported.
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Prim "mo:⛔";
import VarArray "mo:core/VarArray";
import Base58Check "../Base58Check";
import HMAC "../HMAC";
import Secp256k1 "../Secp256k1";
import Hash "Hash";

module {
  public type Network = { #mainnet; #testnet };

  /// Stable data with a compressed SEC1 public key, 32-byte chain code and
  /// 4-byte parent fingerprint. All operations validate caller-built records.
  public type ExtendedPublicKey = {
    network : Network;
    publicKey : Blob;
    chainCode : Blob;
    depth : Nat8;
    parentFingerprint : Blob;
    childIndex : Nat32;
  };

  public type Error = {
    #invalidBase58Check;
    #invalidLength;
    #unsupportedVersion;
    #invalidPublicKey;
    #invalidChainCode;
    #invalidFingerprint;
    #invalidMaster;
    #hardenedChild;
    #maximumDepth;
    #invalidChild;
    #invalidPath;
  };
  public type Result<T> = { #ok : T; #err : Error };

  func slice(bytes : Blob, start : Nat, size : Nat) : Blob {
    Blob.fromArray(Array.tabulate<Nat8>(size, func(i) { bytes[start + i] }))
  };

  func read32(bytes : Blob, start : Nat) : Nat32 {
    Nat32.fromNat8(bytes[start]) << 24 |
    Nat32.fromNat8(bytes[start + 1]) << 16 |
    Nat32.fromNat8(bytes[start + 2]) << 8 |
    Nat32.fromNat8(bytes[start + 3])
  };

  func write32(bytes : [var Nat8], start : Nat, value : Nat32) {
    bytes[start] := Nat8.fromNat32((value >> 24) & 255);
    bytes[start + 1] := Nat8.fromNat32((value >> 16) & 255);
    bytes[start + 2] := Nat8.fromNat32((value >> 8) & 255);
    bytes[start + 3] := Nat8.fromNat32(value & 255);
  };

  func copy(bytes : [var Nat8], start : Nat, source : Blob) {
    var i = 0;
    while (i < source.size()) { bytes[start + i] := source[i]; i += 1 };
  };

  func validate(key : ExtendedPublicKey) : Result<()> {
    if (key.chainCode.size() != 32) return #err(#invalidChainCode);
    if (key.parentFingerprint.size() != 4) return #err(#invalidFingerprint);
    if (key.depth == 0 and (key.childIndex != 0 or key.parentFingerprint != "\00\00\00\00")) {
      return #err(#invalidMaster);
    };
    if (key.publicKey.size() != 33) return #err(#invalidPublicKey);
    switch (Secp256k1.convertPublicKey(key.publicKey, true)) {
      case (#ok(encoded)) {
        if (encoded != key.publicKey) return #err(#invalidPublicKey);
        #ok(())
      };
      case (#err(_)) #err(#invalidPublicKey);
    }
  };

  /// Build a depth-zero key from a compressed or uncompressed SEC1 public
  /// key and a 32-byte chain code. The resulting public key is compressed.
  public func fromPublicKey(publicKey : Blob, chainCode : Blob, network : Network) : Result<ExtendedPublicKey> {
    if (chainCode.size() != 32) return #err(#invalidChainCode);
    switch (Secp256k1.convertPublicKey(publicKey, true)) {
      case (#err(_)) #err(#invalidPublicKey);
      case (#ok(compressed)) #ok({
        network;
        publicKey = compressed;
        chainCode;
        depth = 0;
        parentFingerprint = "\00\00\00\00";
        childIndex = 0;
      });
    }
  };

  /// First four bytes of HASH160 of the compressed SEC1 public key.
  /// Fingerprints can collide and are not proof of a parent relationship.
  public func fingerprint(publicKey : Blob) : Result<Blob> {
    switch (Secp256k1.convertPublicKey(publicKey, true)) {
      case (#err(_)) #err(#invalidPublicKey);
      case (#ok(compressed)) #ok(fingerprintCompressed(compressed));
    }
  };

  func fingerprintCompressed(publicKey : Blob) : Blob {
    slice(Hash.hash160(publicKey), 0, 4)
  };

  /// Parse an xpub/tpub, checking the checksum, exact payload length,
  /// version, depth-zero metadata and compressed curve point. Parent
  /// fingerprints are retained without claiming to verify parent identity.
  public func parse(encoded : Text) : Result<ExtendedPublicKey> {
    let payload = switch (Base58Check.decode(encoded)) {
      case (#err(_)) return #err(#invalidBase58Check);
      case (#ok(bytes)) bytes;
    };
    if (payload.size() != 78) return #err(#invalidLength);
    let bytes = payload;
    let network : Network = switch (read32(bytes, 0)) {
      case (0x0488b21e) #mainnet;
      case (0x043587cf) #testnet;
      case (_) return #err(#unsupportedVersion);
    };
    let key : ExtendedPublicKey = {
      network;
      publicKey = slice(bytes, 45, 33);
      chainCode = slice(bytes, 13, 32);
      depth = bytes[4];
      parentFingerprint = slice(bytes, 5, 4);
      childIndex = read32(bytes, 9);
    };
    switch (validate(key)) {
      case (#err(error)) #err(error);
      case (#ok(())) #ok(key);
    }
  };

  /// Serialize validated metadata to the canonical xpub/tpub representation.
  public func serialize(key : ExtendedPublicKey) : Result<Text> {
    switch (validate(key)) {
      case (#err(error)) return #err(error);
      case (#ok(())) {};
    };
    let bytes = VarArray.repeat<Nat8>(0, 78);
    write32(bytes, 0, switch (key.network) {
      case (#mainnet) 0x0488b21e;
      case (#testnet) 0x043587cf;
    });
    bytes[4] := key.depth;
    copy(bytes, 5, key.parentFingerprint);
    write32(bytes, 9, key.childIndex);
    copy(bytes, 13, key.chainCode);
    copy(bytes, 45, key.publicKey);
    #ok(Base58Check.encode(Blob.fromVarArray(bytes)))
  };

  // The caller has already validated key. Keeping validation outside this
  // helper avoids decoding every intermediate curve point during a path.
  func child(key : ExtendedPublicKey, index : Nat32) : Result<ExtendedPublicKey> {
    if (index >= 0x80000000) return #err(#hardenedChild);
    if (key.depth == 255) return #err(#maximumDepth);
    let data = VarArray.repeat<Nat8>(0, 37);
    copy(data, 0, key.publicKey);
    write32(data, 33, index);
    let node = HMAC.sha512(key.chainCode, Blob.fromVarArray(data));
    // A zero tweak is valid for CKDpub; an out-of-range tweak or the point
    // at infinity is rejected by the secp256k1 plugin.
    let publicKey = switch (Secp256k1.tweakPublicKey(key.publicKey, slice(node, 0, 32))) {
      case (#err(_)) return #err(#invalidChild);
      case (#ok(point)) point;
    };
    #ok({
      network = key.network;
      publicKey;
      chainCode = slice(node, 32, 32);
      depth = key.depth + 1;
      parentFingerprint = fingerprintCompressed(key.publicKey);
      childIndex = index;
    })
  };

  /// Derive the exact non-hardened child index. The exceptionally rare
  /// invalid result returns #invalidChild; callers can explicitly try the
  /// next index, as BIP32 prescribes. The index is never silently changed.
  public func deriveChild(key : ExtendedPublicKey, index : Nat32) : Result<ExtendedPublicKey> {
    switch (validate(key)) {
      case (#err(error)) #err(error);
      case (#ok(())) child(key, index);
    }
  };

  /// Derive a path relative to key. An empty array returns the validated key.
  public func derivePath(key : ExtendedPublicKey, indices : [Nat32]) : Result<ExtendedPublicKey> {
    switch (validate(key)) {
      case (#err(error)) return #err(error);
      case (#ok(())) {};
    };
    if (Nat8.toNat(key.depth) + indices.size() > 255) return #err(#maximumDepth);
    var result = key;
    for (index in indices.values()) {
      result := switch (child(result, index)) {
        case (#err(error)) return #err(error);
        case (#ok(next)) next;
      };
    };
    #ok(result)
  };

  /// Parse decimal non-hardened indices, e.g. "0/1", "m/0/1" or "M/0/1".
  /// "m" and "M" denote an empty root path. Empty input, whitespace, empty
  /// segments, signs and hardened suffixes (', h, H) are rejected. Numeric
  /// indices >= 2^31 return #hardenedChild. At most 255 indices are accepted.
  /// This parser returns indices only; deriveTextPath enforces root depth.
  public func parsePath(path : Text) : Result<[Nat32]> {
    let bytes = Prim.encodeUtf8(path);
    let n = bytes.size();
    let absolute = n != 0 and (bytes[0] == 0x6d or bytes[0] == 0x4d) and (n == 1 or bytes[1] == 0x2f);
    if (absolute and n == 1) return #ok([]);
    let start = if (absolute) 2 else 0;
    // Count first so maximum-depth errors retain precedence over malformed segments.
    var size = 1;
    var i = start;
    while (i < n) { if (bytes[i] == 0x2f) size += 1; i += 1 };
    if (size > 255) return #err(#maximumDepth);
    let indices = VarArray.repeat<Nat32>(0, size);
    i := start;
    var segment = 0;
    while (segment < size) {
      let begin = i;
      var value : Nat = 0;
      while (i < n and bytes[i] != 0x2f) {
        let byte = bytes[i];
        if (byte < 0x30 or byte > 0x39) return #err(#invalidPath);
        value := value * 10 + Nat8.toNat(byte - 0x30);
        if (value >= 0x80000000) return #err(#hardenedChild);
        i += 1;
      };
      if (i == begin) return #err(#invalidPath);
      indices[segment] := Nat32.fromNat(value);
      segment += 1;
      i += 1;
    };
    #ok(VarArray.toArray(indices))
  };

  /// Derive a textual public path. A leading m/M is absolute and requires
  /// depth zero; omit it when deriving relative to an imported account key.
  public func deriveTextPath(key : ExtendedPublicKey, path : Text) : Result<ExtendedPublicKey> {
    switch (path.chars().next()) {
      case (?'m' or ?'M') {
        if (key.depth != 0) return #err(#invalidPath);
      };
      case (_) {};
    };
    switch (parsePath(path)) {
      case (#err(error)) #err(error);
      case (#ok(indices)) derivePath(key, indices);
    }
  };
}
