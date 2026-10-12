/// Segregated witness address encoding per BIP173/BIP350. Requires `bech32`.
import Bech32 "Bech32";
import Blob "mo:core/Blob";
import Array "mo:core/Array";

module {
  public type Error = Bech32.Error or {
    #invalidWitnessVersion; #invalidWitnessProgram; #wrongEncoding;
  };
  public type Result<T> = { #ok : T; #err : Error };
  public type Decoded = { hrp : Text; version : Nat8; program : Blob };

  func validLength(version : Nat8, size : Nat) : Bool {
    size >= 2 and size <= 40 and (version != 0 or size == 20 or size == 32)
  };

  /// Versions 0..16; programs 2..40 bytes (v0 requires 20 or 32). Version 0
  /// uses Bech32; later versions use Bech32m. The caller chooses the network HRP.
  public func encode(hrp : Text, version : Nat8, program : Blob) : Result<Text> {
    if (version > 16) return #err(#invalidWitnessVersion);
    if (not validLength(version, program.size())) return #err(#invalidWitnessProgram);
    switch (Bech32.convertBits(program, 8, 5, true)) {
      case (#err error) #err(error);
      case (#ok converted) {
        let data = Blob.fromArray(Array.concat<Nat8>([version], Blob.toArray(converted)));
        Bech32.encode(hrp, data, if (version == 0) #bech32 else #bech32m)
      };
    }
  };

  /// Verify checksum, version, program length, padding and checksum variant.
  /// HRPs are generic: callers must compare `hrp` with their expected network.
  public func decode(address : Text) : Result<Decoded> {
    switch (Bech32.decode(address)) {
      case (#err error) #err(error);
      case (#ok decoded) {
        let data = Blob.toArray(decoded.data);
        if (data.size() == 0 or data[0] > 16) return #err(#invalidWitnessVersion);
        let version = data[0];
        let packed = Blob.fromArray(Array.tabulate<Nat8>(data.size() - 1, func(i) { data[i + 1] }));
        switch (Bech32.convertBits(packed, 5, 8, false)) {
          case (#err error) #err(error);
          case (#ok program) {
            if (not validLength(version, program.size())) return #err(#invalidWitnessProgram);
            if ((version == 0 and decoded.encoding != #bech32) or
                (version != 0 and decoded.encoding != #bech32m)) return #err(#wrongEncoding);
            #ok({ hrp = decoded.hrp; version; program })
          };
        }
      };
    }
  };
}
