/// Bitcoin Base58Check, composed from the `base58` and `sha256` plugins.
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Runtime "mo:core/Runtime";
import Base58 "Base58";
import SHA256 "SHA256";

module {
  public type Error = {
    #tooLarge;
    #invalidCharacter : Nat64;
    #tooShort;
    #invalidChecksum;
  };
  public type Result<T> = { #ok : T; #err : Error };
  public let maxPayloadBytes : Nat = 4092;

  /// Append the first four bytes of double SHA-256 and Base58-encode.
  /// The caller supplies the complete payload, including any version bytes.
  /// Empty payload is allowed. Traps above `maxPayloadBytes`.
  public func encode(payload : Blob) : Text {
    let size = payload.size();
    if (size > maxPayloadBytes) {
      Runtime.trap("Base58Check.encode payload exceeds 4092 bytes")
    };
    let check = SHA256.digest(SHA256.digest(payload));
    let bytes = Array.tabulate<Nat8>(size + 4, func(i) {
      if (i < size) payload[i] else check[i - size]
    });
    Base58.encode(Blob.fromArray(bytes))
  };

  /// Verify and remove the four checksum bytes, retaining all version bytes.
  /// Alphabet and resource limits are the same as `Base58.decode`.
  public func decode(text : Text) : Result<Blob> {
    switch (Base58.decode(text)) {
      case (#err error) #err error;
      case (#ok bytes) {
        if (bytes.size() < 4) return #err(#tooShort);
        let size = bytes.size() - 4;
        let payload = Blob.fromArray(Array.tabulate<Nat8>(size, func(i) { bytes[i] }));
        let check = SHA256.digest(SHA256.digest(payload));
        var difference : Nat8 = 0;
        var i = 0;
        while (i < 4) {
          difference := difference | (check[i] ^ bytes[size + i]);
          i += 1;
        };
        if (difference != 0) #err(#invalidChecksum) else #ok payload
      };
    }
  };
}
