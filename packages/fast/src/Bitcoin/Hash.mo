/// Bitcoin hashes composed from the `sha256` and `ripemd160` plugins.
import Prim "mo:⛔";
import SHA256 "../SHA256";
import RIPEMD160 "../RIPEMD160";

module {
  /// SHA-256 followed by RIPEMD-160, in digest byte order.
  public func hash160(message : Blob) : Blob { RIPEMD160.digest(SHA256.digest(message)) };

  /// Double SHA-256, in digest byte order. Transaction display IDs reverse it.
  public func sha256d(message : Blob) : Blob { SHA256.digest(SHA256.digest(message)) };

  /// Compatibility spelling for a double SHA-256 digest.
  public let digest256 = sha256d;

  func tagged(tagHash : Blob, message : Blob) : Blob {
    let output = Prim.Array_init<Nat8>(64 + message.size(), 0);
    var i = 0;
    while (i < 32) { output[i] := tagHash[i]; output[i + 32] := tagHash[i]; i += 1 };
    i := 0;
    while (i < message.size()) { output[i + 64] := message[i]; i += 1 };
    SHA256.digest(Prim.arrayMutToBlob(output))
  };

  /// BIP340 tagged SHA-256: SHA256(SHA256(UTF8(tag)) || SHA256(UTF8(tag)) || message).
  public func taggedHash(tag : Text, message : Blob) : Blob { tagged(SHA256.digest(Prim.encodeUtf8(tag)), message) };

  /// Cache the tag digest when hashing many messages in the same domain.
  public func taggedHasher(tag : Text) : Blob -> Blob {
    let tagHash = SHA256.digest(Prim.encodeUtf8(tag));
    func(message : Blob) : Blob { tagged(tagHash, message) }
  };
}
