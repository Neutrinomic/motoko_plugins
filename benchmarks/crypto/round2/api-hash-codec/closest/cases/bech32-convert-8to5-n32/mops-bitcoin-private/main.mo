import Prim "mo:⛔";
import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import VarArray "mo:core/VarArray";
import { type Result } "mo:core/Types";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
    func convertBits(
    data : [Nat8],
    start : Nat,
    from : Nat32,
    to : Nat32,
    pad : Bool,
  ) : Result<[Nat8], Text> {

    var acc : Nat32 = 0;
    var bits : Nat32 = 0;
    let maxv : Nat32 = (1 << to) - 1;
    let dataSize = data.size();
    let output = VarArray.repeat<Nat8>(0, (dataSize - start) * from.toNat() / to.toNat() + 1);
    var outputLen : Nat = 0;

    var pos = start;
    while (pos < dataSize) {
      let v : Nat32 = data[pos].toNat16().toNat32();

      if ((v >> from) != 0) {
        return #err("Invalid input value: " # data[pos].toNat().toText());
      };

      acc := (acc << from) | v;
      bits += from;

      while (bits >= to) {
        bits -= to;
        output[outputLen] := ((acc >> bits) & maxv).toNat16().toNat8();
        outputLen += 1;
      };
      pos += 1;
    };

    if (pad) {
      if (bits > 0) {
        output[outputLen] := ((acc << (to - bits)) & maxv).toNat16().toNat8();
        outputLen += 1;
      };
    } else if (bits >= from or ((acc << (to - bits)) & maxv) != 0) {
      return #err("Invalid Padding");
    };

    #ok(Array.tabulate<Nat8>(outputLen, func(i) = output[i]));
  };
 transient let input : Blob = "\29\72\bb\04\4d\96\df\28\71\ba\03\4c\95\de\27\70\b9\02\4b\94\dd\26\6f\b8\01\4a\93\dc\25\6e\b7\00";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := switch (convertBits(Prim.blobToArray(input), 0, 8, 5, true)) { case (#ok(value)) Prim.arrayToBlob(value); case (#err(_)) Prim.trap("unexpected conversion error") };
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
