//MOC-FLAG --package fast ../../src --plugin ../../../../dist/bls12-381 --sanity-checks
import B "mo:fast/BLS12381";
import Prim "mo:⛔";
// Independent py_ecc 8.0.0 fixtures. Test-only scalars are 42, 43, and r-42.
// Keys/PoPs = SkToPk/PopProve; signatures = Aggregate(Sign(sk_i, message_i)).
// Fixtures never come from the plugin under test.
func repeat<T>(n : Nat, value : T) : [T] { Prim.Array_tabulate<T>(n,func(_){value}) };

let key0 : Blob = "\8c\e3\b5\7b\79\17\98\43\3f\d3\23\75\34\89\ca\c9\bc\a4\3b\98\de\aa\fa\ed\91\f4\cb\01\07\30\ae\1e\38\b1\86\cc\d3\7a\09\b8\ae\d6\2c\e2\3b\69\9c\48";
let proof0 : Blob = "\96\9a\1f\7e\52\0b\cd\7e\3d\a7\91\bb\78\83\83\06\2d\30\c8\b0\f2\b3\eb\d6\70\0e\04\1e\1b\a1\e9\83\bb\d5\e3\10\38\0f\6c\5b\a2\5d\a8\1c\91\64\87\f9\19\2b\c3\3c\0c\95\78\1d\d4\b2\31\6b\bd\9a\9e\a3\4a\20\ff\ac\32\9c\f6\17\f6\68\f8\47\f4\07\19\4f\db\b4\77\7e\a2\b9\35\7b\d9\7e\20\69\11\6b\04\a1";
let repeatedSignature : Blob = "\ad\cb\f0\82\e1\7d\8f\02\d5\c1\f5\ea\0e\c2\c8\a9\4e\80\cf\17\9a\42\76\7e\7b\e8\bb\10\38\3c\a5\c2\74\0f\13\dc\6e\98\a9\cc\86\61\93\7e\20\b2\e1\40\03\53\63\07\75\55\76\41\c6\19\bd\a5\09\26\e2\7d\19\ff\72\87\eb\23\2f\75\68\5e\e6\2c\c5\fd\a0\d6\40\50\47\c1\85\8f\65\8c\92\1b\65\55\47\41\69\4c";
let signature0 : Blob = "\b1\aa\6e\7f\01\59\53\4f\f0\cb\ae\66\82\f5\92\66\01\7b\5b\36\67\ab\cb\0f\2e\00\b8\6f\18\8a\e9\85\73\89\9b\28\e3\7a\be\e8\bb\38\8d\aa\61\af\1f\00\19\ce\bf\86\42\32\05\6a\16\e0\05\89\86\01\82\86\55\7d\f8\d9\0c\44\43\aa\a5\2d\f8\15\be\c3\98\37\4d\cf\82\15\19\9d\51\8a\9c\22\04\c5\9c\8a\e5\46";
let key1 : Blob = "\8f\81\b1\9e\e2\e4\d4\d0\ff\63\84\c6\3b\ac\b7\85\bc\05\c4\fc\22\e6\f5\53\07\9c\c4\ff\7e\02\70\d4\58\95\15\33\45\8a\01\d1\60\b2\2d\59\a8\bd\9a\b5";
let proof1 : Blob = "\b0\c2\9b\d1\e9\de\b5\e1\58\29\0d\ca\42\b9\0d\40\ef\8a\5a\9e\b9\5f\f2\a6\71\91\5f\91\69\53\3f\26\a6\48\5d\61\aa\82\ed\78\06\71\05\14\ca\d6\6e\45\0a\8a\b9\a4\83\a4\61\9d\6e\c2\54\ef\c8\42\f2\1b\ee\47\80\e6\1f\48\74\d0\a6\ee\e2\5a\ec\30\10\66\0e\7e\ad\78\0c\12\42\d1\9e\4f\10\2e\82\52\97\a3";
let nonadjacentSignature : Blob = "\94\8f\5a\4b\16\92\11\11\bc\6e\04\82\30\93\2f\60\0e\5e\cd\44\b5\41\54\b7\36\7a\5b\8d\0e\8b\29\ab\d3\f5\1e\38\e9\28\ca\a9\bf\5e\c2\be\eb\b7\c9\8d\12\20\25\b4\d2\5a\80\51\ea\fc\e8\84\35\87\35\c1\6b\70\af\89\8f\34\84\0a\7d\03\68\1b\0c\31\7a\a0\b5\0a\e3\b0\00\a6\a0\bf\84\a9\b1\b0\2d\82\2f\2e";
let distinctMessageSignature : Blob = "\8f\15\1e\7d\32\7e\0d\a0\c8\8b\69\32\4c\27\a7\a9\18\5a\bd\e8\a7\e4\d6\94\1c\4f\a2\a8\b2\d0\52\36\d3\e8\b2\b2\a2\1c\ea\b3\0f\30\c9\5a\4f\19\61\23\13\a4\91\76\d7\c1\c4\f9\f5\44\7a\0b\35\54\9a\e0\71\97\3e\a1\1a\38\b3\51\e8\35\07\f2\82\e8\93\24\19\54\00\46\33\ac\e0\63\6d\1c\ad\c0\68\f0\30\f8";
let sameMessageSignature : Blob = "\a0\e3\da\b2\9b\14\a4\f3\f2\c4\fb\bd\84\68\b5\69\61\d4\59\2e\c2\44\15\b9\18\4a\3b\9f\67\94\36\5e\f2\cf\83\5f\09\ab\0f\b4\b8\43\04\d4\95\1f\6d\d6\09\9e\9c\31\94\09\23\13\01\b4\ce\2d\58\7a\4d\c2\39\98\bc\e5\a4\22\7b\cd\9d\d2\4b\03\7e\ca\e9\59\98\4c\82\b6\67\a1\35\2a\3a\2e\42\2e\7b\10\cb\84";
let mixedSignature : Blob = "\95\25\db\26\19\2d\c4\be\4b\15\33\d0\2d\a9\c7\9a\0f\ec\5f\02\43\74\ec\70\86\f5\4b\80\e2\8f\20\da\32\a7\b4\3b\dc\93\f1\c0\d0\02\3d\a4\ec\fb\4e\c7\0e\5d\40\96\a6\ef\3a\c8\d8\2d\39\66\c2\4a\0c\08\e6\c7\26\ad\99\80\1a\79\5b\7a\80\88\9d\e3\e5\fe\89\45\83\02\84\3e\2e\57\1d\20\05\8c\e6\c8\32\30";
let emptyMessageSignature : Blob = "\a1\bd\78\5b\39\4d\05\56\4a\b6\8a\23\75\97\e0\b7\46\be\ea\35\d6\96\f7\73\ec\b7\b6\c0\fb\25\0a\3f\f1\ad\f0\01\f4\d7\17\16\45\e9\f9\74\e6\4d\07\e0\04\32\dd\34\0e\c5\29\31\cd\17\58\af\ea\ae\77\50\2d\5f\f1\14\bd\4d\5d\84\08\2b\de\9b\4d\4f\67\3d\a7\99\31\a6\b8\a9\cc\51\c1\f9\52\37\57\f9\7c\b9";
let fastSignature : Blob = "\b2\9b\60\d7\13\84\97\37\c3\d3\6c\26\a8\f9\c4\32\b4\c2\7f\9e\eb\3b\5d\03\38\77\26\75\45\ff\2f\bc\27\2b\6c\50\3e\ff\5a\5e\99\e7\8d\4a\40\83\60\16\02\c3\a8\54\f2\87\c9\55\5e\98\05\cb\2f\76\17\c4\e0\1d\ca\8f\ab\22\8a\42\96\05\27\98\d5\ee\c1\5e\34\ab\44\dc\43\3b\63\af\bf\d5\b6\1e\56\23\3a\a0";
let invalidPoint : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
let wrongDomainProof : Blob = "\b4\a0\b5\cc\3b\57\ec\e0\37\a5\96\09\87\1b\2a\91\f7\35\08\d3\9b\22\6a\a1\c6\27\f6\9c\33\ff\c0\84\f1\83\b7\cf\82\e8\31\a8\2f\1a\e1\a7\bc\5d\9e\04\04\18\ad\30\80\a5\60\6e\dd\2e\c9\c1\48\90\39\7d\08\11\63\e4\49\3f\2f\03\90\09\de\6f\a0\38\59\ee\1a\2a\23\58\8b\64\6d\6b\fd\a4\38\2f\79\58\d6\87";
let negativeKey : Blob = "\ac\e3\b5\7b\79\17\98\43\3f\d3\23\75\34\89\ca\c9\bc\a4\3b\98\de\aa\fa\ed\91\f4\cb\01\07\30\ae\1e\38\b1\86\cc\d3\7a\09\b8\ae\d6\2c\e2\3b\69\9c\48";
let negativeProof : Blob = "\80\9f\2a\46\3b\96\78\98\4c\44\47\aa\12\b9\4d\25\f1\0d\1b\66\2f\6f\8e\68\a0\0e\83\40\93\d0\52\19\c5\72\32\f3\89\cf\f4\74\06\90\b4\82\02\12\f7\b0\07\b6\27\47\bc\16\9c\fe\01\4c\47\eb\90\d6\bd\1e\3a\c6\eb\8a\2a\b3\88\ab\d7\9b\25\32\64\3c\1e\4e\4d\49\fe\63\5e\97\f6\e9\bb\db\75\2d\00\a6\96\da";
let signature1 : Blob = "\b4\8f\9c\90\7b\b9\99\4d\84\06\de\fa\f8\44\c8\fc\96\5e\12\ab\67\0d\34\ef\90\80\79\43\05\7e\37\73\9e\8d\8b\20\d3\c3\1b\47\e3\82\0f\1e\52\75\fd\b4\01\85\4b\2d\27\3a\c5\85\c0\82\28\49\50\4d\bd\2c\04\9f\27\89\ee\c4\6d\61\46\bb\28\82\58\3e\d5\c2\04\7e\11\be\fa\32\78\5f\88\01\15\d3\db\53\ad\5e";

// The quadratic small-batch path and merge-sort path must agree on exact bytes.
for (n in [15,16,17,127].values()) {
  for (mixedSizes in [false,true].values()) {
    let messages = Prim.Array_tabulate<Blob>(n,func(i) {
      let length = if (mixedSizes) i + 1 else 32;
      Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(length,func(j) {
        if (j + 1 == length) Prim.natToNat8(i) else 0
      }))
    });
    let keys = repeat<Blob>(n, "");
    // A malformed signature reaches decoding only when messages are distinct.
    assert B.aggregateVerifyIC(keys,messages,"") == #err(#invalidLength);
    assert B.aggregateVerifyIC(keys,Prim.Array_tabulate<Blob>(n,func(i){messages[n-1-i]}),"") == #err(#invalidLength);
    // Early-prefix, split-prefix, interior, and final duplicates precede crypto.
    for ((a,b) in [(0,1),(0,8),(7,8),(8,n-1),(n/2,n-1)].values()) {
      let duplicate = Prim.Array_tabulate<Blob>(n,func(i){if(i==b)messages[a] else messages[i]});
      assert B.aggregateVerifyIC(keys,duplicate,"") == #err(#duplicateMessage);
    };
  };
};
assert B.aggregateVerifyIC(repeat<Blob>(17,""),repeat<Blob>(17,""),"") == #err(#duplicateMessage);
assert B.aggregateVerifyIC([], ["",""], "") == #err(#invalidLength);
assert B.aggregateVerifyIC(repeat<Blob>(128,""),repeat<Blob>(128,""),"") == #err(#tooManyItems);

// Exact repeated pairs and messages, including nonadjacent pairs and empty messages.
assert B.aggregateVerifyEthereum([key0,key0],[proof0,proof0],["alpha","alpha"],repeatedSignature) == #ok(true);
assert B.aggregateVerifyEthereum([key0,key0],[proof0,proof0],["alpha","alpha"],signature0) == #ok(false);
assert B.aggregateVerifyEthereum([key0,key1,key0],[proof0,proof1,proof0],["alpha","beta","alpha"],nonadjacentSignature) == #ok(true);
assert B.aggregateVerifyEthereum([key0,key0],[proof0,proof0],["alpha","beta"],distinctMessageSignature) == #ok(true);
assert B.aggregateVerifyEthereum([key0,key1],[proof0,proof1],["alpha","alpha"],sameMessageSignature) == #ok(true);
assert B.aggregateVerifyEthereum([key0,key1,key0,key1],[proof0,proof1,proof0,proof1],["alpha","beta","beta","alpha"],mixedSignature) == #ok(true);
assert B.aggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,proof0],["","","alpha"],emptyMessageSignature) == #ok(true);
assert B.fastAggregateVerifyEthereum([key0,key1,key0],[proof0,proof1,proof0],"alpha",fastSignature) == #ok(true);
// A different proof on a cached key must be checked; malformed inputs keep their errors.
assert B.aggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,proof1],["alpha","alpha","alpha"],signature0) == #err(#invalidProof);
assert B.fastAggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,proof1],"alpha",signature0) == #err(#invalidProof);
assert B.aggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,""],["alpha","alpha","alpha"],signature0) == #err(#invalidLength);
assert B.fastAggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,""],"alpha",signature0) == #err(#invalidLength);
assert B.aggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,B.g2Identity],["alpha","alpha","alpha"],signature0) == #err(#identity);
assert B.fastAggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,B.g2Identity],"alpha",signature0) == #err(#identity);
assert B.aggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,invalidPoint],["alpha","alpha","alpha"],signature0) == #err(#invalidPoint);
assert B.fastAggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,invalidPoint],"alpha",signature0) == #err(#invalidPoint);
assert B.aggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,wrongDomainProof],["alpha","alpha","alpha"],signature0) == #err(#invalidProof);
assert B.fastAggregateVerifyEthereum([key0,key0,key0],[proof0,proof0,wrongDomainProof],"alpha",signature0) == #err(#invalidProof);
// A cached proof cannot validate another key; the first failing entry wins.
assert B.aggregateVerifyEthereum([key0,key1],[proof0,proof0],["alpha","alpha"],signature0) == #err(#invalidProof);
assert B.aggregateVerifyEthereum([key0,key0],[proof1,proof0],["alpha","alpha"],signature0) == #err(#invalidProof);
// General verification checks signatures before PoPs; fast verification checks PoPs first.
assert B.aggregateVerifyEthereum([key0],[proof1],["alpha"],"") == #err(#invalidLength);
assert B.fastAggregateVerifyEthereum([key0],[proof1],"alpha","") == #err(#invalidProof);
assert B.aggregateVerifyEthereum([key0],[proof1],["alpha"],B.g2Identity) == #err(#identity);
assert B.fastAggregateVerifyEthereum([key0],[proof1],"alpha",B.g2Identity) == #err(#invalidProof);
// A same-message key sum may be identity: neutral in general aggregation, rejected by fast verification.
assert B.aggregateVerifyEthereum([key0,negativeKey,key1],[proof0,negativeProof,proof1],["alpha","alpha","beta"],signature1) == #ok(true);
assert B.aggregateVerifyEthereum([key0,negativeKey],[proof0,negativeProof],["alpha","alpha"],signature0) == #ok(false);
assert B.fastAggregateVerifyEthereum([key0,negativeKey],[proof0,negativeProof],"alpha",signature0) == #err(#identity);
assert B.fastAggregateVerifyEthereum([key0,negativeKey],[proof0,negativeProof],"alpha","") == #err(#invalidLength);
// Batch limits and matching lengths are checked before any cached work.
assert B.aggregateVerifyEthereum(repeat<Blob>(128,key0),repeat<Blob>(128,proof0),repeat<Blob>(128,"alpha"),"") == #err(#tooManyItems);
assert B.fastAggregateVerifyEthereum(repeat<Blob>(129,key0),repeat<Blob>(129,proof0),"alpha","") == #err(#tooManyItems);
assert B.aggregateVerifyEthereum([key0],[],["alpha"],signature0) == #err(#invalidLength);
assert B.fastAggregateVerifyEthereum([key0],[],"alpha",signature0) == #err(#invalidLength);
