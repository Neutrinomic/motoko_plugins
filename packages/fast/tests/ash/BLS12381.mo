import Test "mo:test";
import B "mo:fast/BLS12381";
import Prim "mo:⛔";
persistent actor {
  public func test_public_groups_profiles_aggregation_and_errors() : async Test.Metrics {
    Test.test(func() {
// Independent py_ecc8.0.0 fixtures; reproducible generator and source JSON live
// under plugins/bls12-381/tests/vectors. No other plugin is loaded.
func pack(parts : [Blob]) : Blob {
  var n=0; for (p in parts.values()) n += p.size();
  let a=Prim.Array_init<Nat8>(n,0); var i=0;
  for (p in parts.values()) { for (x in p.values()) { a[i]:=x; i+=1 } };
  Prim.arrayMutToBlob(a)
};
let zero : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
let one : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
let ethKey0 : Blob = "\8c\e3\b5\7b\79\17\98\43\3f\d3\23\75\34\89\ca\c9\bc\a4\3b\98\de\aa\fa\ed\91\f4\cb\01\07\30\ae\1e\38\b1\86\cc\d3\7a\09\b8\ae\d6\2c\e2\3b\69\9c\48";
let proof0 : Blob = "\96\9a\1f\7e\52\0b\cd\7e\3d\a7\91\bb\78\83\83\06\2d\30\c8\b0\f2\b3\eb\d6\70\0e\04\1e\1b\a1\e9\83\bb\d5\e3\10\38\0f\6c\5b\a2\5d\a8\1c\91\64\87\f9\19\2b\c3\3c\0c\95\78\1d\d4\b2\31\6b\bd\9a\9e\a3\4a\20\ff\ac\32\9c\f6\17\f6\68\f8\47\f4\07\19\4f\db\b4\77\7e\a2\b9\35\7b\d9\7e\20\69\11\6b\04\a1";
let ethSig0 : Blob = "\b1\aa\6e\7f\01\59\53\4f\f0\cb\ae\66\82\f5\92\66\01\7b\5b\36\67\ab\cb\0f\2e\00\b8\6f\18\8a\e9\85\73\89\9b\28\e3\7a\be\e8\bb\38\8d\aa\61\af\1f\00\19\ce\bf\86\42\32\05\6a\16\e0\05\89\86\01\82\86\55\7d\f8\d9\0c\44\43\aa\a5\2d\f8\15\be\c3\98\37\4d\cf\82\15\19\9d\51\8a\9c\22\04\c5\9c\8a\e5\46";
let icKey0 : Blob = "\ac\7f\a6\3d\fc\38\bb\f3\71\2e\27\a1\80\39\1b\ca\4c\ca\bf\60\9c\59\67\a0\59\2e\ff\42\0b\62\35\f3\f2\b3\23\05\1c\b0\99\ac\c3\96\9a\ca\31\0f\7f\f4\19\1b\2d\6d\b4\3f\af\c2\c9\59\2f\7e\5f\73\98\11\07\97\5d\3d\92\b8\43\89\1e\72\4d\bc\9f\05\b5\ee\e5\a3\b2\b1\fc\78\2e\de\81\49\f3\08\30\b8\44\44";
let icSig0 : Blob = "\87\98\25\f4\7b\8e\04\67\fb\63\0a\a2\17\49\3d\92\5a\0f\7f\e6\76\32\a6\a3\49\59\ce\74\fc\da\a5\89\69\45\2a\bf\b5\87\df\83\4c\ec\96\5a\85\67\28\a8";
let ethKey1 : Blob = "\8f\81\b1\9e\e2\e4\d4\d0\ff\63\84\c6\3b\ac\b7\85\bc\05\c4\fc\22\e6\f5\53\07\9c\c4\ff\7e\02\70\d4\58\95\15\33\45\8a\01\d1\60\b2\2d\59\a8\bd\9a\b5";
let proof1 : Blob = "\b0\c2\9b\d1\e9\de\b5\e1\58\29\0d\ca\42\b9\0d\40\ef\8a\5a\9e\b9\5f\f2\a6\71\91\5f\91\69\53\3f\26\a6\48\5d\61\aa\82\ed\78\06\71\05\14\ca\d6\6e\45\0a\8a\b9\a4\83\a4\61\9d\6e\c2\54\ef\c8\42\f2\1b\ee\47\80\e6\1f\48\74\d0\a6\ee\e2\5a\ec\30\10\66\0e\7e\ad\78\0c\12\42\d1\9e\4f\10\2e\82\52\97\a3";
let ethSig1 : Blob = "\b4\8f\9c\90\7b\b9\99\4d\84\06\de\fa\f8\44\c8\fc\96\5e\12\ab\67\0d\34\ef\90\80\79\43\05\7e\37\73\9e\8d\8b\20\d3\c3\1b\47\e3\82\0f\1e\52\75\fd\b4\01\85\4b\2d\27\3a\c5\85\c0\82\28\49\50\4d\bd\2c\04\9f\27\89\ee\c4\6d\61\46\bb\28\82\58\3e\d5\c2\04\7e\11\be\fa\32\78\5f\88\01\15\d3\db\53\ad\5e";
let icKey1 : Blob = "\b6\0f\71\d2\f8\c8\49\56\d9\22\54\9c\e9\9c\be\21\6c\66\ff\ca\2c\b9\c0\5f\44\63\36\a7\3f\94\cb\d9\00\cd\d3\c9\d1\77\21\d8\26\ec\1d\b4\b7\15\27\8b\0d\3d\f6\ea\01\d7\5f\b8\c4\ad\bb\59\5f\78\21\77\1e\00\4d\67\9c\4e\26\1b\3e\02\23\25\c3\8c\69\d5\68\6f\2e\ad\b7\13\5d\1b\74\7e\5a\c0\0e\16\0a\b2";
let icSig1 : Blob = "\b0\05\16\e3\5f\d8\39\a6\69\41\61\6e\53\e0\14\62\dc\0b\8e\45\20\75\05\8d\1e\e5\02\ea\e7\a8\8d\e6\41\e3\9c\d9\68\01\03\2b\37\76\c2\6d\0d\d3\de\c5";
let ethAggregate : Blob = "\95\33\7a\c4\82\a0\04\ae\6e\9b\a6\cb\50\86\81\d1\b5\eb\84\2a\98\37\29\1c\0f\49\16\81\97\fc\5b\08\c5\50\64\5b\a5\16\0b\74\a1\bf\53\34\f0\83\bc\d3\15\59\47\39\e6\d1\a8\5e\67\7c\37\8e\56\44\67\dd\9a\de\2d\b8\f5\75\18\6b\23\e9\62\23\b5\2d\12\fc\30\f3\58\46\e5\2f\bd\c7\af\e7\f1\b4\49\ec\5f\e7";
let ethSame : Blob = "\a0\e3\da\b2\9b\14\a4\f3\f2\c4\fb\bd\84\68\b5\69\61\d4\59\2e\c2\44\15\b9\18\4a\3b\9f\67\94\36\5e\f2\cf\83\5f\09\ab\0f\b4\b8\43\04\d4\95\1f\6d\d6\09\9e\9c\31\94\09\23\13\01\b4\ce\2d\58\7a\4d\c2\39\98\bc\e5\a4\22\7b\cd\9d\d2\4b\03\7e\ca\e9\59\98\4c\82\b6\67\a1\35\2a\3a\2e\42\2e\7b\10\cb\84";
let icAggregate : Blob = "\b2\5b\2a\47\05\a2\64\17\05\79\83\62\3f\b1\3c\99\b4\48\23\10\f8\43\31\58\cc\12\70\11\ba\ac\b5\b3\25\89\03\09\e9\84\08\63\e6\d0\75\da\6f\08\3f\e7";
assert B.validateG1(B.g1Generator) == #ok(B.g1Generator);
assert B.validateG2(B.g2Generator) == #ok(B.g2Generator);
assert B.validateG1(B.g1Identity) == #ok(B.g1Identity);
assert B.g1Mul(B.g1Generator, zero) == #ok(B.g1Identity);
assert B.g2Mul(B.g2Generator, one) == #ok(B.g2Generator);
assert B.g1Add(B.g1Identity, ethKey0) == #ok(ethKey0);
assert B.g2Add(B.g2Identity, icKey0) == #ok(icKey0);
assert B.g1Msm("", "") == #ok(B.g1Identity);
assert B.g2Aggregate("") == #ok(B.g2Identity);
assert B.g1Msm(pack([ethKey0,ethKey1]), pack([one,one])) == B.g1Aggregate(pack([ethKey0,ethKey1]));
assert B.g2Msm(pack([icKey0,icKey1]), pack([one,one])) == B.g2Aggregate(pack([icKey0,icKey1]));
assert B.pairingCheck("") == #ok(true);
assert B.pairingCheck(pack([B.g1Generator, B.g2Generator])) == #ok(false);
assert B.pairingCheck(pack([B.g1Identity, B.g2Generator])) == #ok(true);
assert B.verifyIC(icKey1,"beta",icSig1) == #ok(true);
assert B.verifyEthereum(ethKey1,"beta",ethSig1) == #ok(true);
assert B.verifyIC(icKey0,"alpha",icSig0) == #ok(true);
assert B.verifyIC(icKey0,"changed",icSig0) == #ok(false);
assert B.verifyEthereum(ethKey0,"alpha",ethSig0) == #ok(true);
assert B.verifyEthereum(ethKey0,"changed",ethSig0) == #ok(false);
assert B.verifyEthereumProof(ethKey0, proof0) == #ok(true);
assert B.verifyEthereumProof(ethKey1, proof0) == #ok(false);
assert B.verifyEthereum(ethKey0,ethKey0,proof0) == #ok(false);
assert B.aggregateVerifyIC([icKey0,icKey1],["alpha","beta"],icAggregate) == #ok(true);
assert B.aggregateVerifyIC([icKey0,icKey1],["alpha","alpha"],icAggregate) == #err(#duplicateMessage);
assert B.aggregateVerifyIC([icKey0,icKey1],["alpha","changed"],icAggregate) == #ok(false);
assert B.aggregateVerifyEthereum([ethKey0,ethKey1],[proof0,proof1],["alpha","beta"],ethAggregate) == #ok(true);
assert B.aggregateVerifyEthereum([ethKey0,ethKey1],[proof0,proof1],["alpha","changed"],ethAggregate) == #ok(false);
assert B.aggregateVerifyEthereum([ethKey0,ethKey1],[proof1,proof0],["alpha","beta"],ethAggregate) == #err(#invalidProof);
assert B.fastAggregateVerifyEthereum([ethKey0,ethKey1],[proof0,proof1],"alpha",ethSame) == #ok(true);
assert B.fastAggregateVerifyEthereum([ethKey0,ethKey1],[proof1,proof0],"alpha",ethSame) == #err(#invalidProof);
assert B.verifyEthereum(B.g1Identity,"",B.g2Identity) == #err(#identity);
assert B.verifyIC(B.g2Identity,"",B.g1Identity) == #err(#identity);
// Decoder errors precede identity rejection identically in both interpreters/Wasm.
assert B.verifyIC(B.g2Identity,"", "") == #err(#invalidLength);
assert B.verifyEthereum(B.g1Identity,"", "") == #err(#invalidLength);
assert B.verifyEthereumProof(B.g1Identity, "") == #err(#invalidLength);
assert B.validateG1("") == #err(#invalidLength);
assert B.validateG2("short") == #err(#invalidLength);
assert B.hashToG1("abc", "") == #err(#invalidArgument);
assert B.hashToG2("abc", "") == #err(#invalidArgument);
assert B.aggregateVerifyIC([],[],B.g1Identity) == #err(#emptyBatch);
assert B.aggregateVerifyEthereum([],[],[],B.g2Identity) == #err(#emptyBatch);
assert B.fastAggregateVerifyEthereum([],[],"",B.g2Identity) == #err(#emptyBatch);
assert B.aggregateVerifyIC([icKey0],[],icSig0) == #err(#invalidLength);
let over = Prim.Array_tabulate<Blob>(129,func(_) { B.g1Identity });
assert B.g1Aggregate(pack(over)) == #err(#tooManyItems);
let keys = Prim.Array_tabulate<Blob>(128,func(_) { ethKey0 });
let proofs = Prim.Array_tabulate<Blob>(128,func(_) { proof0 });
let messages = Prim.Array_tabulate<Blob>(128,func(_) { "alpha" });
assert B.aggregateVerifyEthereum(keys,proofs,messages,ethAggregate) == #err(#tooManyItems);
let order : Blob = "\73\ed\a7\53\29\9d\7d\48\33\39\d8\08\09\a1\d8\05\53\bd\a4\02\ff\fe\5b\fe\ff\ff\ff\ff\00\00\00\01";
assert B.g1Mul(B.g1Generator,order) == #err(#invalidScalar);
assert B.g1Msm(pack([B.g1Generator,Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(48,func(_){0}))]),pack([order,one])) == #err(#invalidScalar);

// Independent full-width 4-term fixtures exercise the public-scalar bucket MSM.
let wideScalars : Blob = "\73\ed\a7\53\29\9d\7d\48\33\39\d8\08\09\a1\d8\05\53\bd\a4\02\ff\fe\5b\fe\ff\ff\ff\ff\00\00\00\00\01\23\45\67\89\ab\cd\ef\01\23\45\67\89\ab\cd\ef\01\23\45\67\89\ab\cd\ef\01\23\45\67\89\ab\cd\ef\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
assert B.g1Msm(pack([B.g1Generator,ethKey0,ethKey1,B.g1Identity]),wideScalars) == #ok("\80\6d\d4\84\32\cc\f9\b5\d3\2b\75\4a\2f\92\e0\aa\d9\47\46\98\8c\9e\c9\79\b8\4d\38\74\ba\f6\c1\90\22\0e\bb\03\c5\36\13\03\53\21\39\40\26\3c\4a\80");
assert B.g2Msm(pack([B.g2Generator,icKey0,icKey1,B.g2Identity]),wideScalars) == #ok("\a0\09\7c\e3\f2\d3\ef\01\19\85\43\f0\61\f2\e3\6a\33\e7\4f\4d\cf\67\5f\d8\92\12\0c\57\bf\f2\68\b3\48\7c\3a\ab\7c\2f\e0\06\cf\6b\1d\d4\41\d9\73\4a\0e\b7\90\1d\e6\f4\92\0f\d8\74\84\26\72\63\ac\6c\f6\be\c8\61\7b\dc\1f\90\2f\c6\14\08\bf\4c\7f\56\24\27\e2\0d\a3\27\a7\9c\a1\dd\93\11\cd\9e\f8\1d");
    })
  };
  public func test_rfc9380_and_exceptional_zero_field() : async Test.Metrics {
    Test.test(func() {
// Independent official RFC9380 vectors. Full source JSON and provenance in runtime/vectors.
assert B.hashToG1("", "QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_") == #ok("\85\29\26\ad\d2\20\7b\76\ca\4f\a5\7a\87\34\41\6c\8d\c9\5e\24\50\17\72\c8\14\27\87\00\ee\d6\d1\e4\e8\cf\62\d9\c0\9d\b0\fa\c3\49\61\2b\75\9e\79\a1");
assert B.hashToG1("abc", "QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_") == #ok("\83\56\7b\c5\ef\9c\69\0c\2a\b2\ec\df\6a\96\ef\1c\13\9c\c0\b2\f2\84\dc\a0\a9\a7\94\33\88\a4\9a\3a\ee\66\4b\a5\37\9a\76\55\d3\c6\89\00\be\2f\69\03");
assert B.hashToG1("abcdef0123456789", "QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_") == #ok("\91\e0\b0\79\de\a2\9a\68\f0\38\3e\e9\4f\ed\1b\94\09\95\27\24\07\e3\bb\91\6b\bf\26\8c\26\3d\dd\57\a6\a2\72\00\a7\84\cb\c2\48\e8\4f\35\7c\e8\2d\98");
assert B.hashToG1("q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq", "QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_") == #ok("\b5\f6\8e\aa\69\3b\95\cc\b8\52\15\dc\65\fa\81\03\8d\69\62\9f\70\ae\ee\0d\0f\67\7c\f2\22\85\e7\bf\58\d7\cb\86\ee\fe\8f\2e\9b\c3\f8\cb\84\fa\c4\88");
assert B.hashToG1("a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "QUUX-V01-CS02-with-BLS12381G1_XMD:SHA-256_SSWU_RO_") == #ok("\88\2a\ab\ae\8b\7d\ed\b0\e7\8a\eb\61\9a\d3\bf\d9\27\7a\2f\77\ba\7f\ad\20\ef\6a\ab\dc\6c\31\d1\9b\a5\a6\d1\22\83\55\32\94\c1\82\5c\4b\3c\a2\dc\fe");
assert B.hashToG2("", "QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_") == #ok("\a5\cb\84\37\53\5e\20\ec\ff\ae\f7\75\2b\ad\df\98\03\41\39\c3\84\52\45\8b\ae\ef\ab\37\9b\a1\3d\ff\5b\f5\dd\71\b7\24\18\71\70\47\f5\b0\f3\7d\a0\3d\01\41\eb\fb\dc\a4\0e\b8\5b\87\14\2e\13\0a\b6\89\c6\73\cf\60\f1\a3\e9\8d\69\33\52\66\f3\0d\9b\8d\4a\c4\4c\10\38\e9\dc\dd\53\93\fa\f5\c4\1f\b7\8a");
assert B.hashToG2("abc", "QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_") == #ok("\93\9c\dd\bc\cd\c5\e9\1b\96\23\ef\d3\8c\49\f8\1a\6f\83\f1\75\e8\0b\06\fc\37\4d\e9\eb\4b\41\df\e4\ca\3a\23\0e\d2\50\fb\e3\a2\ac\f7\3a\41\17\7f\d8\02\c2\d1\8e\03\3b\96\05\62\aa\e3\ca\b3\7a\27\ce\00\d8\0c\cd\5b\a4\b7\fe\0e\7a\21\02\45\12\9d\be\c7\78\0c\cc\79\54\72\5f\41\68\af\f2\78\77\76\e6");
assert B.hashToG2("abcdef0123456789", "QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_") == #ok("\99\0d\11\93\45\b9\4f\bd\15\49\7b\cb\a9\4e\cf\7d\b2\cb\fd\1e\1f\e7\da\03\4d\26\cb\ba\16\9f\b3\96\82\88\b3\fa\fb\26\5f\9e\bd\38\05\12\a7\1c\3f\2c\12\19\82\81\1d\24\91\fd\e9\ba\7e\d3\1e\f9\ca\47\4f\0e\15\01\29\7f\68\c2\98\e9\f4\c0\02\8a\dd\35\ae\a8\bb\83\d5\3c\08\cf\c0\07\c1\e0\05\72\3c\d0");
assert B.hashToG2("q128_qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq", "QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_") == #ok("\89\34\ab\a5\16\a5\2d\8a\e4\79\93\9a\91\99\82\99\c7\6d\39\cc\0c\03\5c\d1\88\13\be\c4\33\f5\87\e2\d7\a4\fe\f0\38\26\0e\ef\0c\ef\4d\02\aa\e3\eb\91\19\a8\4d\d7\24\8a\10\66\f7\37\cc\34\50\2e\e5\55\5b\d3\c1\9f\2e\cd\b3\c7\d9\e2\4d\c6\5d\4e\25\e5\0d\83\f0\f7\71\05\e9\55\d7\8f\47\62\d3\3c\17\da");
assert B.hashToG2("a512_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "QUUX-V01-CS02-with-BLS12381G2_XMD:SHA-256_SSWU_RO_") == #ok("\91\fc\a2\ff\52\55\72\79\5a\80\1e\ed\17\eb\12\78\58\87\c7\b6\3f\b7\7a\42\be\46\ce\4a\34\13\1d\71\f7\a7\3e\95\fe\e3\f8\12\ae\a3\de\78\b4\d0\15\69\01\a6\ba\2f\9a\11\fa\55\98\b2\d8\ac\e0\fb\e0\a0\ea\cb\65\de\ce\b4\76\fb\bc\b6\4f\d2\45\57\c2\f4\b1\8e\cf\c5\66\3e\54\ae\16\a8\4f\5a\b7\f6\25\34");
let zero = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(96,func(_){0}));
// The all-zero Fp2 map exercises a zkcrypto exceptional branch absent from RFC hash vectors.
assert B.mapToG2(zero) == #ok("\8a\67\d1\21\18\b5\a3\5b\b0\2d\2e\86\b3\eb\fa\7e\23\41\0d\b9\3d\e3\9f\b0\6d\70\25\fa\95\e9\6f\fa\42\8a\7a\27\c3\ae\4d\d4\b4\0b\d2\51\ac\65\88\92\01\83\20\89\6e\c9\ee\f9\d5\e6\19\84\8d\c2\9c\e2\66\f4\13\d0\2d\d3\1d\9b\9d\44\ec\0c\79\cd\61\f1\8b\07\5d\db\a6\d7\bd\20\b7\ff\27\a4\b3\24\bf\ce");
    })
  };
}
