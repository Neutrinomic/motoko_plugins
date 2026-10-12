/// Bitcoin output-script and data-push builders. Scripts are raw bytes, without
/// the CompactSize prefix used when they are serialized inside transactions.
/// Importing this module requires `sha256` for its Taproot commitment helpers.
/// Commitments follow https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki.
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import SHA256 "../SHA256";
import Prim "mo:⛔";

module {
  func join(prefix : [Nat8], data : Blob, suffix : [Nat8]) : Blob {
    let bytes = Prim.Array_init<Nat8>(prefix.size() + data.size() + suffix.size(), 0);
    var i = 0;
    for (b in prefix.values()) { bytes[i] := b; i += 1 };
    var j = 0;
    while (j < data.size()) { bytes[i] := data[j]; i += 1; j += 1 };
    for (b in suffix.values()) { bytes[i] := b; i += 1 };
    Prim.arrayMutToBlob(bytes)
  };

  /// Encode a minimally encoded data push, including OP_0, OP_1NEGATE and OP_1..16.
  /// Returns null above the PUSHDATA4 length limit. Execution rules may impose
  /// smaller stack-element limits (usually 520 bytes).
  public func pushData(data : Blob) : ?Blob {
    let n = data.size();
    if (n == 0) return ?"\00";
    if (n == 1) {
      let b = data.values().next();
      switch b {
        case (?0x81) return ?"\4f";
        case (?v) { if (v >= 1 and v <= 16) return ?Blob.fromArray([v + 0x50]) };
        case null {};
      };
    };
    if (n < 76) return ?join([Nat8.fromNat(n)], data, []);
    if (n <= 0xff) return ?join([0x4c, Nat8.fromNat(n)], data, []);
    if (n <= 0xffff) return ?join([0x4d, Nat8.fromNat(n % 256), Nat8.fromNat(n / 256)], data, []);
    if (n > 0xffff_ffff) return null;
    ?join([0x4e, Nat8.fromNat(n % 256), Nat8.fromNat(n / 256 % 256), Nat8.fromNat(n / 65536 % 256), Nat8.fromNat(n / 16777216)], data, [])
  };

  /// P2PKH output script from a 20-byte HASH160 public-key digest.
  public func p2pkh(publicKeyHash : Blob) : ?Blob {
    if (publicKeyHash.size() != 20) return null;
    ?join([0x76, 0xa9, 0x14], publicKeyHash, [0x88, 0xac])
  };

  /// P2SH output script from a 20-byte HASH160 redeem-script digest.
  public func p2sh(scriptHash : Blob) : ?Blob {
    if (scriptHash.size() != 20) return null;
    ?join([0xa9, 0x14], scriptHash, [0x87])
  };

  /// Witness output script. Version 0 requires a 20- or 32-byte program;
  /// versions 1..16 permit 2..40 bytes. This does not interpret future versions.
  public func witnessProgram(version : Nat8, program : Blob) : ?Blob {
    let n = program.size();
    if (version > 16 or n < 2 or n > 40) return null;
    if (version == 0 and n != 20 and n != 32) return null;
    ?join([if (version == 0) 0 else 0x50 + version, Nat8.fromNat(n)], program, [])
  };

  public func p2wpkh(publicKeyHash : Blob) : ?Blob {
    if (publicKeyHash.size() != 20) return null;
    witnessProgram(0, publicKeyHash)
  };

  public func p2wsh(scriptHash : Blob) : ?Blob {
    if (scriptHash.size() != 32) return null;
    witnessProgram(0, scriptHash)
  };

  /// P2TR output script from an already tweaked 32-byte x-only output key.
  public func p2tr(outputKey : Blob) : ?Blob {
    if (outputKey.size() != 32) return null;
    witnessProgram(1, outputKey)
  };
  func compact(n : Nat) : [Nat8] {
    if (n < 253) return [Nat8.fromNat(n)];
    let width = if (n <= 0xffff) 2 else if (n <= 0xffff_ffff) 4 else 8;
    Array.tabulate<Nat8>(width + 1, func(i) {
      if (i == 0) (if (width == 2) 0xfd else if (width == 4) 0xfe else 0xff)
      else Nat8.fromNat(n / 256 ** (i - 1) % 256)
    })
  };

  // SHA256 of the UTF-8 protocol tags, fixed by BIP341.
  let tapLeafTag : Blob = "\ae\ea\8f\dc\42\08\98\31\05\73\4b\58\08\1d\1e\26\38\d3\5f\1c\b5\40\08\d4\d3\57\ca\03\be\78\e9\ee";
  let tapBranchTag : Blob = "\19\41\a1\f2\e5\6e\b9\5f\a2\a9\f1\94\be\5c\01\f7\21\6f\33\ed\82\b0\91\46\34\90\d0\5b\f5\16\a0\15";

  func tagPrefix(tag : Blob, size : Nat) : [var Nat8] {
    let bytes = Prim.Array_init<Nat8>(size, 0);
    var i = 0;
    while (i < 32) { bytes[i] := tag[i]; bytes[i + 32] := tag[i]; i += 1 };
    bytes
  };

  /// BIP341 TapLeaf hash over an even leaf version and a CompactSize-prefixed
  /// script. Current tapscript uses 0xc0. Requires the `sha256` compiler plugin.
  /// This computes the commitment only; future versions need their own rules.
  public func tapLeafHash(script : Blob, leafVersion : Nat8) : ?Blob {
    if (leafVersion & 1 != 0 or script.size() > 0xffff_ffff_ffff_ffff) return null;
    let length = compact(script.size());
    let bytes = tagPrefix(tapLeafTag, 65 + length.size() + script.size());
    bytes[64] := leafVersion;
    var i = 65;
    for (b in length.values()) { bytes[i] := b; i += 1 };
    var j = 0;
    while (j < script.size()) { bytes[i] := script[j]; i += 1; j += 1 };
    ?SHA256.digest(Prim.arrayMutToBlob(bytes))
  };

  /// BIP341 TapBranch hash. Children must be 32-byte hashes; their order is
  /// normalized lexicographically, as required by Taproot commitments.
  public func tapBranchHash(left : Blob, right : Blob) : ?Blob {
    if (left.size() != 32 or right.size() != 32) return null;
    let (first, second) = if (left < right) (left, right) else (right, left);
    let bytes = tagPrefix(tapBranchTag, 128);
    var i = 0;
    while (i < 32) { bytes[i + 64] := first[i]; bytes[i + 96] := second[i]; i += 1 };
    ?SHA256.digest(Prim.arrayMutToBlob(bytes))
  };

}
