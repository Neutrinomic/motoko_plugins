// Generated from independent Python integer arithmetic by render.py.
import P256 "mo:fast/P256";
import Prim "mo:⛔";
module {
  public type Key = { compressed : Blob; uncompressed : Blob };
  public type Vector = { key : Nat; digest : Blob; signature : Blob; expected : Bool };
  public let keys : [Key] = [
    { compressed = "\03\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96"; uncompressed = "\04\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\4f\e3\42\e2\fe\1a\7f\9b\8e\e7\eb\4a\7c\0f\9e\16\2b\ce\33\57\6b\31\5e\ce\cb\b6\40\68\37\bf\51\f5" },
    { compressed = "\03\7c\f2\7b\18\8d\03\4f\7e\8a\52\38\03\04\b5\1a\c3\c0\89\69\e2\77\f2\1b\35\a6\0b\48\fc\47\66\99\78"; uncompressed = "\04\7c\f2\7b\18\8d\03\4f\7e\8a\52\38\03\04\b5\1a\c3\c0\89\69\e2\77\f2\1b\35\a6\0b\48\fc\47\66\99\78\07\77\55\10\db\8e\d0\40\29\3d\9a\c6\9f\74\30\db\ba\7d\ad\e6\3c\e9\82\29\9e\04\b7\9d\22\78\73\d1" },
    { compressed = "\02\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96"; uncompressed = "\04\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\b0\1c\bd\1c\01\e5\80\65\71\18\14\b5\83\f0\61\e9\d4\31\cc\a9\94\ce\a1\31\34\49\bf\97\c8\40\ae\0a" },
    { compressed = "\03\fc\b7\11\61\20\d0\17\4b\c4\19\1a\cf\84\23\c0\ba\ff\33\d7\07\1d\39\80\92\6f\31\36\89\8a\bf\6b\d1"; uncompressed = "\04\fc\b7\11\61\20\d0\17\4b\c4\19\1a\cf\84\23\c0\ba\ff\33\d7\07\1d\39\80\92\6f\31\36\89\8a\bf\6b\d1\de\ea\e3\7c\83\66\66\44\24\aa\32\13\6e\27\7d\6a\41\f3\c2\38\87\52\10\23\33\19\2f\74\f8\6c\5b\d9" },
    { compressed = "\02\44\7d\73\9b\ee\db\5e\67\fb\98\2f\d5\88\c6\76\6e\fc\35\ff\7d\c2\97\ea\c3\57\c8\4f\c9\d7\89\bd\85"; uncompressed = "\04\44\7d\73\9b\ee\db\5e\67\fb\98\2f\d5\88\c6\76\6e\fc\35\ff\7d\c2\97\ea\c3\57\c8\4f\c9\d7\89\bd\85\2d\48\25\ab\83\41\31\ee\e1\2e\9d\95\3a\4a\af\f7\3d\34\9b\95\a7\fa\e5\00\0c\7e\33\c9\72\e2\5b\32" },
    { compressed = "\03\77\b2\0a\91\2e\6b\23\13\50\66\e9\11\89\15\24\bc\4e\fe\35\60\e3\e9\23\50\b5\2d\ec\8f\37\5f\2b\54"; uncompressed = "\04\77\b2\0a\91\2e\6b\23\13\50\66\e9\11\89\15\24\bc\4e\fe\35\60\e3\e9\23\50\b5\2d\ec\8f\37\5f\2b\54\a3\dc\29\18\25\ce\a3\f7\f7\b1\0b\fc\dd\03\8a\72\df\62\3d\a1\e8\50\e0\f1\ca\a8\01\fc\d6\cc\67\ff" },
    { compressed = "\02\02\bc\84\7e\19\eb\be\40\a3\67\ce\d6\48\06\85\11\bb\c2\4d\ba\56\32\2f\d5\28\85\60\4e\dd\c0\9e\af"; uncompressed = "\04\02\bc\84\7e\19\eb\be\40\a3\67\ce\d6\48\06\85\11\bb\c2\4d\ba\56\32\2f\d5\28\85\60\4e\dd\c0\9e\af\81\55\56\a7\b1\bb\4d\14\f4\f4\21\97\da\f6\2b\07\c1\f3\0f\fb\bd\9d\f1\50\47\f2\b2\9c\56\da\40\5e" },
    { compressed = "\03\ab\ef\d5\30\35\32\5d\cb\20\b6\96\7a\2c\28\4a\9b\fc\67\9b\84\46\68\25\23\b3\2b\af\41\12\0d\76\e4"; uncompressed = "\04\ab\ef\d5\30\35\32\5d\cb\20\b6\96\7a\2c\28\4a\9b\fc\67\9b\84\46\68\25\23\b3\2b\af\41\12\0d\76\e4\b4\d5\ee\3e\b3\9a\b3\dc\05\9b\c7\cb\8c\8f\cf\1f\84\2c\ee\7d\72\96\02\a7\f1\5e\aa\65\3d\81\87\2d" },
    { compressed = "\03\eb\90\6a\e9\b4\d0\21\65\b3\62\c0\10\0a\d5\0d\58\91\b2\46\c4\6f\37\40\fa\16\02\e0\8b\72\0e\d1\e7"; uncompressed = "\04\eb\90\6a\e9\b4\d0\21\65\b3\62\c0\10\0a\d5\0d\58\91\b2\46\c4\6f\37\40\fa\16\02\e0\8b\72\0e\d1\e7\d5\91\06\1a\79\94\d6\29\d4\7e\5f\60\6f\2b\68\c8\6e\2a\82\c3\98\9d\16\7c\e1\2c\6d\c6\8b\59\a6\eb" },
    { compressed = "\03\91\bc\4a\51\e0\d1\3e\76\a0\1d\41\54\b8\b5\1d\33\c0\48\71\24\06\c9\46\ec\7a\fb\b7\81\35\5f\7a\9a"; uncompressed = "\04\91\bc\4a\51\e0\d1\3e\76\a0\1d\41\54\b8\b5\1d\33\c0\48\71\24\06\c9\46\ec\7a\fb\b7\81\35\5f\7a\9a\d8\c4\38\60\0c\61\24\e1\4c\26\cb\ac\bb\f4\f4\ce\2d\29\49\85\91\72\a5\2e\50\59\e5\b9\11\ef\86\8f" },
    { compressed = "\02\6a\9a\05\16\8d\d3\d8\ce\c6\8e\07\6c\c2\0c\52\7b\38\74\47\01\ae\4c\1d\86\33\04\be\00\f1\ca\93\80"; uncompressed = "\04\6a\9a\05\16\8d\d3\d8\ce\c6\8e\07\6c\c2\0c\52\7b\38\74\47\01\ae\4c\1d\86\33\04\be\00\f1\ca\93\80\0d\42\f6\e8\c9\55\15\06\c9\97\fc\64\a5\fb\b2\90\9d\d1\dc\4e\85\2b\e1\a0\e6\bc\fb\63\90\e0\60\12" },
    { compressed = "\03\e1\68\9c\e3\6d\e7\a4\1a\c0\b7\63\e3\83\95\5b\30\d7\65\07\69\5e\d3\88\65\30\92\63\1c\8f\70\f8\8f"; uncompressed = "\04\e1\68\9c\e3\6d\e7\a4\1a\c0\b7\63\e3\83\95\5b\30\d7\65\07\69\5e\d3\88\65\30\92\63\1c\8f\70\f8\8f\f7\08\fc\a9\49\92\4f\0a\38\89\e5\02\5b\9c\e7\e6\c4\d1\85\cb\99\aa\56\86\73\ab\9f\1f\4e\4c\fe\37" },
    { compressed = "\02\ed\c7\d9\ce\3b\85\10\68\8e\a8\82\44\14\3d\b1\b8\2e\66\24\9b\18\5e\46\f0\51\7d\90\02\a3\14\be\3e"; uncompressed = "\04\ed\c7\d9\ce\3b\85\10\68\8e\a8\82\44\14\3d\b1\b8\2e\66\24\9b\18\5e\46\f0\51\7d\90\02\a3\14\be\3e\26\8a\f4\4d\74\b2\29\ef\b2\12\a8\01\78\94\92\0b\97\1a\29\10\49\aa\ff\0f\9f\75\ab\92\66\e7\83\8a" },
    { compressed = "\02\04\a5\f3\8f\98\1a\88\25\77\fb\a4\21\7d\d4\8e\34\3f\b3\d8\ac\db\6c\af\23\ac\73\98\fd\59\3f\eb\7c"; uncompressed = "\04\04\a5\f3\8f\98\1a\88\25\77\fb\a4\21\7d\d4\8e\34\3f\b3\d8\ac\db\6c\af\23\ac\73\98\fd\59\3f\eb\7c\9a\4a\da\39\cb\a5\0e\4c\2f\2c\3c\03\d1\ee\ae\da\19\22\bb\ff\1c\37\a1\ed\39\76\f6\0c\12\54\9e\70" },
    { compressed = "\03\7d\c0\e0\ef\8a\dc\a0\57\e1\de\35\b0\47\75\7e\bc\d7\b5\5b\1a\3a\93\a5\54\6c\04\ce\87\10\06\a1\c6"; uncompressed = "\04\7d\c0\e0\ef\8a\dc\a0\57\e1\de\35\b0\47\75\7e\bc\d7\b5\5b\1a\3a\93\a5\54\6c\04\ce\87\10\06\a1\c6\3d\fa\d9\e4\37\cf\dc\27\a3\e3\5f\64\47\27\02\d0\a0\c3\02\56\76\58\8d\44\47\23\a5\ea\39\5d\d2\3b" },
    { compressed = "\02\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; uncompressed = "\04\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\66\48\5c\78\0e\2f\83\d7\24\33\bd\5d\84\a0\6b\b6\54\1c\2a\f3\1d\ae\87\17\28\bf\85\6a\17\4f\93\f4" },
    { compressed = "\03\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fc"; uncompressed = "\04\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fc\19\71\9b\eb\f6\ae\a1\3f\25\c9\6d\fd\7c\71\f5\22\5d\4c\8f\c0\9e\b5\a0\ab\9f\39\e9\17\8e\55\c1\21" },
  ];
  public let vectors : [Vector] = [
    // valid-0-0
    { key = 0; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96"; expected = true },
    // flipped-S-0-0
    { key = 0; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\94\e8\2e\0c\1e\d3\bd\b9\07\43\19\1a\9c\5b\bf\0d\45\e3\7d\2c\79\2c\6a\e3\ff\18\91\7d\23\ca\62\bb"; expected = true },
    // changed-r-0-0
    { key = 0; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96"; expected = false },
    // valid-0-1
    { key = 0; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\94\e8\2e\0c\1e\d3\bd\b9\07\43\19\1a\9c\5b\bf\0d\45\e3\7d\2c\79\2c\6a\e3\ff\18\91\7d\23\ca\62\ba"; expected = true },
    // flipped-S-0-1
    { key = 0; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97"; expected = true },
    // changed-r-0-1
    { key = 0; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\94\e8\2e\0c\1e\d3\bd\b9\07\43\19\1a\9c\5b\bf\0d\45\e3\7d\2c\79\2c\6a\e3\ff\18\91\7d\23\ca\62\ba"; expected = false },
    // valid-0-2
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\53\d1\d7\17\f1\b9\d4\26\1d\ee\4e\96\6d\9d\55\e3\6e\9a\3c\a6\c7\55\36\41\22\e7\c4\76\77\9a\b2\50"; expected = true },
    // flipped-S-0-2
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\ac\2e\28\e7\0e\46\2b\da\e2\11\b1\69\92\62\aa\1c\4e\4c\be\06\df\c2\68\43\d0\d2\06\4c\84\c8\73\01"; expected = true },
    // changed-r-0-2
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\53\d1\d7\17\f1\b9\d4\26\1d\ee\4e\96\6d\9d\55\e3\6e\9a\3c\a6\c7\55\36\41\22\e7\c4\76\77\9a\b2\50"; expected = false },
    // valid-0-3
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\0c\f9\d6\74\6e\71\72\8f\a1\19\6c\b9\ef\7a\4a\32\3a\44\ce\dd\02\3f\ed\11\2a\47\78\4c\84\ab\4c\b0"; expected = true },
    // flipped-S-0-3
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\f3\06\29\8a\91\8e\8d\71\5e\e6\93\46\10\85\b5\cd\82\a2\2b\d0\a4\d7\b1\73\c9\72\52\76\77\b7\d8\a1"; expected = true },
    // changed-r-0-3
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3f\0c\f9\d6\74\6e\71\72\8f\a1\19\6c\b9\ef\7a\4a\32\3a\44\ce\dd\02\3f\ed\11\2a\47\78\4c\84\ab\4c\b0"; expected = false },
    // valid-0-4
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97"; expected = true },
    // flipped-S-0-4
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\94\e8\2e\0c\1e\d3\bd\b9\07\43\19\1a\9c\5b\bf\0d\45\e3\7d\2c\79\2c\6a\e3\ff\18\91\7d\23\ca\62\ba"; expected = true },
    // changed-r-0-4
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97"; expected = false },
    // valid-0-5
    { key = 0; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\94\e8\2e\0b\1e\d3\bd\ba\07\43\19\1a\9c\5b\bf\0d\02\ca\77\da\20\44\09\68\f2\d2\5c\40\20\2d\88\0d"; expected = true },
    // flipped-S-0-5
    { key = 0; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6b\17\d1\f3\e1\2c\42\46\f8\bc\e6\e5\63\a4\40\f2\ba\1c\82\d3\86\d3\95\1c\00\e7\6e\82\dc\35\9d\44"; expected = true },
    // changed-r-0-5
    { key = 0; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\94\e8\2e\0b\1e\d3\bd\ba\07\43\19\1a\9c\5b\bf\0d\02\ca\77\da\20\44\09\68\f2\d2\5c\40\20\2d\88\0d"; expected = false },
    // valid-1-0
    { key = 1; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\29\d0\5c\19\3d\a7\7b\71\0e\86\32\35\38\b7\7e\1a\ce\df\ff\ab\4b\41\37\43\0a\77\58\37\4b\31\a0\25"; expected = true },
    // flipped-S-1-0
    { key = 1; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\d6\2f\a3\e5\c2\58\84\8f\f1\79\cd\ca\c7\48\81\e4\ee\06\fb\02\5b\d6\67\41\e9\42\72\8b\b1\31\85\2c"; expected = true },
    // changed-r-1-0
    { key = 1; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\29\d0\5c\19\3d\a7\7b\71\0e\86\32\35\38\b7\7e\1a\ce\df\ff\ab\4b\41\37\43\0a\77\58\37\4b\31\a0\25"; expected = false },
    // valid-1-1
    { key = 1; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\0e\19\08\31\47\00\83\37\d8\4f\c2\40\a5\3c\e0\b4\05\72\c4\7a\a8\b2\4f\6b\d3\a5\30\85\42\32\ea\41"; expected = true },
    // flipped-S-1-1
    { key = 1; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\f1\e6\f7\cd\b8\ff\7c\c9\27\b0\3d\bf\5a\c3\1f\4b\b7\74\36\32\fe\65\4f\19\20\14\9a\3d\ba\30\3b\10"; expected = true },
    // changed-r-1-1
    { key = 1; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\0e\19\08\31\47\00\83\37\d8\4f\c2\40\a5\3c\e0\b4\05\72\c4\7a\a8\b2\4f\6b\d3\a5\30\85\42\32\ea\41"; expected = false },
    // valid-1-2
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\3b\f9\70\54\53\ae\e2\68\94\ad\d5\4f\43\13\68\b1\a8\bf\c6\85\27\1e\5d\e7\89\bd\fb\b4\3b\37\7b\9e"; expected = true },
    // flipped-S-1-2
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\c4\06\8f\aa\ac\51\1d\98\6b\52\2a\b0\bc\ec\97\4e\14\27\34\28\7f\f9\40\9d\69\fb\cf\0e\c1\2b\a9\b3"; expected = true },
    // changed-r-1-2
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3f\3b\f9\70\54\53\ae\e2\68\94\ad\d5\4f\43\13\68\b1\a8\bf\c6\85\27\1e\5d\e7\89\bd\fb\b4\3b\37\7b\9e"; expected = false },
    // valid-1-3
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\d6\2f\a3\e5\c2\58\84\8f\f1\79\cd\ca\c7\48\81\e4\ee\06\fb\02\5b\d6\67\41\e9\42\72\8b\b1\31\85\2c"; expected = true },
    // flipped-S-1-3
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\29\d0\5c\19\3d\a7\7b\71\0e\86\32\35\38\b7\7e\1a\ce\df\ff\ab\4b\41\37\43\0a\77\58\37\4b\31\a0\25"; expected = true },
    // changed-r-1-3
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\d6\2f\a3\e5\c2\58\84\8f\f1\79\cd\ca\c7\48\81\e4\ee\06\fb\02\5b\d6\67\41\e9\42\72\8b\b1\31\85\2c"; expected = false },
    // valid-1-4
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\29\d0\5c\19\3d\a7\7b\71\0e\86\32\35\38\b7\7e\1a\ce\df\ff\ab\4b\41\37\43\0a\77\58\37\4b\31\a0\24"; expected = true },
    // flipped-S-1-4
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\d6\2f\a3\e5\c2\58\84\8f\f1\79\cd\ca\c7\48\81\e4\ee\06\fb\02\5b\d6\67\41\e9\42\72\8b\b1\31\85\2d"; expected = true },
    // changed-r-1-4
    { key = 1; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\29\d0\5c\19\3d\a7\7b\71\0e\86\32\35\38\b7\7e\1a\ce\df\ff\ab\4b\41\37\43\0a\77\58\37\4b\31\a0\24"; expected = false },
    // valid-1-5
    { key = 1; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\74\75\76\db\04\a2\9b\f1\1a\ad\a9\88\c9\3b\68\15\ea\9e\92\5c\97\57\b8\25\75\16\c0\ca\60\34\91\2b"; expected = true },
    // flipped-S-1-5
    { key = 1; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\8b\8a\89\23\fb\5d\64\0f\e5\52\56\77\36\c4\97\e9\d2\48\68\51\0f\bf\e6\5f\7e\a3\09\f8\9c\2e\94\26"; expected = true },
    // changed-r-1-5
    { key = 1; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\74\75\76\db\04\a2\9b\f1\1a\ad\a9\88\c9\3b\68\15\ea\9e\92\5c\97\57\b8\25\75\16\c0\ca\60\34\91\2b"; expected = false },
    // valid-2-0
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\df\5c\60\3b\ed\17\38\37\03\40\a5\0d\a4\61\ed\cd\40\e2\a4\f7\d7\15\1c\a0\a1\8a\ce\6f\13\c9\46\76"; expected = true },
    // flipped-S-2-0
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\20\a3\9f\c3\12\e8\c7\c9\fc\bf\5a\f2\5b\9e\12\32\7c\04\55\b5\d0\02\81\e4\52\2e\fc\53\e8\99\de\db"; expected = true },
    // changed-r-2-0
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\df\5c\60\3b\ed\17\38\37\03\40\a5\0d\a4\61\ed\cd\40\e2\a4\f7\d7\15\1c\a0\a1\8a\ce\6f\13\c9\46\76"; expected = false },
    // valid-2-1
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\d1\00\66\1f\1a\c2\90\28\0c\6b\97\6a\ac\66\e1\80\4e\6c\03\05\82\39\2d\ae\94\43\47\5b\45\d6\f6\63"; expected = true },
    // flipped-S-2-1
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\2e\ff\99\df\e5\3d\6f\d8\f3\94\68\95\53\99\1e\7f\6e\7a\f7\a8\24\de\70\d6\5f\76\83\67\b6\8c\2e\ee"; expected = true },
    // changed-r-2-1
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3f\d1\00\66\1f\1a\c2\90\28\0c\6b\97\6a\ac\66\e1\80\4e\6c\03\05\82\39\2d\ae\94\43\47\5b\45\d6\f6\63"; expected = false },
    // valid-2-2
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\94\e8\2e\0c\1e\d3\bd\b9\07\43\19\1a\9c\5b\bf\0d\45\e3\7d\2c\79\2c\6a\e3\ff\18\91\7d\23\ca\62\ba"; expected = true },
    // flipped-S-2-2
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97"; expected = true },
    // changed-r-2-2
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\94\e8\2e\0c\1e\d3\bd\b9\07\43\19\1a\9c\5b\bf\0d\45\e3\7d\2c\79\2c\6a\e3\ff\18\91\7d\23\ca\62\ba"; expected = false },
    // valid-2-3
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96"; expected = true },
    // flipped-S-2-3
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\94\e8\2e\0c\1e\d3\bd\b9\07\43\19\1a\9c\5b\bf\0d\45\e3\7d\2c\79\2c\6a\e3\ff\18\91\7d\23\ca\62\bb"; expected = true },
    // changed-r-2-3
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96"; expected = false },
    // valid-2-4
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\ac\2e\28\e7\0e\46\2b\da\e2\11\b1\69\92\62\aa\1c\4e\4c\be\06\df\c2\68\43\d0\d2\06\4c\84\c8\73\01"; expected = true },
    // flipped-S-2-4
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\53\d1\d7\17\f1\b9\d4\26\1d\ee\4e\96\6d\9d\55\e3\6e\9a\3c\a6\c7\55\36\41\22\e7\c4\76\77\9a\b2\50"; expected = true },
    // changed-r-2-4
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\ac\2e\28\e7\0e\46\2b\da\e2\11\b1\69\92\62\aa\1c\4e\4c\be\06\df\c2\68\43\d0\d2\06\4c\84\c8\73\01"; expected = false },
    // valid-2-5
    { key = 2; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\de\52\e6\1a\d3\a7\9e\52\ee\82\8d\56\e4\3e\6f\98\c8\24\7e\6f\84\10\a2\f6\85\b5\8d\76\4c\61\98\9a"; expected = true },
    // flipped-S-2-5
    { key = 2; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\21\ad\19\e4\2c\58\61\ae\11\7d\72\a9\1b\c1\90\66\f4\c2\7c\3e\23\06\fb\8e\6e\04\3d\4c\b0\01\8c\b7"; expected = true },
    // changed-r-2-5
    { key = 2; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3f\de\52\e6\1a\d3\a7\9e\52\ee\82\8d\56\e4\3e\6f\98\c8\24\7e\6f\84\10\a2\f6\85\b5\8d\76\4c\61\98\9a"; expected = false },
    // valid-3-0
    { key = 3; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\02\91\08\d5\05\9d\8e\9e\9c\92\09\ee\8e\2b\65\41\09\19\4c\d6\ec\01\d7\73\47\55\03\9c\c0\49\05\0c"; expected = true },
    // flipped-S-3-0
    { key = 3; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\fd\6e\f7\29\fa\62\71\62\63\6d\f6\11\71\d4\9a\be\b3\cd\ad\d6\bb\15\c7\11\ac\64\c7\26\3c\1a\20\45"; expected = true },
    // changed-r-3-0
    { key = 3; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3f\02\91\08\d5\05\9d\8e\9e\9c\92\09\ee\8e\2b\65\41\09\19\4c\d6\ec\01\d7\73\47\55\03\9c\c0\49\05\0c"; expected = false },
    // valid-3-1
    { key = 3; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6e\d1\57\39\36\33\ea\70\9a\58\4a\1b\e1\eb\9d\94\ce\51\69\6a\a4\5e\97\9b\d7\dc\94\88\44\82\75\11"; expected = true },
    // flipped-S-3-1
    { key = 3; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\91\2e\a8\c5\c9\cc\15\90\65\a7\b5\e4\1e\14\62\6a\ee\95\91\43\02\b9\06\e9\1b\dd\36\3a\b7\e0\b0\40"; expected = true },
    // changed-r-3-1
    { key = 3; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\6e\d1\57\39\36\33\ea\70\9a\58\4a\1b\e1\eb\9d\94\ce\51\69\6a\a4\5e\97\9b\d7\dc\94\88\44\82\75\11"; expected = false },
    // valid-3-2
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\91\2e\a8\c5\c9\cc\15\90\65\a7\b5\e4\1e\14\62\6a\ee\95\91\43\02\b9\06\e9\1b\dd\36\3a\b7\e0\b0\42"; expected = true },
    // flipped-S-3-2
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6e\d1\57\39\36\33\ea\70\9a\58\4a\1b\e1\eb\9d\94\ce\51\69\6a\a4\5e\97\9b\d7\dc\94\88\44\82\75\0f"; expected = true },
    // changed-r-3-2
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\91\2e\a8\c5\c9\cc\15\90\65\a7\b5\e4\1e\14\62\6a\ee\95\91\43\02\b9\06\e9\1b\dd\36\3a\b7\e0\b0\42"; expected = false },
    // valid-3-3
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\ef\04\82\f8\15\28\e2\dc\87\d2\fe\3b\d6\d0\13\ab\6a\2b\e0\a2\84\7a\3c\1f\32\72\2b\23\a1\de\21\d9"; expected = true },
    // flipped-S-3-3
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\10\fb\7d\06\ea\d7\1d\24\78\2d\01\c4\29\2f\ec\54\52\bb\1a\0b\22\9d\62\65\c1\47\9f\9f\5a\85\03\78"; expected = true },
    // changed-r-3-3
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\ef\04\82\f8\15\28\e2\dc\87\d2\fe\3b\d6\d0\13\ab\6a\2b\e0\a2\84\7a\3c\1f\32\72\2b\23\a1\de\21\d9"; expected = false },
    // valid-3-4
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\e0\8b\45\68\8e\d1\91\56\4a\17\0e\13\2a\0c\90\f3\91\ca\1e\b9\70\7a\f2\33\05\df\c3\44\8a\cb\48\1f"; expected = true },
    // flipped-S-3-4
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\1f\74\ba\96\71\2e\6e\aa\b5\e8\f1\ec\d5\f3\6f\0c\2b\1c\db\f4\36\9c\ac\51\ed\da\07\7e\71\97\dd\32"; expected = true },
    // changed-r-3-4
    { key = 3; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3f\e0\8b\45\68\8e\d1\91\56\4a\17\0e\13\2a\0c\90\f3\91\ca\1e\b9\70\7a\f2\33\05\df\c3\44\8a\cb\48\1f"; expected = false },
    // valid-3-5
    { key = 3; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\6e\d1\57\3a\36\33\ea\6f\9a\58\4a\1b\e1\eb\9d\95\11\6a\6e\bc\fd\46\f9\16\e4\22\c9\c5\48\1f\4f\be"; expected = true },
    // flipped-S-3-5
    { key = 3; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\91\2e\a8\c4\c9\cc\15\91\65\a7\b5\e4\1e\14\62\6a\ab\7c\8b\f0\a9\d0\a5\6e\0f\97\00\fd\b4\43\d5\93"; expected = true },
    // changed-r-3-5
    { key = 3; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\6e\d1\57\3a\36\33\ea\6f\9a\58\4a\1b\e1\eb\9d\95\11\6a\6e\bc\fd\46\f9\16\e4\22\c9\c5\48\1f\4f\be"; expected = false },
    // valid-4-0
    { key = 4; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\aa\75\5d\b8\54\46\88\a3\7e\72\38\ff\40\fe\92\6b\6d\ac\25\d7\9e\44\a7\a5\fb\43\fb\37\67\35\de\dc"; expected = true },
    // flipped-S-4-0
    { key = 4; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\55\8a\a2\46\ab\b9\77\5d\81\8d\c7\00\bf\01\6d\94\4f\3a\d4\d6\08\d2\f6\de\f8\75\cf\8b\95\2d\46\75"; expected = true },
    // changed-r-4-0
    { key = 4; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\aa\75\5d\b8\54\46\88\a3\7e\72\38\ff\40\fe\92\6b\6d\ac\25\d7\9e\44\a7\a5\fb\43\fb\37\67\35\de\dc"; expected = false },
    // valid-4-1
    { key = 4; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\55\8a\a2\46\ab\b9\77\5d\81\8d\c7\00\bf\01\6d\94\4f\3a\d4\d6\08\d2\f6\de\f8\75\cf\8b\95\2d\46\74"; expected = true },
    // flipped-S-4-1
    { key = 4; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\aa\75\5d\b8\54\46\88\a3\7e\72\38\ff\40\fe\92\6b\6d\ac\25\d7\9e\44\a7\a5\fb\43\fb\37\67\35\de\dd"; expected = true },
    // changed-r-4-1
    { key = 4; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\55\8a\a2\46\ab\b9\77\5d\81\8d\c7\00\bf\01\6d\94\4f\3a\d4\d6\08\d2\f6\de\f8\75\cf\8b\95\2d\46\74"; expected = false },
    // valid-4-2
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\df\d2\3b\27\d9\85\64\d9\4e\92\b8\24\b8\54\44\bb\d8\e9\7f\1b\06\f4\bf\69\84\e6\f5\ff\2a\04\d2\c4"; expected = true },
    // flipped-S-4-2
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\20\2d\c4\d7\26\7a\9b\27\b1\6d\47\db\47\ab\bb\43\e3\fd\7b\92\a0\22\df\1b\6e\d2\d4\c3\d2\5e\52\8d"; expected = true },
    // changed-r-4-2
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\df\d2\3b\27\d9\85\64\d9\4e\92\b8\24\b8\54\44\bb\d8\e9\7f\1b\06\f4\bf\69\84\e6\f5\ff\2a\04\d2\c4"; expected = false },
    // valid-4-3
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\b1\ba\77\d5\fa\0b\ce\fc\47\70\f9\06\b0\1e\b1\ef\61\d6\c6\7f\16\97\07\c9\fb\17\5c\13\2c\d9\c7\59"; expected = true },
    // flipped-S-4-3
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\4e\45\88\29\05\f4\31\04\b8\8f\06\f9\4f\e1\4e\10\5b\10\34\2e\90\80\96\ba\f8\a2\6e\af\cf\89\5d\f8"; expected = true },
    // changed-r-4-3
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3f\b1\ba\77\d5\fa\0b\ce\fc\47\70\f9\06\b0\1e\b1\ef\61\d6\c6\7f\16\97\07\c9\fb\17\5c\13\2c\d9\c7\59"; expected = false },
    // valid-4-4
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\aa\75\5d\b8\54\46\88\a3\7e\72\38\ff\40\fe\92\6b\6d\ac\25\d7\9e\44\a7\a5\fb\43\fb\37\67\35\de\dd"; expected = true },
    // flipped-S-4-4
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\55\8a\a2\46\ab\b9\77\5d\81\8d\c7\00\bf\01\6d\94\4f\3a\d4\d6\08\d2\f6\de\f8\75\cf\8b\95\2d\46\74"; expected = true },
    // changed-r-4-4
    { key = 4; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\aa\75\5d\b8\54\46\88\a3\7e\72\38\ff\40\fe\92\6b\6d\ac\25\d7\9e\44\a7\a5\fb\43\fb\37\67\35\de\dd"; expected = false },
    // valid-4-5
    { key = 4; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\55\8a\a2\45\ab\b9\77\5e\81\8d\c7\00\bf\01\6d\94\0c\21\cf\83\af\ea\95\63\ec\2f\9a\4e\91\90\6b\c7"; expected = true },
    // flipped-S-4-5
    { key = 4; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\aa\75\5d\b9\54\46\88\a2\7e\72\38\ff\40\fe\92\6b\b0\c5\2b\29\f7\2d\09\21\07\8a\30\74\6a\d2\b9\8a"; expected = true },
    // changed-r-4-5
    { key = 4; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\55\8a\a2\45\ab\b9\77\5e\81\8d\c7\00\bf\01\6d\94\0c\21\cf\83\af\ea\95\63\ec\2f\9a\4e\91\90\6b\c7"; expected = false },
    // valid-5-0
    { key = 5; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\11\b1\e6\c7\e2\ad\81\58\25\d1\d7\dd\02\ff\1d\2e\fd\bf\23\f4\39\ef\32\46\aa\c0\71\b5\cf\1f\37\a9"; expected = true },
    // flipped-S-5-0
    { key = 5; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\ee\4e\19\37\1d\52\7e\a8\da\2e\28\22\fd\00\e2\d0\bf\27\d6\b9\6d\28\6c\3e\48\f9\59\0d\2d\43\ed\a8"; expected = true },
    // changed-r-5-0
    { key = 5; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\11\b1\e6\c7\e2\ad\81\58\25\d1\d7\dd\02\ff\1d\2e\fd\bf\23\f4\39\ef\32\46\aa\c0\71\b5\cf\1f\37\a9"; expected = false },
    // valid-5-1
    { key = 5; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\d6\19\cd\6a\55\fa\0e\15\0f\0d\de\69\04\12\d0\87\77\de\5f\dc\7f\65\56\ee\06\a1\dc\ac\b9\85\e0\40"; expected = true },
    // flipped-S-5-1
    { key = 5; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\29\e6\32\94\aa\05\f1\eb\f0\f2\21\96\fb\ed\2f\78\45\08\9a\d1\27\b2\47\96\ed\17\ee\16\42\dd\45\11"; expected = true },
    // changed-r-5-1
    { key = 5; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\d6\19\cd\6a\55\fa\0e\15\0f\0d\de\69\04\12\d0\87\77\de\5f\dc\7f\65\56\ee\06\a1\dc\ac\b9\85\e0\40"; expected = false },
    // valid-5-2
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\ec\67\f2\5b\38\88\3e\0e\f8\5d\b3\63\34\8f\b9\02\4c\21\59\2e\af\01\00\43\41\63\98\73\17\27\a0\ff"; expected = true },
    // flipped-S-5-2
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3e\13\98\0d\a3\c7\77\c1\f2\07\a2\4c\9c\cb\70\46\fd\70\c5\a1\7e\f8\16\9e\41\b2\56\32\4f\e5\3b\84\52"; expected = true },
    // changed-r-5-2
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\4e\76\9e\76\72\c9\dd\ad\31\85\5f\7d\b8\c7\fe\db\74\e0\2f\08\02\03\a5\6b\2d\f4\8c\04\67\7c\8a\3f\ec\67\f2\5b\38\88\3e\0e\f8\5d\b3\63\34\8f\b9\02\4c\21\59\2e\af\01\00\43\41\63\98\73\17\27\a0\ff"; expected = false },
    // valid-5-3
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\ee\4e\19\37\1d\52\7e\a8\da\2e\28\22\fd\00\e2\d0\bf\27\d6\b9\6d\28\6c\3e\48\f9\59\0d\2d\43\ed\a8"; expected = true },
    // flipped-S-5-3
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\11\b1\e6\c7\e2\ad\81\58\25\d1\d7\dd\02\ff\1d\2e\fd\bf\23\f4\39\ef\32\46\aa\c0\71\b5\cf\1f\37\a9"; expected = true },
    // changed-r-5-3
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\ee\4e\19\37\1d\52\7e\a8\da\2e\28\22\fd\00\e2\d0\bf\27\d6\b9\6d\28\6c\3e\48\f9\59\0d\2d\43\ed\a8"; expected = false },
    // valid-5-4
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\11\b1\e6\c7\e2\ad\81\58\25\d1\d7\dd\02\ff\1d\2e\fd\bf\23\f4\39\ef\32\46\aa\c0\71\b5\cf\1f\37\a8"; expected = true },
    // flipped-S-5-4
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\ee\4e\19\37\1d\52\7e\a8\da\2e\28\22\fd\00\e2\d0\bf\27\d6\b9\6d\28\6c\3e\48\f9\59\0d\2d\43\ed\a9"; expected = true },
    // changed-r-5-4
    { key = 5; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\97\11\b1\e6\c7\e2\ad\81\58\25\d1\d7\dd\02\ff\1d\2e\fd\bf\23\f4\39\ef\32\46\aa\c0\71\b5\cf\1f\37\a8"; expected = false },
    // valid-5-5
    { key = 5; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\3c\76\3c\15\13\9c\26\cd\51\6b\c5\b1\28\11\57\e9\a0\23\33\10\c6\f3\21\22\b4\59\a2\2e\db\24\61\d9"; expected = true },
    // flipped-S-5-5
    { key = 5; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\63\c3\89\c3\e9\ec\63\d9\33\ae\94\3a\4e\d7\ee\a8\16\1c\c3\c7\9c\e0\24\7d\62\3f\60\28\94\21\3e\c3\78"; expected = true },
    // changed-r-5-5
    { key = 5; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\0f\a8\22\bc\28\11\aa\a5\84\92\59\2e\32\6e\25\de\29\49\3b\aa\ad\65\1f\7e\90\e7\5c\b4\8e\14\db\64\3c\76\3c\15\13\9c\26\cd\51\6b\c5\b1\28\11\57\e9\a0\23\33\10\c6\f3\21\22\b4\59\a2\2e\db\24\61\d9"; expected = false },
    // x-ge-n-3-0-1
    { key = 6; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = true },
    // x-ge-n-highS-3-0-1
    { key = 6; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = true },
    // x-ge-n-3-1-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 7; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = true },
    // x-ge-n-highS-3-1-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 7; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = true },
    // x-ge-n-3-115792089237316195423570985008687907853269984665640564039457584007913129639935-2
    { key = 8; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02"; expected = true },
    // x-ge-n-highS-3-115792089237316195423570985008687907853269984665640564039457584007913129639935-2
    { key = 8; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4f"; expected = true },
    // x-ge-n-4-0-1
    { key = 9; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\04\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = true },
    // x-ge-n-highS-4-0-1
    { key = 9; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\04\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = true },
    // x-ge-n-4-1-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 10; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\04\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = true },
    // x-ge-n-highS-4-1-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 10; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\04\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = true },
    // x-ge-n-4-115792089237316195423570985008687907853269984665640564039457584007913129639935-2
    { key = 11; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\04\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02"; expected = true },
    // x-ge-n-highS-4-115792089237316195423570985008687907853269984665640564039457584007913129639935-2
    { key = 11; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\04\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4f"; expected = true },
    // x-ge-n-6-0-1
    { key = 12; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = true },
    // x-ge-n-highS-6-0-1
    { key = 12; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = true },
    // x-ge-n-6-1-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 13; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = true },
    // x-ge-n-highS-6-1-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 13; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = true },
    // x-ge-n-6-115792089237316195423570985008687907853269984665640564039457584007913129639935-2
    { key = 14; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02"; expected = true },
    // x-ge-n-highS-6-115792089237316195423570985008687907853269984665640564039457584007913129639935-2
    { key = 14; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4f"; expected = true },
    // identity-G-1
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-negG-1
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-G-2
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\4f"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-negG-2
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-G-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 0; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-negG-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 2; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-G-18446744073709551616
    { key = 0; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\83\f3\b9\ca\c2\fc\63\25\51"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-negG-18446744073709551616
    { key = 2; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-G-57896044618658097711785492504343953926634992332820282019728792003956564819968
    { key = 0; digest = "\7f\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\80\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // identity-negG-57896044618658097711785492504343953926634992332820282019728792003956564819968
    { key = 2; digest = "\80\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\80\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; expected = false },
    // field-boundary-0-0
    { key = 15; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-0-1
    { key = 15; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-0-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 15; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-0-115792089210356248762697446949407573529996955224135760342422259061068512044369
    { key = 15; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-0-115792089210356248762697446949407573529996955224135760342422259061068512044370
    { key = 15; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-0-115792089237316195423570985008687907853269984665640564039457584007913129639935
    { key = 15; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-115792089210356248762697446949407573530086143415290314195533631308867097853948-0
    { key = 16; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-115792089210356248762697446949407573530086143415290314195533631308867097853948-1
    { key = 16; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-115792089210356248762697446949407573530086143415290314195533631308867097853948-115792089210356248762697446949407573529996955224135760342422259061068512044368
    { key = 16; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-115792089210356248762697446949407573530086143415290314195533631308867097853948-115792089210356248762697446949407573529996955224135760342422259061068512044369
    { key = 16; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-115792089210356248762697446949407573530086143415290314195533631308867097853948-115792089210356248762697446949407573529996955224135760342422259061068512044370
    { key = 16; digest = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\52"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // field-boundary-115792089210356248762697446949407573530086143415290314195533631308867097853948-115792089237316195423570985008687907853269984665640564039457584007913129639935
    { key = 16; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50"; expected = false },
    // random-equation-0
    { key = 0; digest = "\84\cd\88\d8\2b\f6\be\b3\f9\3d\0f\2e\e6\f2\7f\9a\f1\c7\7d\3f\1c\90\60\04\58\b2\cd\ed\66\9e\ac\e1"; signature = "\10\2d\e2\9a\aa\e3\2c\31\25\20\28\7d\53\04\ec\17\e2\22\ca\90\ae\9b\67\cc\dc\5b\b9\ef\15\96\1b\d4\77\1b\a9\cf\46\e0\ef\d2\93\15\a1\3b\cd\89\bd\03\cd\e5\46\c6\29\21\b1\94\12\34\21\ae\81\f4\73\13"; expected = false },
    // random-equation-1
    { key = 1; digest = "\e2\49\ca\14\40\97\99\45\67\a3\3b\dc\5e\ca\6b\2d\2f\04\d3\93\dd\ae\c2\10\c2\5b\36\7d\0f\d4\02\9e"; signature = "\69\19\87\cd\b4\dc\2f\11\e3\4d\8f\2d\b1\1e\52\5b\8c\d1\f6\fe\86\26\0b\c4\7c\e3\d4\21\46\88\64\a5\be\a3\e9\20\ac\41\3c\e0\ed\39\d2\65\3f\dd\50\b1\db\5c\6e\a5\47\97\f8\58\e9\be\7a\aa\5d\c8\d5\f9"; expected = false },
    // random-equation-2
    { key = 2; digest = "\13\34\74\03\2e\d3\a0\a1\70\1e\c2\c1\21\39\10\c7\87\7c\ae\4b\12\9a\5e\f4\82\d5\1f\a9\30\af\c1\b2"; signature = "\f2\36\6a\09\0b\0d\13\4b\b5\f9\c0\c8\0d\e9\88\2b\90\27\30\4a\b5\b3\df\a3\c8\b4\ac\41\29\e1\20\61\db\64\8b\a9\26\a9\86\97\28\db\a5\e8\68\76\0c\7a\65\b6\e8\72\bb\64\ab\e5\3f\e8\dc\75\30\f0\70\e0"; expected = false },
    // random-equation-3
    { key = 3; digest = "\3b\1f\67\a9\a9\c4\7d\c3\06\64\1f\30\bf\a8\ef\0f\84\04\ca\94\76\1f\8e\ed\1f\5a\3a\fb\8b\8a\f1\74"; signature = "\25\96\ba\0b\b9\71\a6\92\95\ab\ae\63\aa\ec\a6\86\5b\fc\47\31\50\f5\25\e5\64\ff\74\3a\04\1c\d7\e7\b5\38\01\df\f2\1d\df\a9\c8\d7\3c\50\6b\2c\25\5c\a9\f5\ba\cd\5f\fa\69\05\ac\c9\25\6a\e5\f6\30\66"; expected = false },
    // random-equation-4
    { key = 4; digest = "\e1\64\02\96\df\cd\b5\82\8f\9f\49\02\a1\ab\d4\6d\ec\59\2d\cd\e8\15\da\33\38\39\7c\8d\32\00\31\fc"; signature = "\e2\ae\87\73\8e\54\72\16\50\2b\a7\3d\5e\fd\08\09\78\b1\2d\a5\9a\8d\e5\d3\18\f6\08\ea\df\ff\2f\e6\e5\f8\ef\e3\35\61\60\51\c8\09\28\61\72\e6\2b\2f\a6\96\58\03\f6\06\21\b8\1d\b3\2a\c6\91\7d\97\32"; expected = false },
    // random-equation-5
    { key = 5; digest = "\c3\03\b7\34\18\82\ec\3f\fc\e9\a7\ea\06\27\38\86\fd\68\fc\74\d0\9b\93\99\35\7b\e0\1a\d1\b2\2b\e4"; signature = "\c9\82\32\10\db\ff\83\fa\03\6b\36\41\d4\3e\74\80\97\1f\2d\fb\79\68\23\3e\4c\05\b3\af\d9\c9\f9\82\24\f5\dd\83\df\00\0c\b1\ce\13\88\4f\d7\b2\e9\12\90\8c\32\bc\2e\5b\36\ae\1f\d7\2f\0a\a3\4b\e0\1a"; expected = false },
    // random-equation-6
    { key = 0; digest = "\ce\c7\78\e9\68\10\6d\88\cc\f7\27\fc\43\c8\0b\8f\58\d0\38\bd\cc\26\ce\b1\bc\59\14\0a\40\d4\2a\ea"; signature = "\5d\85\9f\10\8a\65\5d\9d\37\75\3f\73\70\a9\82\b5\8c\cd\af\d1\95\38\37\e4\cb\ea\6f\22\c4\b1\30\53\17\57\0f\28\d6\2c\6d\f7\d6\71\b5\32\f6\6a\8b\ac\7f\7e\0c\09\d1\cc\b0\84\f4\bf\68\c9\f4\2a\0c\91"; expected = false },
    // random-equation-7
    { key = 1; digest = "\f4\6d\88\23\db\7e\bb\db\ad\13\b7\48\83\27\00\44\8f\1c\19\41\0a\0b\b8\a6\af\01\c4\8b\f9\0b\f3\ba"; signature = "\29\7e\70\6f\60\9f\4a\8a\44\9b\18\84\8b\cc\f1\48\50\94\b4\77\94\0a\b7\8a\88\6f\8b\be\ef\d0\59\37\eb\14\7b\cf\50\a2\62\e3\92\50\4a\f9\29\d4\86\4e\b0\3b\ec\3a\52\55\d3\3a\9a\27\14\01\0e\82\09\4b"; expected = false },
    // random-equation-8
    { key = 2; digest = "\2b\67\f8\64\18\5f\60\1c\64\39\35\f7\76\8e\42\be\a8\ba\53\19\5b\e1\e2\c6\ad\41\db\0d\75\2c\e3\25"; signature = "\b2\00\67\de\a6\82\1e\29\3e\c7\88\df\8a\78\68\2c\ac\17\f9\53\75\f4\62\eb\31\eb\1d\77\29\d4\1d\4a\f0\52\a4\6e\da\93\99\e3\ee\2f\5a\6a\9a\3b\11\fc\c1\73\87\69\73\24\05\2e\f3\08\d6\7e\83\57\ba\07"; expected = false },
    // random-equation-9
    { key = 3; digest = "\2a\a6\11\b0\23\86\f6\f5\1f\d1\6f\ed\d9\c6\2b\e5\90\b1\2b\8c\f6\a7\3a\77\f0\da\a6\4f\c8\ae\c9\5c"; signature = "\87\ae\30\cd\fc\dc\15\7d\b7\cd\05\7a\a9\20\08\c6\61\fd\1b\23\96\7c\9f\75\4a\f8\52\20\75\1b\95\d0\52\af\d0\c2\d4\40\ac\b4\f9\2e\50\1c\7b\31\48\41\15\3b\ce\bb\80\22\f6\95\53\d4\e9\e7\d3\14\74\9c"; expected = false },
    // random-equation-10
    { key = 4; digest = "\8f\d8\bb\57\15\a8\50\63\e4\57\ce\ff\fe\c9\1c\ea\68\6a\5a\b3\4b\18\d4\e0\6b\44\73\3d\6b\b8\1e\f5"; signature = "\f9\f5\5c\0a\5d\e2\90\c1\2b\0f\38\3a\a7\26\b1\41\e4\80\bb\7e\59\fe\6a\36\e1\9d\7d\7c\75\4d\49\83\c0\e2\a6\36\e7\a1\4f\cc\82\26\ed\41\e6\fb\54\85\7d\bc\a3\b3\3d\c6\26\01\37\71\94\15\53\e9\f1\3b"; expected = false },
    // random-equation-11
    { key = 5; digest = "\fa\33\28\17\4a\bb\73\bb\8a\64\4a\4f\f1\c9\f4\6f\09\a7\5b\17\c7\b3\50\16\10\4a\59\01\df\e2\de\72"; signature = "\be\48\7d\07\98\84\37\2c\3d\2b\cc\d2\90\ba\88\5e\ef\10\d9\c4\06\a4\f7\47\cb\e7\c7\fb\9b\f0\c0\fc\69\54\d7\75\7e\a7\56\4f\b9\ac\cf\c7\03\3b\d7\a5\73\90\c0\59\8f\fc\d4\ac\b9\f5\43\24\c5\33\29\3e"; expected = false },
    // random-equation-12
    { key = 0; digest = "\84\93\e6\32\56\ed\02\11\aa\f7\66\da\ef\b5\a2\b9\c2\63\4d\6b\41\9d\2a\04\0a\f8\d1\42\38\d1\92\7f"; signature = "\8f\6d\32\0f\ad\62\73\35\1c\01\fb\2f\34\08\61\dc\40\a8\45\d4\f2\1b\31\77\a9\81\64\65\2d\9f\05\6a\d9\3c\cc\6d\43\ad\d0\16\60\34\c4\e2\51\2d\10\22\54\82\ab\57\15\54\a8\14\2e\b2\43\c5\71\e7\54\8f"; expected = false },
    // random-equation-13
    { key = 1; digest = "\e8\58\36\0d\42\da\ba\cb\00\91\7b\e9\ce\c6\f1\bd\8b\0d\14\cc\1f\68\79\4c\b2\6f\ff\be\76\40\0d\4b"; signature = "\e4\57\1d\02\dc\ca\8b\64\a9\71\38\06\fd\59\18\1b\b2\dc\73\51\9f\42\03\03\d5\80\f7\e0\f0\51\18\21\f6\0f\b7\af\7e\03\7d\11\5a\d7\7c\94\77\f1\f4\a3\1a\0e\92\b1\c9\dd\ad\b0\c5\59\f4\26\e9\eb\0c\60"; expected = false },
    // random-equation-14
    { key = 2; digest = "\00\35\40\02\f3\5b\88\db\a8\69\d8\40\c1\16\53\b6\01\85\bf\04\3f\ec\95\85\b5\21\6e\e4\94\7a\ef\9f"; signature = "\80\83\ca\57\f5\e4\46\19\00\d8\2f\64\92\2e\16\e1\f2\aa\e8\5c\23\6a\69\d1\d2\86\07\61\fd\d1\1c\65\35\34\02\63\35\41\34\7c\94\d0\1b\03\55\c0\4d\c2\0f\db\9c\9b\92\ba\7f\31\61\82\0d\ce\4b\10\65\11"; expected = false },
    // random-equation-15
    { key = 3; digest = "\ba\f5\f9\cf\5e\64\98\05\31\e8\78\2a\a3\7c\65\4c\3b\ca\45\52\e6\9a\84\53\32\22\97\df\ec\38\b2\d6"; signature = "\f7\9b\01\35\1f\1d\ea\90\4d\01\01\69\2f\cd\91\7b\bf\13\c8\12\3f\96\11\6e\c0\f2\c2\57\7f\28\8c\07\63\73\66\ef\aa\69\35\9d\aa\6c\bc\c2\25\e4\66\53\62\69\5c\af\39\74\bf\af\d6\ee\f0\8a\63\fb\e4\08"; expected = false },
    // random-equation-16
    { key = 4; digest = "\49\e0\53\e5\11\c5\f4\ee\65\ed\e4\83\fd\d6\98\58\36\d3\24\75\d6\42\e0\b2\98\88\ae\11\d5\b9\3f\83"; signature = "\cf\eb\fa\f8\ef\41\b3\9a\dc\0d\2d\0b\1c\91\55\bc\1f\15\dd\31\b5\d2\94\cf\69\8d\26\f2\6a\8d\21\a9\23\78\b0\86\40\30\e6\b3\a1\2f\fb\d8\df\aa\b0\61\d9\6d\b4\22\5e\67\c1\15\bb\4f\5a\48\88\59\fd\be"; expected = false },
    // random-equation-17
    { key = 5; digest = "\8c\d8\f6\b6\51\41\5e\83\ea\29\12\8b\28\5e\5f\c5\e2\96\7b\99\05\f2\8b\4b\15\8f\f7\61\53\42\ef\29"; signature = "\c4\57\d8\e4\4d\d0\7e\26\77\58\8f\27\99\bc\0e\39\ae\dc\a0\d3\b3\dd\17\46\7a\b1\ce\80\16\fb\9a\a5\2f\69\87\1d\cb\42\1f\02\2f\69\f0\fa\a7\b0\fb\1e\3e\0d\3f\83\1f\70\41\2f\dd\af\20\3a\d7\5e\ad\8d"; expected = false },
    // random-equation-18
    { key = 0; digest = "\cb\ef\f6\01\06\f0\4f\5c\9e\c6\5f\b6\ce\7a\6f\f9\66\b3\2f\d8\10\f8\f1\a7\bf\58\cc\d9\04\94\6c\5c"; signature = "\1c\06\c9\4b\fd\b7\20\43\22\ed\a2\93\68\3f\b7\a6\9d\4c\56\84\8b\fb\3d\14\10\e5\dc\0b\d6\8a\31\d5\df\6f\bc\e2\73\a4\44\92\ce\d2\f2\3d\17\9b\b0\07\d3\27\64\85\c4\6b\0b\76\7e\d3\80\a1\41\50\3f\ef"; expected = false },
    // random-equation-19
    { key = 1; digest = "\ea\f7\52\a1\ec\e8\01\ec\f6\80\22\40\72\9d\7a\60\e6\c4\7d\34\20\56\16\01\9e\b7\4d\6e\89\2f\3a\ae"; signature = "\c5\9d\1c\a6\be\e3\5c\a9\e5\ee\57\90\6c\40\cc\67\3b\f9\ed\fe\36\cb\82\4b\9a\bf\01\eb\85\e1\64\19\de\6e\71\ab\38\1e\19\72\47\34\eb\70\fb\b3\ae\3e\20\d2\cd\cd\ae\54\11\e2\76\1a\be\c1\ac\ad\fe\d9"; expected = false },
    // random-equation-20
    { key = 2; digest = "\1a\f9\f6\2f\bb\da\37\03\9d\cf\0d\90\80\81\74\d4\9f\8d\61\7d\45\c3\3f\7a\48\75\3f\97\3d\01\d0\2d"; signature = "\6d\7b\36\fb\58\82\3c\93\ae\01\eb\69\3d\02\54\06\df\96\c1\a8\24\c7\24\14\6c\07\6d\09\a7\f1\6f\5c\49\69\ef\78\d6\a9\ff\83\64\ee\46\21\64\5e\79\dc\0b\31\f6\da\4c\d2\24\90\a9\b1\cd\be\21\9d\d6\5b"; expected = false },
    // random-equation-21
    { key = 3; digest = "\51\1d\ed\e3\8f\47\6d\c3\b0\87\d9\54\63\1e\2f\98\6b\e1\fe\9b\8c\8a\2a\53\3b\52\95\6b\2d\b9\1d\4d"; signature = "\ee\f5\43\b6\e7\f4\11\b2\ed\02\87\6e\22\61\94\1a\cb\9e\de\0b\ad\cd\42\7b\1c\61\c3\de\bb\27\f8\ae\71\28\d5\41\43\34\1a\de\4b\54\6c\fa\cf\e9\dc\6d\05\e5\3b\4b\56\a6\1d\9a\1b\7c\85\26\7e\b1\18\29"; expected = false },
    // random-equation-22
    { key = 4; digest = "\92\c6\90\4c\2c\5e\f8\19\a7\79\43\06\d5\2e\6e\19\00\8d\24\d7\53\15\a5\e6\b0\8e\ba\73\04\3f\24\e7"; signature = "\a8\d2\ec\e9\a3\e3\27\71\2d\25\42\61\0c\e0\ed\fc\11\b7\ce\ae\b6\16\21\e5\cb\78\6b\8c\45\04\0c\98\de\f6\29\f8\ae\53\58\5a\df\f2\6f\e8\4b\06\4f\7e\9f\60\b0\d1\53\49\07\ed\05\f8\f9\f9\f7\2e\32\c6"; expected = false },
    // random-equation-23
    { key = 5; digest = "\5e\bf\7d\7f\bf\ab\ea\f1\74\43\60\fd\89\9d\ff\6a\27\1e\8d\b5\28\2e\0d\cc\03\65\cb\65\b1\73\f2\bc"; signature = "\1c\70\66\64\bd\0a\e0\00\a8\3b\93\f9\9d\12\2e\70\af\44\ac\e3\e0\e1\f9\77\d0\e0\d1\c0\df\08\f6\1b\86\09\d3\c5\a5\6d\41\37\e4\de\6e\28\55\89\03\e7\ac\2c\ac\37\54\aa\65\7c\d7\72\28\44\75\d1\ea\c2"; expected = false },
    // random-equation-24
    { key = 0; digest = "\89\a4\ea\6c\aa\2d\92\90\a2\73\f6\8d\b8\f1\13\26\a4\e2\87\4e\aa\dc\2f\1d\18\88\db\47\5f\5c\0f\c1"; signature = "\8b\1a\ef\26\b7\2e\e3\ee\9a\75\f8\ff\da\6c\ab\68\5c\14\67\ad\eb\02\bd\93\55\4b\6b\59\1d\73\0f\0c\4d\c5\6a\d3\19\12\3e\cd\51\12\8e\3e\db\2d\8b\ee\ca\db\49\f8\d0\7b\56\00\4f\4b\ec\a3\58\64\01\93"; expected = false },
    // random-equation-25
    { key = 1; digest = "\0e\e4\69\88\a8\36\9e\4c\48\1d\0a\b5\78\c2\7b\00\a7\c9\54\bc\91\83\4f\9b\a1\6a\9d\b3\c9\85\f0\60"; signature = "\94\e7\78\cc\02\1e\9a\a9\3a\c3\7a\31\09\3d\16\7b\18\4d\fa\a4\77\24\b8\e5\2a\60\88\da\70\a5\de\44\5e\d4\63\67\93\53\4a\00\79\c1\2a\e7\0d\da\46\00\20\f7\87\22\62\ff\bb\97\8d\b6\69\b5\ed\bb\88\43"; expected = false },
    // random-equation-26
    { key = 2; digest = "\74\b6\24\94\2b\99\c0\71\c4\08\d3\ad\2a\6d\f7\b5\4d\48\33\b3\33\04\cc\44\a6\98\7d\fc\c7\75\07\9f"; signature = "\96\d3\64\db\43\a8\6d\11\c2\b1\fb\5d\36\e9\80\ea\28\4a\6e\d0\ee\cc\58\1c\81\25\33\77\30\29\3c\89\f4\e2\af\3e\17\05\53\a0\3c\4d\ab\9d\f2\c9\a5\6b\1e\2e\98\85\32\30\34\4f\96\82\b8\75\b9\06\bc\91"; expected = false },
    // random-equation-27
    { key = 3; digest = "\24\09\29\6f\9a\67\84\09\d8\79\8d\13\b9\05\30\11\14\29\82\96\e6\dc\38\0c\bd\43\72\3e\f8\ba\38\0a"; signature = "\3b\45\3d\29\53\46\98\94\a7\b1\1c\d9\7b\93\57\b4\78\6c\ef\10\35\71\9d\fb\d5\98\ed\9e\42\62\ce\a1\3c\c4\ea\0c\e9\db\6f\3e\49\05\b4\a9\22\4f\db\01\b8\a1\fd\20\09\ae\04\31\20\a1\0e\c6\f3\fd\81\c2"; expected = false },
    // random-equation-28
    { key = 4; digest = "\f8\eb\59\e2\c2\78\18\31\17\16\cc\ed\c4\36\17\fe\64\31\87\bd\48\5f\9a\44\d1\50\37\50\6d\08\fd\cb"; signature = "\e8\79\6b\72\b3\99\6c\4e\21\eb\bf\20\83\df\0a\ec\2a\f0\1c\e0\c9\70\25\33\d5\2f\08\08\76\5e\84\b2\d5\e7\f7\86\41\20\75\bf\6c\9a\71\fe\95\b3\f1\a4\c0\3e\5f\17\0f\83\b2\4c\3d\19\ab\24\d3\14\03\f3"; expected = false },
    // random-equation-29
    { key = 5; digest = "\31\d1\f3\cb\c9\03\92\10\28\6e\03\9d\ea\50\70\e5\49\60\ae\9f\c7\e5\f1\2f\34\f0\c9\47\0c\36\ea\97"; signature = "\ef\dc\48\2b\94\2e\2d\29\03\1f\fb\7b\44\56\95\e6\00\1f\a4\46\5c\09\86\dc\13\8a\c0\c1\04\76\81\e0\8f\89\4a\d8\bf\bf\a5\4d\7e\9f\be\63\59\a2\2e\36\b9\a7\7a\fb\89\83\3d\b0\08\24\18\23\d4\53\5f\8f"; expected = false },
    // random-equation-30
    { key = 0; digest = "\df\76\1d\2d\eb\17\86\0b\a3\68\e1\a7\05\e4\14\25\14\21\e3\b4\88\04\39\84\91\67\cb\b7\64\95\2d\f8"; signature = "\7b\61\2c\ac\37\62\cc\3f\55\03\c1\38\0e\e5\a2\6b\88\39\3f\ff\c2\b0\55\78\83\2f\da\8f\96\7a\51\ac\1a\f8\07\0f\03\bc\70\3f\a9\e2\77\74\f3\9d\7b\0e\bc\3e\ba\eb\e8\ee\79\4c\a7\8a\ae\d5\40\ae\83\22"; expected = false },
    // random-equation-31
    { key = 1; digest = "\07\1f\b5\b1\89\7d\5f\26\6d\8e\5d\66\f9\56\86\fd\76\73\a2\d6\64\bf\77\6c\e1\63\24\97\ae\2a\f9\4a"; signature = "\df\e3\fb\15\9f\c2\53\40\b3\97\c1\e9\1b\80\73\6a\18\32\ab\31\6d\93\5d\58\7a\03\8f\04\41\f0\dc\e5\26\0c\3a\81\11\34\a1\cb\f2\0c\18\a5\3d\d8\1a\c3\6f\90\77\04\67\57\eb\c9\bd\59\e7\88\5d\df\3e\b9"; expected = false },
  ];
  public let invalidKeys : [Blob] = [
    "",
    "\00",
    "\02",
    "\04",
    "\05\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00",
    "\02\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff",
    "\03\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff",
    "\04\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00",
    "\04\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\4f\e3\42\e2\fe\1a\7f\9b\8e\e7\eb\4a\7c\0f\9e\16\2b\ce\33\57\6b\31\5e\ce\cb\b6\40\68\37\bf\51\f5",
    "\04\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\ff\ff\ff\ff\00\00\00\01\00\00\00\00\00\00\00\00\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff",
    "\06\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\4f\e3\42\e2\fe\1a\7f\9b\8e\e7\eb\4a\7c\0f\9e\16\2b\ce\33\57\6b\31\5e\ce\cb\b6\40\68\37\bf\51\f5",
  ];
  public let invalidSignatures : [Blob] = [
    "",
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00",
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00",
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00",
    "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96",
    "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96",
    "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96",
    "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00",
    "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51",
    "\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff",
  ];
  public func ok<T>(r : P256.Result<T>) : T {
    switch r { case (#ok x) x; case (#err _) Prim.trap("prepared P256 audit: unexpected error") }
  };
  public func copy(b : Blob) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(b.size(), func(i) { b[i] }))
  };
  public func run() {
    let prepared = Prim.Array_tabulate<P256.PreparedPublicKey>(keys.size(), func(i) {
      ok(P256.preparePublicKey(copy(keys[i].compressed)))
    });
    let uncompressed = Prim.Array_tabulate<P256.PreparedPublicKey>(keys.size(), func(i) {
      ok(P256.preparePublicKey(copy(keys[i].uncompressed)))
    });
    for (v in vectors.values()) {
      assert P256.verifyPrehashPrepared(prepared[v.key], v.digest, v.signature) == #ok(v.expected);
      assert P256.verifyPrehashPrepared(uncompressed[v.key], v.digest, v.signature) == #ok(v.expected);
      assert P256.verifyPrehash(keys[v.key].compressed, v.digest, v.signature) == #ok(v.expected);
    };
    for (key in invalidKeys.values()) {
      switch (P256.preparePublicKey(key)) {
        case (#err(#invalidPublicKey)) {};
        case _ Prim.trap("prepared P256 audit: malformed key accepted");
      }
    };
    let first = vectors[0];
    let p = prepared[first.key];
    assert P256.verifyPrehashPrepared(p, "", "") == #err(#invalidDigest);
    assert P256.verifyPrehashPrepared(p, first.digest, "") == #err(#invalidSignature);
    for (signature in invalidSignatures.values()) {
      assert P256.verifyPrehashPrepared(p, first.digest, signature) == #err(#invalidSignature);
      assert P256.verifyPrehashPrepared(p, "", signature) == #err(#invalidDigest);
    };
    func identity<T>(x : T) : T { x };
    let returned = identity({ values = [p]; read = func() : P256.PreparedPublicKey { p } });
    assert P256.verifyPrehashPrepared(returned.values[0], first.digest, first.signature) == #ok(first.expected);
    assert P256.verifyPrehashPrepared(returned.read(), first.digest, first.signature) == #ok(first.expected);
    let verify = P256.verifyPrehashPrepared;
    var sequence = 0;
    func keyArg() : P256.PreparedPublicKey { assert sequence == 0; sequence := 1; p };
    func digestArg() : Blob { assert sequence == 1; sequence := 2; first.digest };
    func signatureArg() : Blob { assert sequence == 2; sequence := 3; first.signature };
    assert verify(keyArg(), digestArg(), signatureArg()) == #ok(first.expected);
    assert sequence == 3;
  };
}
