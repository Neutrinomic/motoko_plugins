import Prim "mo:⛔";
import H "mo:fast/BLAKE3";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Bool = false;
  transient let input : Blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1024, func(i) {Prim.natToNat8(i % 251)}));
transient let key : Blob = "\77\68\61\74\73\20\74\68\65\20\45\6c\76\69\73\68\20\77\6f\72\64\20\66\6f\72\20\66\72\69\65\6e\64";
  transient let expected : Blob = "\75\c4\6f\6f\3d\9e\b4\f5\5e\ca\ae\e4\80\db\73\2e\6c\21\05\54\6f\1e\67\50\03\68\7c\31\71\9c\7b\a4";
  func verifyMac(key : Blob, message : Blob, tag : Blob) : Bool {
    if (tag.size() != 32) return false;
    let digest = switch (H.keyedHash(key, message)) {
      case (#ok(value)) value;
      case (#err(_)) return false;
    };
    var difference : Nat8 = 0;
    var i = 0;
    while (i < 32) {
      difference := difference | (digest[i] ^ tag[i]);
      i += 1;
    };
    difference == 0
  };
  func changed(bytes : Blob, index : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(bytes.size(), func(i) {
      bytes[i] ^ (if (i == index) 1 else 0)
    }))
  };

  transient var suppliedTag : Blob = "";
  public func configure() : async () { 
    assert verifyMac(key, input, expected);
    var i = 0;
    while (i < 32) {
      assert not verifyMac(key, input, changed(expected, i));
      i += 1;
    };
    assert not verifyMac(key, input, Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(31, func(i) { expected[i] })));
    assert not verifyMac(key, input, Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(33, func(i) { if (i < 32) expected[i] else 0 })));
    assert not verifyMac(changed(key, 0), input, expected);
    assert not verifyMac(key, changed(input, 0), expected);

    suppliedTag := changed(expected, 31); };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := verifyMac(key, input, suppliedTag);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { if (result) "\01" else "\00" };
}
