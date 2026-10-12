import Prim "mo:⛔";
import M "mo:fast/Bitcoin/Transaction";
import BA "mo:core/Array";
import BB "mo:core/Blob";

persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  func unwrap<T,E>(r : {#ok:T;#err:E}) : T {switch r {case(#ok(x))x;case(#err(_))Prim.trap("unexpected error")}};
func some<T>(r : ?T) : T {switch r {case(?x)x;case(null)Prim.trap("unexpected null")}};
transient let tx : M.Tx = {version = 2; inputs = [{previousTxid = "\dc\dd\f4\13\3e\65\b9\51\d5\40\aa\47\0a\c6\2d\7d\a2\ac\0b\03\03\49\33\be\71\59\d3\ad\0c\8d\65\44"; previousIndex = 0; scriptSig = ""; sequence = 4294967293; witness = []},
{previousTxid = "\32\a3\b4\59\f1\d2\9d\0a\52\3e\8f\05\5d\ee\33\d4\f3\d5\74\d8\71\e6\37\c5\c4\57\36\36\c4\42\63\0f"; previousIndex = 1; scriptSig = ""; sequence = 4294967292; witness = []},
{previousTxid = "\26\c9\98\40\37\8b\fb\91\a1\24\f2\85\40\5e\a2\6f\22\1c\4a\02\49\59\4e\9c\bc\fa\1c\9b\4b\72\9e\ab"; previousIndex = 2; scriptSig = ""; sequence = 4294967291; witness = []},
{previousTxid = "\90\88\35\4f\49\89\31\62\ad\a7\21\90\ee\c9\4f\69\2f\2c\97\c5\9f\07\33\27\db\0a\59\d0\ae\20\cd\0a"; previousIndex = 0; scriptSig = ""; sequence = 4294967290; witness = []},
{previousTxid = "\7d\5a\a0\8a\b9\a5\cd\ac\cc\62\41\bb\c2\c8\59\3e\b0\d1\3b\84\ac\54\ba\8f\dd\d7\74\04\37\29\7c\78"; previousIndex = 1; scriptSig = ""; sequence = 4294967289; witness = []},
{previousTxid = "\f9\5c\6c\9a\2f\99\a8\fe\34\40\f2\d6\14\f5\8c\45\48\ad\73\f7\50\dc\50\77\7e\ed\40\3e\83\d4\b6\37"; previousIndex = 2; scriptSig = ""; sequence = 4294967288; witness = []},
{previousTxid = "\51\24\09\6a\1f\e3\32\39\f9\52\bd\50\d0\3c\c8\ae\90\46\75\2b\aa\fc\d8\61\ff\01\fe\b9\d9\d6\a7\79"; previousIndex = 0; scriptSig = ""; sequence = 4294967287; witness = []},
{previousTxid = "\ad\b5\b7\12\2c\2d\f5\c0\d6\50\48\6b\c5\9c\23\70\01\51\b0\47\4a\21\5e\e1\9c\05\86\85\66\ad\20\c5"; previousIndex = 1; scriptSig = ""; sequence = 4294967286; witness = []},
{previousTxid = "\c3\9a\ea\0f\65\a3\a0\fc\79\79\7f\03\37\e5\3c\90\35\cd\ff\af\a6\0d\df\fa\6f\7b\e1\09\ad\61\5e\cf"; previousIndex = 2; scriptSig = ""; sequence = 4294967285; witness = []},
{previousTxid = "\15\f1\ba\cd\92\00\37\89\bd\41\f6\f9\9d\12\1d\8a\32\33\c4\05\bc\40\29\b2\e1\a7\cd\80\fd\df\b9\eb"; previousIndex = 0; scriptSig = ""; sequence = 4294967284; witness = []}]; outputs = [{value = 900000; scriptPubKey = "\00\14\71\9e\49\da\51\c4\83\a2\32\33\73\87\ed\06\0d\fc\2b\02\2c\e2"},
{value = 8000; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"}]; lockTime = 850000};
transient let prevouts : [M.Output] = [{value = 100000; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100001; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100002; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100003; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100004; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100005; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100006; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100007; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100008; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"},
{value = 100009; scriptPubKey = "\51\20\73\d5\00\d5\f2\b3\8d\bb\1f\84\11\78\ce\ff\c0\09\c5\b2\2d\0b\34\44\96\f6\f5\bd\60\ab\e0\7f\74\21"}];
transient let scriptCode : Blob = "\76\a9\14\5a\54\b6\b3\6d\b6\7d\33\ff\2d\52\eb\25\5f\64\d0\c1\0f\43\b6\88\ac";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := some(M.wtxid(tx));
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { result };
}
