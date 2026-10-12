import Prim "mo:⛔";
import T "mo:fast/Bitcoin/Transaction";
import A "mo:core/Array";
import B "mo:core/Blob";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : [Blob] = [];
  transient let tx : T.Tx = {version = 2; inputs = [{previousTxid = "\dc\dd\f4\13\3e\65\b9\51\d5\40\aa\47\0a\c6\2d\7d\a2\ac\0b\03\03\49\33\be\71\59\d3\ad\0c\8d\65\44"; previousIndex = 0; scriptSig = ""; sequence = 4294967293; witness = []}]; outputs = [{value = 90000; scriptPubKey = "\00\14\71\9e\49\da\51\c4\83\a2\32\33\73\87\ed\06\0d\fc\2b\02\2c\e2"},
{value = 8000; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"}]; lockTime = 850000};
transient let prevouts : [T.Output] = [{value = 100000; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"}];
transient let scriptCode : Blob = "\76\a9\14\5a\54\b6\b3\6d\b6\7d\33\ff\2d\52\eb\25\5f\64\d0\c1\0f\43\b6\88\ac";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := A.tabulate<Blob>(1, func(i) { let ?value = T.signatureHashTaproot(tx, i, prevouts, 0, null, null) else Prim.trap("native sighash"); value });
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { B.fromArray(A.flatten<Nat8>(A.map<Blob, [Nat8]>(result, B.toArray))) };
}
