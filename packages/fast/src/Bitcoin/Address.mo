/// Bitcoin addresses, Taproot commitments and local key-path signing.
/// Requires sha256, ripemd160, secp256k1, base58, and bech32 plugins.
/// Implemented from BIP141, BIP173, BIP341 and BIP350; no Bitcoin package code is copied.
import Prim "mo:⛔";
import Base58Check "../Base58Check";
import Segwit "../Segwit";
import SHA256 "../SHA256";
import Secp256k1 "../Secp256k1";
import Hash "Hash";

module {
  public type Network = { #mainnet; #testnet; #regtest };
  public type Payload = {
    #p2pkh : Blob;
    #p2sh : Blob;
    #witness : { version : Nat8; program : Blob };
  };
  public type Error = {
    #invalidAddress; #wrongNetwork; #invalidLength; #invalidPublicKey;
    #invalidWitness; #invalidMerkleRoot; #invalidTweak;
    #invalidSecretKey; #invalidDigest; #invalidAuxiliaryRandomness;
  };
  public type Result<T> = { #ok : T; #err : Error };
  public type TaprootOutput = { publicKey : Blob; parity : Nat8 };

  func concat(parts : [Blob]) : Blob {
    var size = 0;
    for (part in parts.vals()) { size += part.size() };
    let output = Prim.Array_init<Nat8>(size, 0);
    var i = 0;
    for (part in parts.vals()) {
      var j = 0;
      while (j < part.size()) { output[i + j] := part[j]; j += 1 };
      i += part.size();
    };
    Prim.arrayMutToBlob(output)
  };
  func slice(bytes : Blob, start : Nat, size : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) { bytes[start + i] }))
  };
  func prefix(network : Network, script : Bool) : Nat8 {
    switch (network, script) {
      case (#mainnet, false) 0;
      case (#mainnet, true) 5;
      case (_, false) 111;
      case (_, true) 196;
    }
  };
  public func hrp(network : Network) : Text {
    switch network { case (#mainnet) "bc"; case (#testnet) "tb"; case (#regtest) "bcrt" }
  };

  /// Encode a 20-byte legacy hash or a BIP173/BIP350 witness program.
  public func encode(payload : Payload, network : Network) : Result<Text> {
    switch payload {
      case (#p2pkh hash) {
        if (hash.size() != 20) return #err(#invalidLength);
        #ok(Base58Check.encode(concat([Prim.arrayToBlob([prefix(network, false)]), hash])))
      };
      case (#p2sh hash) {
        if (hash.size() != 20) return #err(#invalidLength);
        #ok(Base58Check.encode(concat([Prim.arrayToBlob([prefix(network, true)]), hash])))
      };
      case (#witness {version; program}) {
        switch (Segwit.encode(hrp(network), version, program)) {
          case (#ok address) #ok(address);
          case (#err _) #err(#invalidWitness);
        }
      };
    }
  };

  /// Decode and require the specified network. Testnet and regtest legacy
  /// addresses share version bytes, so they cannot be distinguished on wire.
  public func decode(address : Text, network : Network) : Result<Payload> {
    switch (Segwit.decode(address)) {
      case (#ok decoded) {
        if (decoded.hrp != hrp(network)) return #err(#wrongNetwork);
        return #ok(#witness { version = decoded.version; program = decoded.program })
      };
      case (#err _) {};
    };
    switch (Base58Check.decode(address)) {
      case (#err _) #err(#invalidAddress);
      case (#ok bytes) {
        if (bytes.size() != 21) return #err(#invalidLength);
        let version = bytes[0];
        let hash = slice(bytes, 1, 20);
        if (version == prefix(network, false)) #ok(#p2pkh hash)
        else if (version == prefix(network, true)) #ok(#p2sh hash)
        else if (version == 0 or version == 5 or version == 111 or version == 196) #err(#wrongNetwork)
        else #err(#invalidAddress)
      };
    }
  };

  /// P2PKH preserves the supplied canonical compressed or uncompressed SEC1 encoding.
  public func p2pkh(publicKey : Blob, network : Network) : Result<Text> {
    if (publicKey.size() != 33 and publicKey.size() != 65) return #err(#invalidPublicKey);
    switch (Secp256k1.convertPublicKey(publicKey, publicKey.size() == 33)) {
      case (#err _) #err(#invalidPublicKey);
      case (#ok canonical) { encode(#p2pkh(Hash.hash160(canonical)), network) };
    }
  };

  public func p2sh(redeemScript : Blob, network : Network) : Result<Text> {
    encode(#p2sh(Hash.hash160(redeemScript)), network)
  };

  /// P2WPKH requires a compressed SEC1 key, as required by standard witness policy.
  public func p2wpkh(publicKey : Blob, network : Network) : Result<Text> {
    if (publicKey.size() != 33) return #err(#invalidPublicKey);
    switch (Secp256k1.convertPublicKey(publicKey, true)) {
      case (#err _) #err(#invalidPublicKey);
      case (#ok canonical) { encode(#witness {version = 0; program = Hash.hash160(canonical)}, network) };
    }
  };

  public func p2wsh(witnessScript : Blob, network : Network) : Result<Text> {
    encode(#witness {version = 0; program = SHA256.digest(witnessScript)}, network)
  };

  func taprootTweak(internalKey : Blob, merkleRoot : ?Blob) : Result<Blob> {
    if (internalKey.size() != 32) return #err(#invalidPublicKey);
    let message = switch merkleRoot {
      case (null) internalKey;
      case (?root) {
        if (root.size() != 32) return #err(#invalidMerkleRoot);
        concat([internalKey, root])
      };
    };
    #ok(Hash.taggedHash("TapTweak", message))
  };

  /// BIP341 output key Q = lift_x(internalKey) + TapTweak(internalKey || root) * G.
  /// A null root means no script tree, as in BIP86. A supplied root must be 32 bytes.
  /// The native scalar parser rejects tweaks >= the group order (not the field prime).
  public func taprootOutputKey(internalKey : Blob, merkleRoot : ?Blob) : Result<TaprootOutput> {
    let tweak = switch (taprootTweak(internalKey, merkleRoot)) {
      case (#ok value) value; case (#err error) return #err(error);
    };
    switch (Secp256k1.tweakXOnlyPublicKey(internalKey, tweak)) {
      case (#err(#invalidPublicKey)) #err(#invalidPublicKey);
      case (#err _) #err(#invalidTweak);
      case (#ok compressed) #ok({ publicKey = slice(compressed, 1, 32); parity = compressed[0] - 2 });
    }
  };

  /// Derive the local Taproot signing secret from an internal secret and optional
  /// script-tree root. Native code normalizes the internal point to even Y,
  /// adds the scalar tweak, and rejects an invalid or zero resulting secret.
  /// The returned scalar corresponds to the actual output point; BIP340 signing
  /// normalizes the output parity separately, as the signature algorithm requires.
  public func taprootSecretKey(internalSecret : Blob, merkleRoot : ?Blob) : Result<Blob> {
    let publicKey = switch (Secp256k1.derivePublicKey(internalSecret)) {
      case (#ok value) value; case (#err _) return #err(#invalidSecretKey);
    };
    let tweak = switch (taprootTweak(slice(publicKey, 1, 32), merkleRoot)) {
      case (#ok value) value; case (#err error) return #err(error);
    };
    switch (Secp256k1.tweakXOnlySecretKey(internalSecret, tweak)) {
      case (#ok value) #ok(value);
      case (#err _) #err(#invalidTweak);
    }
  };

  /// Sign a 32-byte BIP341 key-path sighash with a local internal secret.
  /// `auxiliaryRandomness` is exactly 32 bytes, supplied by the caller. Returns
  /// the 64-byte Schnorr signature; append a nonzero sighash-type byte when using
  /// a mode other than SIGHASH_DEFAULT. Pass the digest from Transaction's
  /// signatureHashTaproot; this function neither serializes nor rehashes it.
  public func signTaprootKeyPath(internalSecret : Blob, merkleRoot : ?Blob, sighash : Blob, auxiliaryRandomness : Blob) : Result<Blob> {
    if (sighash.size() != 32) return #err(#invalidDigest);
    if (auxiliaryRandomness.size() != 32) return #err(#invalidAuxiliaryRandomness);
    let secret = switch (taprootSecretKey(internalSecret, merkleRoot)) {
      case (#ok value) value; case (#err error) return #err(error);
    };
    switch (Secp256k1.schnorrSign(secret, sighash, auxiliaryRandomness)) {
      case (#ok value) #ok(value);
      case (#err _) #err(#invalidTweak);
    }
  };

  /// Encode a tweaked Taproot output key. Use p2tr to derive it from an internal key.
  public func p2trOutput(outputKey : Blob, network : Network) : Result<Text> {
    if (outputKey.size() != 32) return #err(#invalidPublicKey);
    switch (Secp256k1.convertPublicKey(concat(["\02", outputKey]), true)) {
      case (#err _) #err(#invalidPublicKey);
      case (#ok _) encode(#witness {version = 1; program = outputKey}, network);
    }
  };

  public func p2tr(internalKey : Blob, merkleRoot : ?Blob, network : Network) : Result<Text> {
    switch (taprootOutputKey(internalKey, merkleRoot)) {
      case (#err error) #err(error);
      case (#ok output) encode(#witness {version = 1; program = output.publicKey}, network);
    }
  };

  /// Standard locking script for a validated address, including future witness versions.
  public func scriptPubKey(address : Text, network : Network) : Result<Blob> {
    switch (decode(address, network)) {
      case (#err error) #err(error);
      case (#ok(#p2pkh hash)) #ok(concat(["\76\a9\14", hash, "\88\ac"]));
      case (#ok(#p2sh hash)) #ok(concat(["\a9\14", hash, "\87"]));
      case (#ok(#witness {version; program})) {
        let opcode : Nat8 = if (version == 0) 0 else 0x50 + version;
        #ok(concat([Prim.arrayToBlob([opcode, Prim.natToNat8(program.size())]), program]))
      };
    }
  };
}
