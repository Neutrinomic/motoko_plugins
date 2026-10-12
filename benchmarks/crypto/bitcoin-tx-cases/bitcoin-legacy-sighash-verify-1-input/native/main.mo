import Prim "mo:⛔";
import T "mo:fast/Bitcoin/Transaction";
import A "mo:core/Array";
import B "mo:core/Blob";
import C "mo:fast/Secp256k1";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Bool = false;
  transient let tx : T.Tx = {version = 2; inputs = [{previousTxid = "\dc\dd\f4\13\3e\65\b9\51\d5\40\aa\47\0a\c6\2d\7d\a2\ac\0b\03\03\49\33\be\71\59\d3\ad\0c\8d\65\44"; previousIndex = 0; scriptSig = ""; sequence = 4294967293; witness = []}]; outputs = [{value = 90000; scriptPubKey = "\00\14\71\9e\49\da\51\c4\83\a2\32\33\73\87\ed\06\0d\fc\2b\02\2c\e2"},
{value = 8000; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"}]; lockTime = 850000};
transient let prevouts : [T.Output] = [{value = 100000; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"}];
transient let scriptCode : Blob = "\76\a9\14\5a\54\b6\b3\6d\b6\7d\33\ff\2d\52\eb\25\5f\64\d0\c1\0f\43\b6\88\ac";
transient let publicKey : Blob = "\03\3d\e4\db\4d\ba\29\cd\84\f7\60\25\cc\e8\ee\80\5d\b7\8a\91\62\63\3d\e0\a8\23\09\ba\4d\4b\dd\a0\94"; transient let signature : Blob = "\d0\bf\ec\68\30\08\1b\d5\91\24\93\cf\c1\9f\f0\89\8a\35\6d\a4\6b\8b\9c\2b\fa\d9\cc\48\82\00\e3\54\2a\22\0c\0d\ee\c9\47\19\8c\9b\9e\37\d3\cb\88\b5\a4\a8\04\84\7a\af\39\1e\72\b9\82\c0\b6\98\f9\88";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    let ?digest = T.signatureHashLegacy(tx, 0, scriptCode, 1) else Prim.trap("sighash"); let #ok(valid) = C.verifyPrehash(publicKey, digest, signature) else Prim.trap("verify"); result := valid;
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { if (result) "\01" else "\00" };
}
