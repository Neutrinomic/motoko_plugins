import Prim "mo:⛔";
import RSA "mo:fast/RSA";
persistent actor {
  type Measurement = {instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat};
  transient var result : Blob = "";
  transient let secret : Blob = "\da\8f\45\44\0f\03\90\27\a4\0c\54\b6\2e\35\55\43\c3\f5\97\01\77\97\36\4e\86\8d\32\f5\7f\b1\9b\3a\5a\29\39\5f\77\e7\78\fa\22\89\10\42\78\b6\19\67\ca\92\b3\ef\3c\a9\ee\5a\8d\40\61\20\6a\7b\df\74\36\9c\18\a5\66\a9\a0\cc\d7\9f\e6\22\1f\c0\12\23\39\9d\8b\b2\c7\9c\f5\16\4c\3c\7c\43\fd\9b\9c\10\ad\ed\a2\0f\af\02\2d\35\a7\0b\f8\90\df\80\67\b7\40\6b\30\d1\ae\5e\17\ff\2d\b9\d9\4d\6f\3a\4d\62\2a\5a\74\87\88\5b\a1\b0\17\69\9a\9c\c3\73\60\0f\9d\43\2c\12\6c\37\ef\6e\0c\d7\47\b6\ae\86\45\fa\16\4a\32\fb\32\f0\3d\ec\3e\44\19\0d\d1\a7\6b\a6\cf\11\55\0b\1f\fe\f8\5c\c7\3d\63\98\6a\e2\05\fb\bf\c6\5b\72\cf\bd\ca\ec\76\21\89\3c\de\66\70\f8\b8\ab\ae\bd\52\10\81\58\b9\55\c8\a4\02\44\69\5d\02\7c\95\84\57\9e\77\42\64\99\44\ad\3e\b0\d4\b5\a7\e7\69\eb\d2\b7\ab\b9\25\88\53\39\ff\ee\ad\6e\d2\b3\5f\19\ad\eb\e9\79\c1\5b\52\03\6a\ad\7f\32\b6\c5\b3\74\83\a5\9a\a7\71\a5\cb\fe\87\58\ff\fc\73\2f\48\c9\20\3a\fb\28\27\f9\67\9e\10\84\19\83\09\08\e1\5b\b4\69\f1\9e\fc\2d\1c\27\3d\c6\f3\57\fc\c8\0d\87\67\1a\75\23\0a\68\ab\19\8e\dd\d8\e8\8a\8a\e1\4e\68\f4\99\ae\ac\a0\e4\bd\69\a9\ab\8b\46\56\bc\12\c9\a8\7f\82\cd\fa\54\09\f0\d3\70\be\87\a1\9f\6b\35\71\e1\73\7f\2a\cb\45\9a\70\30\85\96\e6\ae\bb\53\e6\70\e4\7d\c6\a9\c2\73\5b\0d\78\d1\56\c2\a1\17\b2\06\a3\e7\10\9c\6b\96\73\c9\2a\5b\cf\f4\b5\ee\b2\99\fb\92\56\b2\2c\42\ed\ef\d2\92\b2\01\9c\1f\75\70\85\82\db\3d\74\45\31\2b\d2\30\56\4c\49\fe\fd\05\72\09\3a\74\89\81\04\7b\41\68\e9\56\e7\e4\1c\81\b7\98\81\76\86\f7\16\36\85\e9\a0\95\f1\60\33\0f\85\e8\c5\42\24\bc\bc\0a\60\23\11\1f\4e\d6\a6\4e\c9\38\08\06\7a\09\5e\e6\c8\ed\57\30\f7\d6\f4\f5\49\00\91\40\58\16\36\95\cf\92\14\2b\dc\b8\6d\52\59\d8\71\d7\28\d1\8d\11\c9\9f\14\31\e8\f0\7d\a1\33\78\b6\49\da\19\b4\0f\86\c7\97\3e\f1\84\70\e5\88\21\64\48\5c\97\07\61\7b\1d\7c\05\bb\55\2d\3c\f1\b6\07\d9\ed\bd\d3\ca\32\b3\51\d1\ff\d1\8a\30\18\d0\05\dc\5f\3a\ea\01\b9\07\14\d8\78\0c\70\94\ad\64\82\1c\08\f6\c6\81\2d\9c\ae\fb\9e\02\3b\b2\ef\38\52\09\59\b5\7b\a0\b6\95\36\76\bc\9f\fc\d1\5c\a2\d9\c3\76\3b\04\89\b5\e6\5b\e7\07\56\e6\33\2c\e3\50\36\58\df\be\53\3d\21\08\78\0c\54\24\3d\51\23\34\39\36\18\1b\f7\40\2a\37\6f\4e\86\22\73\bf\99\cd\e5\b2\32\d1\4f\c0\8b\60\c6\93\b6\ca\5e\90\10\9d\9f\10\c2\e2\60\e2\ff\c9\f2\71\f7\b9\03\97\d3\7a\b9\30\55\fa\7c\21\61\a3\1c\2f\57\49\cc\b0\f3\b2\35\11\82\31\3f\f8\4b\2a\12\34\8d\77\00\ce\9d\12\9b\46\0c\44\8b\71\79\d9\3b\be\7f\f7\79\eb\c1\84\66\92\42\ca\03\13\40\1e\42\67\f7\3a\f6\81\a4\af\d3\1b\43\00\c0\05\cb\fe\d8\31\30\55\1f\77\a1\11\41\16\d1\ad\f4\81\76\79\b1\2b\ba\f2\30\50\62\c7\e4\80\91\d8\69\46\84\91\db\6e\08\67\09\e6\54\e3\2f\ef\33\86\46\96\1f\6d\c6\d8\d6\ab\a5\fb\d2\6b\91\f4\e4\f5\d8\41\40\d8\7f\eb\22\70\30\8e\d1\e8\c1\7e\17\4c\fc\8e\7d\42\43\37\5e\25\34\18\fd\33\f3\c4\6b\34\0e\dc\ea\2e\b1\e0\6d\45\00\45\f1\d0\c3\bd\5b\73\de\a4\c3\91\e8\c8\3e\f6\fb\b5\44\35\74\e1\b8\c2\ed\18\dd\bf\4a\bb\f9\43\3d\0b\4a\e1\9d\32\4f\90\19\29\7e\8e\79\8c\a4\4b\ea\dc\74\94\e0\3e\bf\37\6f\a7";
transient let publicKey : Blob = "\a3\ba\3d\90\4c\9f\30\fb\1e\db\8f\0c\f3\25\34\7f\c7\5a\44\7d\ee\14\51\4f\b7\67\59\5e\fe\81\49\35\56\68\69\65\6a\cb\71\48\50\46\00\9b\b4\db\f6\b4\1b\a7\14\e8\bc\c0\ce\a5\11\09\04\20\6b\86\c7\7a\fe\8c\34\60\7d\e6\04\3f\4a\93\60\94\ac\37\7e\56\3b\aa\37\5a\d6\2f\d8\02\cb\38\d1\c1\75\ad\44\72\da\cf\13\4a\18\48\56\ef\08\22\de\ca\00\7b\38\9a\9d\48\b7\6d\c7\f1\cf\20\33\ed\67\c8\2c\a0\2e\34\0a\ea\10\45\7d\c0\c3\20\5d\78\f5\1a\81\f9\44\e1\c6\32\78\99\5a\e1\2d\bd\70\7b\5a\e6\c8\90\de\20\fc\1c\7e\57\9e\c0\f7\72\7a\7f\75\72\f3\96\0c\3e\37\ef\35\f3\56\08\a3\86\0e\1f\bb\7b\fd\9c\df\b9\44\35\e0\2d\12\c2\ac\2a\ca\70\4c\a8\72\39\15\6e\38\ad\6b\25\27\c9\d5\f5\cb\35\b1\3d\ad\d9\26\e1\50\6e\97\04\5f\8f\9c\0f\3a\91\f5\06\6b\7b\54\e2\6c\96\db\46\48\c5\83\8b\f5\09\e8\e9\96\76\5f\b0\8c\a7\26\82\0d\2b\3b\93\a6\5d\b5\02\41\f2\c8\66\27\7e\8e\41\97\d6\7e\c9\55\59\f9\9b\36\b0\c2\6e\35\01\84\6a\16\cd\85\e8\a2\3d\b1\02\c2\2e\5f\33\4e\bb\a0\26\e3\02\db\7d\a5\09\3c\4c\ae\a6\ed\cb\31\ed\f1\ad\a7\3d\e2\ad\ed\e5\ec\8c\b7\76\04\fc\63\d5\54\41\49\90\da\f0\62\f4\32\59\f6\ad\d8\4b\be\2f\d2\7c\5a\e0\f6\8d\7e\1f\11\07\f5\86\6d\d4\76\5a\5e\89\81\9d\2f\f7\d2\63\b2\5c\84\5c\2b\67";
transient let message : Blob = "\69\6e\64\65\70\65\6e\64\65\6e\74\20\52\53\41\2d\50\53\53\20\53\48\41\32\35\36\20\76\65\72\69\66\69\63\61\74\69\6f\6e\00\6d\65\73\73\61\67\65";
transient let digest : Blob = "\80\b8\7b\c8\09\bd\32\2f\3f\d2\61\a0\a0\50\54\2b\89\88\1c\ed\46\7f\a1\89\38\f1\22\37\b3\7b\16\b6";
transient let salt : Blob = "\71\14\4a\2b\c3\87\82\98\d3\52\4b\0d\f3\23\59\dd\38\a9\1f\c6\d7\c0\5c\8a\a4\bd\42\fc\b3\9d\3e\22";
transient let signature : Blob = "\1b\aa\68\74\fb\ea\3f\a3\c7\61\1e\00\00\dc\28\eb\05\1f\26\be\e4\af\5d\31\b1\11\d5\fb\c4\1c\66\b1\8a\d7\ba\75\19\94\d3\a4\c9\22\90\a6\8a\ed\2d\e1\16\cb\c7\9d\db\76\e8\2b\0f\2b\26\be\2e\41\d3\ca\33\23\2d\0c\82\25\1c\05\ec\c4\69\4b\c2\75\cf\d9\d2\aa\bf\27\70\4a\b8\f2\8a\02\ff\ac\e7\40\4a\4b\5b\6a\ce\6d\aa\ed\a9\aa\2e\54\0f\cd\16\00\14\7b\54\6d\d4\2b\ad\ca\39\23\78\87\d2\13\28\ac\62\b2\ea\af\fa\ed\ce\35\8c\fc\5b\c1\65\c2\6a\fa\51\e8\e8\52\fa\79\4a\49\59\94\51\67\6e\b4\7e\10\b3\b2\8d\3c\2f\a8\08\34\c2\dd\27\d0\eb\f3\83\cc\e4\e2\da\b1\83\a9\77\fc\0c\99\df\27\1b\b6\8b\c2\3b\1f\69\df\73\16\6c\18\26\10\a9\99\f4\07\70\c1\8a\3b\ce\3c\38\be\a4\7c\3c\ab\9a\c7\bc\f4\a2\b6\34\73\93\87\eb\31\92\9b\aa\7d\d1\4b\2f\75\55\f5\9a\25\df\7b\6f\ea\7d\1c\ee\1a\7f\91\21\51\8e\92\c1\e7\53\6f\b2\54\8b\58\cb\88\ad\2f\28\cf\f2\b4\93\48\72\5d\99\aa\e6\92\3c\3e\7f\4c\56\a4\61\ac\7f\19\9e\7f\c9\2a\67\a2\0a\16\66\b6\67\2d\e9\fc\79\ed\45\0c\bd\ce\06\81\ad\bc\60\9d\f3\9a\5c\03\cd\92\be\a6\e2\7a\e9\a0\10\b8\82\17\39\ca\c6\ea\35\05\d8\9d\10\2b\2c\1a\f4\6c\fa\2f\13\e4\0a\c6\c1\b1\e6\23\e4\da\84\e0\ce\bd\80\ff\6f\05\56\e3\3f\81\33\d9\c0\bf\3b\4e\fe\2a\60\1a\92\8f\e1\ad\e2\cb";
  transient var key : ?RSA.PreparedSecretKey = null;
  func unwrap<T>(value : RSA.Result<T>) : T {
    switch value { case (#ok x) x; case (#err _) Prim.trap("RSA benchmark error") }
  };
  func getKey() : RSA.PreparedSecretKey {
    switch key { case (?x) x; case null Prim.trap("RSA key not prepared") }
  };
  public func configure() : async () { key := ?unwrap(RSA.prepareSecretKey(secret)) };
  public func run() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let start = Prim.performanceCounter(0);
    result := unwrap(RSA.signPrehashPrepared(getKey(), digest, salt));
    let stop = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    {instructions = stop - start; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = 0}
  };

  public query func memory() : async {
    heapSize : Nat; memorySize : Nat; totalAllocation : Nat; reclaimed : Nat
  } {
    {heapSize = Prim.rts_heap_size(); memorySize = Prim.rts_memory_size();
      totalAllocation = Prim.rts_total_allocation(); reclaimed = Prim.rts_reclaimed()}
  };
  public query func bytesResult() : async Blob { result };
}
