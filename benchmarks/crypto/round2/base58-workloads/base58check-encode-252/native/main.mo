import Prim "mo:⛔";
import B "mo:fast/Base58Check";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Text = "";
  transient let input : Blob = "\11\94\17\9a\1d\a0\23\a6\29\ac\2f\b2\35\b8\3b\be\41\c4\47\ca\4d\d0\53\d6\59\dc\5f\e2\65\e8\6b\ee\71\f4\77\fa\7d\00\83\06\89\0c\8f\12\95\18\9b\1e\a1\24\a7\2a\ad\30\b3\36\b9\3c\bf\42\c5\48\cb\4e\d1\54\d7\5a\dd\60\e3\66\e9\6c\ef\72\f5\78\fb\7e\01\84\07\8a\0d\90\13\96\19\9c\1f\a2\25\a8\2b\ae\31\b4\37\ba\3d\c0\43\c6\49\cc\4f\d2\55\d8\5b\de\61\e4\67\ea\6d\f0\73\f6\79\fc\7f\02\85\08\8b\0e\91\14\97\1a\9d\20\a3\26\a9\2c\af\32\b5\38\bb\3e\c1\44\c7\4a\cd\50\d3\56\d9\5c\df\62\e5\68\eb\6e\f1\74\f7\7a\fd\80\03\86\09\8c\0f\92\15\98\1b\9e\21\a4\27\aa\2d\b0\33\b6\39\bc\3f\c2\45\c8\4b\ce\51\d4\57\da\5d\e0\63\e6\69\ec\6f\f2\75\f8\7b\fe\81\04\87\0a\8d\10\93\16\99\1c\9f\22\a5\28\ab\2e\b1\34\b7\3a\bd\40\c3\46\c9\4c\cf\52\d5\58\db\5e\e1\64\e7\6a\ed\70\f3\76\f9\7c\ff\82";
  public func configure() : async () {  };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := B.encode(input);
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };
  public query func bytesResult() : async Blob { Prim.encodeUtf8(result) };
}
