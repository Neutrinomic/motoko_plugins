import Prim "mo:⛔";
import T "mo:bitcoin/bitcoin/Transaction";
import S "mo:bitcoin/bitcoin/Script";
import A "mo:core/Array";
import B "mo:core/Blob";
import N32 "mo:core/Nat32";
import E "mo:ecdsa";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Bool = false;
  transient var tx : ?T.Transaction = null;
transient var script : S.Script = [];
transient var tapScript : S.Script = [];
transient let amounts : [Nat64] = [100000];
transient let curve = E.Curve(#secp256k1);
transient let publicKey = E.PublicKey(27995438472319844750992790748024825379343533308901948937279607600408906539156, 24709589477967370822707259984895160576895811622420279240703072547268707019185, curve);
transient let signature = E.Signature(94420171915722701882436353466280373948898995751932424584614329783678524253012, 19057295637282247812707595459955705100215163648289830841035841369621701130632, curve);
  public func configure() : async () { let #ok(value) = T.fromBytes(("\02\00\00\00\01\dc\dd\f4\13\3e\65\b9\51\d5\40\aa\47\0a\c6\2d\7d\a2\ac\0b\03\03\49\33\be\71\59\d3\ad\0c\8d\65\44\00\00\00\00\00\fd\ff\ff\ff\02\90\5f\01\00\00\00\00\00\16\00\14\71\9e\49\da\51\c4\83\a2\32\33\73\87\ed\06\0d\fc\2b\02\2c\e2\40\1f\00\00\00\00\00\00\22\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21\50\f8\0c\00" : Blob).values()) else Prim.trap("baseline transaction"); tx := ?value;
let #ok(legacyScript) = S.fromBytes(("\76\a9\14\5a\54\b6\b3\6d\b6\7d\33\ff\2d\52\eb\25\5f\64\d0\c1\0f\43\b6\88\ac" : Blob).values(), false) else Prim.trap("legacy script"); script := legacyScript;
let #ok(tap) = S.fromBytes(("\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21" : Blob).values(), false) else Prim.trap("Taproot script"); tapScript := tap; };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    let ?value = tx else Prim.trap("configure first"); let digest = value.createP2pkhSignatureHash(script, 0, 1); result := publicKey.verifyHashed(digest.values(), signature);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { if (result) "\01" else "\00" };
}
