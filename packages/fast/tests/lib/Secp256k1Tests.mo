import Prim "mo:⛔";
import Secp "mo:fast/Secp256k1";
import Array "mo:core/Array";
import Blob "mo:core/Blob";

// Fixed answers are independent of the plugin. Sources and reproduction commands:
// ../ash/coverage/Secp256k1.md
module {
  func ok<T>(result : Secp.Result<T>) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected secp256k1 error") }
  };
  func err<T>(result : Secp.Result<T>, expected : Secp.Error) {
    switch result { case (#err actual) assert actual == expected; case (#ok _) assert false }
  };
  func join(a : Blob, b : Blob) : Blob = Prim.arrayToBlob(a.toArray().concat(b.toArray()));
  func zeros(size : Nat) : Blob = Prim.arrayToBlob(Array.repeat<Nat8>(0, size));
  let zero : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
  let one : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
  let two : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02";
  let three : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03";
  let six : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06";
  let order : Blob = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\41";
  let minusOne : Blob = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\40";
  let field : Blob = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ff\ff\fc\2f";
  let generator : Blob = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98";
  let generatorUncompressed : Blob = "\04\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98\48\3a\da\77\26\a3\c4\65\5d\a4\fb\fc\0e\11\08\a8\fd\17\b4\48\a6\85\54\19\9c\47\d0\8f\fb\10\d4\b8";
  let negativeGenerator : Blob = "\03\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98";
  let generatorX : Blob = "\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98";
  let twice : Blob = "\02\c6\04\7f\94\41\ed\7d\6d\30\45\40\6e\95\c0\7c\d8\5c\77\8e\4b\8c\ef\3c\a7\ab\ac\09\b9\5c\70\9e\e5";
  let triple : Blob = "\02\f9\30\8a\01\92\58\c3\10\49\34\4f\85\f8\9d\52\29\b5\31\c8\45\83\6f\99\b0\86\01\f1\13\bc\e0\36\f9";
  let sixfold : Blob = "\03\ff\f9\7b\d5\75\5e\ee\a4\20\45\3a\14\35\52\35\d3\82\f6\47\2f\85\68\a1\8b\2f\05\7a\14\60\29\75\56";

  public func pointVectors() {
    // Standards for Efficient Cryptography 2 (SEC 2), section 2.4.1.
    assert ok(Secp.derivePublicKey(one)) == generator;
    assert ok(Secp.publicKey(one, true)) == generator;
    assert ok(Secp.publicKey(one, false)) == generatorUncompressed;
    assert ok(Secp.convertPublicKey(generator, false)) == generatorUncompressed;
    assert ok(Secp.convertPublicKey(generatorUncompressed, true)) == generator;
    assert ok(Secp.convertPublicKey(generator, true)) == generator;
    assert ok(Secp.convertPublicKey(generatorUncompressed, false)) == generatorUncompressed;
    assert ok(Secp.compressPublicKey(generatorUncompressed)) == generator;
    assert ok(Secp.decompressPublicKey(generator)) == generatorUncompressed;
    assert ok(Secp.baseMultiply(one)) == generator;
    assert ok(Secp.baseMultiply(two)) == twice;
    assert ok(Secp.baseMultiply(six)) == sixfold;
    assert ok(Secp.derivePublicKey(minusOne)) == negativeGenerator;
    assert ok(Secp.pointAdd(generator, generator)) == twice;
    assert ok(Secp.pointAdd(generatorUncompressed, twice)) == triple;
    assert ok(Secp.pointMultiply(generator, three)) == triple;
    assert ok(Secp.pointMultiply(twice, three)) == sixfold;
    assert ok(Secp.pointMultiply(generatorUncompressed, one)) == generator;
    assert ok(Secp.tweakPublicKey(generator, zero)) == generator;
    assert ok(Secp.tweakPublicKey(generator, one)) == twice;
    assert ok(Secp.tweakPublicKey(generatorUncompressed, two)) == triple;
    assert ok(Secp.xOnlyPublicKey(generator)) == generatorX;
    assert ok(Secp.xOnlyPublicKey(negativeGenerator)) == generatorX;
    assert ok(Secp.xOnlyPublicKey(generatorUncompressed)) == generatorX;
    assert ok(Secp.tweakXOnlyPublicKey(generatorX, zero)) == generator;
    assert ok(Secp.tweakXOnlyPublicKey(generatorX, one)) == twice;
    // The parity byte is significant: 6G has odd Y, unlike 3G.
    assert ok(Secp.tweakXOnlyPublicKey(ok(Secp.xOnlyPublicKey(triple)), three)) == sixfold;

    // BIP341 secret tweaking normalizes the INPUT point to even Y before
    // scalar addition, while preserving the parity of the resulting point.
    // Seven scalar/parity boundaries plus all seven official wallet vectors.
    let secretTweaks : [(Blob, Blob, Blob)] = [
      ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"),
      ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03"),
      ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01", "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\3f", "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\40"),
      ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\3b"),
      ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01", "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\3c"),
      ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\06", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\07", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"),
      ("\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\40", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"),
      ("\6b\97\3d\88\83\8f\27\36\6e\d6\1c\9a\d6\36\76\63\04\5c\b4\56\e2\83\35\c1\09\e3\07\17\ae\0c\6b\aa", "\b8\6e\7b\e8\f3\9b\ab\32\a6\f2\c0\44\3a\bb\c2\10\f0\ed\ac\0e\2c\53\d5\01\b3\6b\64\43\7d\9c\6c\70", "\24\05\b9\71\77\2a\d2\69\15\c8\dc\df\10\f2\38\75\3a\9b\83\7e\5f\8e\6a\86\fd\7c\0c\ce\5b\72\96\d9"),
      ("\1e\4d\a4\9f\6a\af\4e\5c\d1\75\fe\08\a3\2b\b5\cb\48\63\d9\63\92\12\55\f3\3d\3b\c3\1e\13\43\90\7f", "\cb\d8\67\9b\a6\36\c1\11\0e\a2\47\54\2c\fb\d9\64\13\1a\6b\e8\4f\87\3f\7f\3b\62\a7\77\52\8e\d0\01", "\ea\26\0c\3b\10\e6\0f\6d\e0\18\45\5c\d0\27\8f\2f\5b\7e\45\4b\e1\99\95\72\78\9e\6a\95\65\d2\60\80"),
      ("\d3\c7\af\07\da\2d\54\f7\a7\73\5d\3d\0f\c4\f0\a7\31\64\db\63\8b\2f\2f\7c\43\f7\11\f6\d4\aa\7e\64", "\6a\f9\e2\8d\bf\9d\6a\af\02\76\96\e2\59\8a\5b\3d\05\6f\5f\d2\35\5a\7f\d5\a3\7a\0e\50\08\13\2d\30", "\97\32\33\85\e5\70\15\b7\5b\03\39\a5\49\c5\6a\94\8e\b9\61\55\59\73\f0\95\1f\55\5a\e6\03\9e\f0\0d"),
      ("\f3\6b\b0\7a\11\e4\69\ce\94\1d\16\b6\3b\11\b9\b9\12\0a\84\d9\d8\7c\ff\2c\84\a8\d4\af\fb\43\8f\4e", "\b5\7b\fa\18\3d\28\ee\b6\ad\68\8d\da\ab\b2\65\b4\a4\1f\bf\68\e5\fe\d2\c7\2c\74\de\70\d5\a7\86\f4", "\a8\e7\aa\92\4f\0d\58\85\41\85\a4\90\e6\c4\1f\6e\fb\7b\67\5c\0f\33\31\b7\f1\4b\54\94\00\b4\d5\01"),
      ("\41\5c\fe\9c\15\d9\ce\a2\7d\81\04\d5\51\7c\06\e9\de\48\e2\f9\86\b6\95\e4\f5\ff\eb\f2\30\e7\25\d8", "\65\79\13\8e\79\76\dc\13\b6\a9\2f\7b\fd\5a\2f\c7\68\4f\5e\a4\24\19\d4\33\68\30\14\70\f3\b7\4e\d9", "\24\1c\14\f2\63\9d\0d\71\39\28\2a\a6\ab\de\28\dd\8a\06\7b\aa\9d\63\3e\4e\72\30\28\7e\c2\d0\29\01"),
      ("\c7\b0\e8\1f\0a\9a\0b\04\99\e1\12\27\9d\71\8c\ca\98\e7\9a\12\e2\f1\37\c7\2a\e5\b2\13\aa\d0\d1\03", "\9e\05\17\ed\c8\25\9b\b3\35\92\55\40\0b\23\ca\95\07\f2\a9\1c\d1\e4\25\0b\a0\68\b4\ea\fc\eb\a4\a9", "\65\b6\00\0c\d2\bf\a6\b7\cf\73\67\67\a8\95\57\60\e6\2b\66\49\05\8c\bc\97\0b\7c\08\71\d7\86\34\6b"),
      ("\77\86\34\16\be\0d\06\65\e5\17\e1\c3\75\fd\6f\75\83\95\44\ec\a5\53\67\5e\f7\fd\f4\94\95\18\eb\aa", "\63\9f\02\81\b7\ac\49\e7\42\cd\25\b7\f1\88\65\76\26\da\1a\d1\69\20\90\78\e2\76\1c\ef\d9\1f\d6\5e", "\ec\18\ce\6a\f9\9f\43\81\5d\b5\43\f4\7b\8a\f5\ff\5d\f3\b2\cb\73\15\c9\55\aa\4a\86\e8\14\3d\2b\f5"),
    ];
    for ((secret, tweak, expectedSecret) in secretTweaks.values()) {
      let actual = ok(Secp.tweakXOnlySecretKey(secret, tweak));
      assert actual == expectedSecret;
      let internalX = ok(Secp.xOnlyPublicKey(ok(Secp.derivePublicKey(secret))));
      let expectedPublic = ok(Secp.tweakXOnlyPublicKey(internalX, tweak));
      assert ok(Secp.derivePublicKey(actual)) == expectedPublic;
      let signature = ok(Secp.schnorrSign(actual, "BIP341 secret tweak", zero));
      assert ok(Secp.schnorrVerify(ok(Secp.xOnlyPublicKey(expectedPublic)), "BIP341 secret tweak", signature));
    };
  };

  public func scalarAndPointErrors() {
    for (invalid in ([zero, order, field, "", zeros(31), zeros(33)] : [Blob]).values()) {
      err(Secp.derivePublicKey(invalid), #invalidSecretKey);
      err(Secp.tweakXOnlySecretKey(invalid, one), #invalidSecretKey);
      err(Secp.publicKey(invalid, false), #invalidSecretKey);
      err(Secp.signPrehash(invalid, zero), #invalidSecretKey);
      err(Secp.schnorrSign(invalid, "message", zero), #invalidSecretKey);
    };
    for (invalid in ([order, field, "", zeros(31), zeros(33)] : [Blob]).values()) {
      err(Secp.baseMultiply(invalid), #invalidScalar);
      err(Secp.pointMultiply(generator, invalid), #invalidScalar);
      err(Secp.tweakPublicKey(generator, invalid), #invalidScalar);
      err(Secp.tweakXOnlyPublicKey(generatorX, invalid), #invalidScalar);
      err(Secp.tweakXOnlySecretKey(one, invalid), #invalidScalar);
    };
    err(Secp.baseMultiply(zero), #pointAtInfinity);
    err(Secp.pointMultiply(generator, zero), #pointAtInfinity);
    err(Secp.pointAdd(generator, negativeGenerator), #pointAtInfinity);
    err(Secp.tweakPublicKey(generator, minusOne), #pointAtInfinity);
    err(Secp.tweakXOnlyPublicKey(generatorX, minusOne), #pointAtInfinity);
    err(Secp.tweakXOnlySecretKey(one, minusOne), #pointAtInfinity);
    err(Secp.tweakXOnlySecretKey(six, six), #pointAtInfinity);
    let invalidKeys : [Blob] = [
      "", "\00", generatorX, zeros(33), zeros(65),
      join("\02", zero), // x=0 is not a secp256k1 point.
      join("\02", field), // A field element must be strictly less than p.
      join("\05", generatorX), // Invalid SEC1 tag.
      join(generator, "\00"),
      join("\06", join(generatorX, "\48\3a\da\77\26\a3\c4\65\5d\a4\fb\fc\0e\11\08\a8\fd\17\b4\48\a6\85\54\19\9c\47\d0\8f\fb\10\d4\b8")), // Hybrid is not supported.
    ];
    for (invalid in invalidKeys.values()) {
      err(Secp.convertPublicKey(invalid, true), #invalidPublicKey);
      err(Secp.compressPublicKey(invalid), #invalidPublicKey);
      err(Secp.decompressPublicKey(invalid), #invalidPublicKey);
      err(Secp.xOnlyPublicKey(invalid), #invalidPublicKey);
      err(Secp.pointAdd(invalid, generator), #invalidPublicKey);
      err(Secp.pointAdd(generator, invalid), #invalidPublicKey);
      err(Secp.pointMultiply(invalid, one), #invalidPublicKey);
      err(Secp.tweakPublicKey(invalid, one), #invalidPublicKey);
    };
    for (invalid in (["", zero, field, generator] : [Blob]).values()) {
      err(Secp.tweakXOnlyPublicKey(invalid, one), #invalidPublicKey);
    };
  };

  type EcdsaVector = { secret : Blob; digest : Blob; signature : Blob; high : Blob; der : Blob; publicKey : Blob };
  let ecdsaVectors : [EcdsaVector] = [
    { secret = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; digest = "\af\2b\db\e1\aa\9b\6e\c1\e2\ad\e1\d6\94\f4\1f\c7\1a\83\1d\02\68\e9\89\15\62\11\3d\8a\62\ad\d1\bf"; signature = "\58\db\65\7b\cd\63\10\38\be\a0\7b\49\41\17\2f\01\67\ac\a9\8f\12\b5\5e\31\76\bd\1c\35\43\5d\65\01\3a\78\e7\3d\8f\f8\ab\55\4e\13\c1\0f\63\90\d8\1a\88\2f\91\94\5d\62\75\49\38\82\67\61\70\b5\3a\57"; high = "\58\db\65\7b\cd\63\10\38\be\a0\7b\49\41\17\2f\01\67\ac\a9\8f\12\b5\5e\31\76\bd\1c\35\43\5d\65\01\c5\87\18\c2\70\07\54\aa\b1\ec\3e\f0\9c\6f\27\e4\32\7f\4b\52\51\e6\2a\f2\87\4f\f7\2b\5f\81\06\ea"; der = "\30\44\02\20\58\db\65\7b\cd\63\10\38\be\a0\7b\49\41\17\2f\01\67\ac\a9\8f\12\b5\5e\31\76\bd\1c\35\43\5d\65\01\02\20\3a\78\e7\3d\8f\f8\ab\55\4e\13\c1\0f\63\90\d8\1a\88\2f\91\94\5d\62\75\49\38\82\67\61\70\b5\3a\57"; publicKey = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98" },
    { secret = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; digest = "\9f\86\d0\81\88\4c\7d\65\9a\2f\ea\a0\c5\5a\d0\15\a3\bf\4f\1b\2b\0b\82\2c\d1\5d\6c\15\b0\f0\0a\08"; signature = "\98\df\3a\ae\d1\8d\12\99\10\9e\97\32\e3\01\5f\7e\68\e5\d1\fd\ea\d6\92\48\09\b4\10\d9\70\a3\b0\ce\3e\f1\59\87\c6\59\23\79\ba\ad\63\92\58\6a\38\2d\63\95\25\72\63\2f\cd\95\1a\e7\5e\74\71\c1\44\c6"; high = "\98\df\3a\ae\d1\8d\12\99\10\9e\97\32\e3\01\5f\7e\68\e5\d1\fd\ea\d6\92\48\09\b4\10\d9\70\a3\b0\ce\c1\0e\a6\78\39\a6\dc\86\45\52\9c\6d\a7\95\c7\d1\57\19\b7\74\4c\18\d2\a6\a4\eb\00\18\5e\74\fc\7b"; der = "\30\45\02\21\00\98\df\3a\ae\d1\8d\12\99\10\9e\97\32\e3\01\5f\7e\68\e5\d1\fd\ea\d6\92\48\09\b4\10\d9\70\a3\b0\ce\02\20\3e\f1\59\87\c6\59\23\79\ba\ad\63\92\58\6a\38\2d\63\95\25\72\63\2f\cd\95\1a\e7\5e\74\71\c1\44\c6"; publicKey = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98" },
    { secret = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\02"; digest = "\af\2b\db\e1\aa\9b\6e\c1\e2\ad\e1\d6\94\f4\1f\c7\1a\83\1d\02\68\e9\89\15\62\11\3d\8a\62\ad\d1\bf"; signature = "\8a\31\1a\6f\14\74\da\7c\79\a5\e3\58\98\9c\b8\47\8d\21\6d\ce\ca\30\56\7d\f8\66\73\0b\e4\d0\d1\d0\51\c3\ab\fb\06\3e\30\42\87\39\1e\44\5e\b0\c4\4d\c5\88\d0\19\97\0b\c4\0e\25\73\69\02\a4\58\14\39"; high = "\8a\31\1a\6f\14\74\da\7c\79\a5\e3\58\98\9c\b8\47\8d\21\6d\ce\ca\30\56\7d\f8\66\73\0b\e4\d0\d1\d0\ae\3c\54\04\f9\c1\cf\bd\78\c6\e1\bb\a1\4f\3b\b0\f5\26\0c\cd\18\3c\dc\2d\9a\5e\f5\8a\2b\de\2d\08"; der = "\30\45\02\21\00\8a\31\1a\6f\14\74\da\7c\79\a5\e3\58\98\9c\b8\47\8d\21\6d\ce\ca\30\56\7d\f8\66\73\0b\e4\d0\d1\d0\02\20\51\c3\ab\fb\06\3e\30\42\87\39\1e\44\5e\b0\c4\4d\c5\88\d0\19\97\0b\c4\0e\25\73\69\02\a4\58\14\39"; publicKey = "\02\c6\04\7f\94\41\ed\7d\6d\30\45\40\6e\95\c0\7c\d8\5c\77\8e\4b\8c\ef\3c\a7\ab\ac\09\b9\5c\70\9e\e5" },
    { secret = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\40"; digest = "\93\15\34\c0\c1\45\d0\a9\96\31\a3\20\25\f2\3f\88\c6\7f\c6\b3\4a\60\8a\73\d0\41\0b\c0\4c\f7\bd\ce"; signature = "\74\95\49\e5\62\37\2b\f1\60\02\c1\28\70\25\a9\e4\3e\96\61\f7\94\9d\ee\87\7d\df\af\5b\4c\ec\46\5a\02\c6\f9\3e\fe\d7\ef\d4\9e\93\88\1e\dc\27\15\fc\ba\4e\f8\94\c2\54\5f\63\ac\5a\59\d8\93\fa\5f\80"; high = "\74\95\49\e5\62\37\2b\f1\60\02\c1\28\70\25\a9\e4\3e\96\61\f7\94\9d\ee\87\7d\df\af\5b\4c\ec\46\5a\fd\39\06\c1\01\28\10\2b\61\6c\77\e1\23\d8\ea\02\00\5f\e4\51\ec\f4\40\d8\13\78\04\b4\3c\3b\e1\c1"; der = "\30\44\02\20\74\95\49\e5\62\37\2b\f1\60\02\c1\28\70\25\a9\e4\3e\96\61\f7\94\9d\ee\87\7d\df\af\5b\4c\ec\46\5a\02\20\02\c6\f9\3e\fe\d7\ef\d4\9e\93\88\1e\dc\27\15\fc\ba\4e\f8\94\c2\54\5f\63\ac\5a\59\d8\93\fa\5f\80"; publicKey = "\03\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98" },
    { secret = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; digest = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\a0\b3\7f\8f\ba\68\3c\c6\8f\65\74\cd\43\b3\9f\03\43\a5\00\08\bf\6c\ce\a9\d1\32\31\d9\e7\e2\e1\e4\11\ed\c8\d3\07\25\42\96\26\4a\eb\fc\3d\c7\6c\d8\b6\68\37\3a\07\2f\d6\46\65\b5\00\00\e9\fc\ce\52"; high = "\a0\b3\7f\8f\ba\68\3c\c6\8f\65\74\cd\43\b3\9f\03\43\a5\00\08\bf\6c\ce\a9\d1\32\31\d9\e7\e2\e1\e4\ee\12\37\2c\f8\da\bd\69\d9\b5\14\03\c2\38\93\26\04\46\a5\ac\a8\18\c9\f5\5a\1d\5e\8b\e6\39\72\ef"; der = "\30\45\02\21\00\a0\b3\7f\8f\ba\68\3c\c6\8f\65\74\cd\43\b3\9f\03\43\a5\00\08\bf\6c\ce\a9\d1\32\31\d9\e7\e2\e1\e4\02\20\11\ed\c8\d3\07\25\42\96\26\4a\eb\fc\3d\c7\6c\d8\b6\68\37\3a\07\2f\d6\46\65\b5\00\00\e9\fc\ce\52"; publicKey = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98" },
    { secret = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\40"; signature = "\03\15\f6\88\38\86\55\53\c4\bd\6f\ab\5d\27\c7\eb\c7\2b\94\f1\e2\93\9a\4f\34\d6\95\4f\99\8e\f2\d3\24\64\db\52\70\7d\43\21\35\c4\8d\6f\37\d1\8e\e6\45\d7\a8\93\a5\50\53\50\e5\7b\04\30\00\98\eb\e9"; high = "\03\15\f6\88\38\86\55\53\c4\bd\6f\ab\5d\27\c7\eb\c7\2b\94\f1\e2\93\9a\4f\34\d6\95\4f\99\8e\f2\d3\db\9b\24\ad\8f\82\bc\de\ca\3b\72\90\c8\2e\71\18\74\d7\34\53\09\f8\4c\ea\da\57\5a\5c\cf\9d\55\58"; der = "\30\44\02\20\03\15\f6\88\38\86\55\53\c4\bd\6f\ab\5d\27\c7\eb\c7\2b\94\f1\e2\93\9a\4f\34\d6\95\4f\99\8e\f2\d3\02\20\24\64\db\52\70\7d\43\21\35\c4\8d\6f\37\d1\8e\e6\45\d7\a8\93\a5\50\53\50\e5\7b\04\30\00\98\eb\e9"; publicKey = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98" },
    { secret = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\41"; signature = "\a0\b3\7f\8f\ba\68\3c\c6\8f\65\74\cd\43\b3\9f\03\43\a5\00\08\bf\6c\ce\a9\d1\32\31\d9\e7\e2\e1\e4\11\ed\c8\d3\07\25\42\96\26\4a\eb\fc\3d\c7\6c\d8\b6\68\37\3a\07\2f\d6\46\65\b5\00\00\e9\fc\ce\52"; high = "\a0\b3\7f\8f\ba\68\3c\c6\8f\65\74\cd\43\b3\9f\03\43\a5\00\08\bf\6c\ce\a9\d1\32\31\d9\e7\e2\e1\e4\ee\12\37\2c\f8\da\bd\69\d9\b5\14\03\c2\38\93\26\04\46\a5\ac\a8\18\c9\f5\5a\1d\5e\8b\e6\39\72\ef"; der = "\30\45\02\21\00\a0\b3\7f\8f\ba\68\3c\c6\8f\65\74\cd\43\b3\9f\03\43\a5\00\08\bf\6c\ce\a9\d1\32\31\d9\e7\e2\e1\e4\02\20\11\ed\c8\d3\07\25\42\96\26\4a\eb\fc\3d\c7\6c\d8\b6\68\37\3a\07\2f\d6\46\65\b5\00\00\e9\fc\ce\52"; publicKey = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98" },
    { secret = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; digest = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\7c\b3\8c\c5\71\2e\9e\11\a7\67\61\5f\60\80\db\c1\11\c9\cd\d6\13\eb\98\99\9f\d9\2a\86\ba\fd\45\40\79\23\ca\1f\4d\03\47\1d\28\66\f7\76\ef\8a\6d\3c\ac\09\9b\42\73\31\ae\b2\45\aa\9d\af\ed\dc\f1\15"; high = "\7c\b3\8c\c5\71\2e\9e\11\a7\67\61\5f\60\80\db\c1\11\c9\cd\d6\13\eb\98\99\9f\d9\2a\86\ba\fd\45\40\86\dc\35\e0\b2\fc\b8\e2\d7\99\08\89\10\75\92\c2\0e\a5\41\a4\3c\16\f1\89\7a\27\c0\dc\e2\59\50\2c"; der = "\30\44\02\20\7c\b3\8c\c5\71\2e\9e\11\a7\67\61\5f\60\80\db\c1\11\c9\cd\d6\13\eb\98\99\9f\d9\2a\86\ba\fd\45\40\02\20\79\23\ca\1f\4d\03\47\1d\28\66\f7\76\ef\8a\6d\3c\ac\09\9b\42\73\31\ae\b2\45\aa\9d\af\ed\dc\f1\15"; publicKey = "\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98" },
  ];

  public func ecdsaKnownAnswers() {
    for (v in ecdsaVectors.values()) {
      assert ok(Secp.derivePublicKey(v.secret)) == v.publicKey;
      assert ok(Secp.signPrehash(v.secret, v.digest)) == v.signature;
      assert ok(Secp.signPrehash(v.secret, v.digest)) == v.signature;
      assert ok(Secp.verifyPrehash(v.publicKey, v.digest, v.signature));
      assert ok(Secp.verifyPrehash(ok(Secp.convertPublicKey(v.publicKey, false)), v.digest, v.signature));
      assert ok(Secp.verifyPrehash(v.publicKey, v.digest, v.high));
      let wrongDigest = if (v.digest == zero or v.digest == order) one else zero;
      assert not ok(Secp.verifyPrehash(v.publicKey, wrongDigest, v.signature));
      assert ok(Secp.normalizeSignature(v.signature)) == v.signature;
      assert ok(Secp.normalizeSignature(v.high)) == v.signature;
      assert ok(Secp.signatureToDer(v.signature)) == v.der;
      assert ok(Secp.signatureFromDer(v.der)) == v.signature;
      assert ok(Secp.signatureFromDer(ok(Secp.signatureToDer(v.high)))) == v.high;
    };
    assert not ok(Secp.verifyPrehash(twice, ecdsaVectors[0].digest, ecdsaVectors[0].signature));
  };

  public func ecdsaAndDerErrors() {
    let v = ecdsaVectors[0];
    for (invalid in (["", zeros(31), zeros(33)] : [Blob]).values()) {
      err(Secp.signPrehash(one, invalid), #invalidDigest);
      err(Secp.verifyPrehash(generator, invalid, v.signature), #invalidDigest);
    };
    err(Secp.verifyPrehash("", v.digest, v.signature), #invalidPublicKey);
    for (invalid in (["", zeros(63), zeros(65), zeros(64), join(zero, one), join(one, zero), join(order, one), join(one, order)] : [Blob]).values()) {
      err(Secp.verifyPrehash(generator, v.digest, invalid), #invalidSignature);
      err(Secp.signatureToDer(invalid), #invalidSignature);
      err(Secp.normalizeSignature(invalid), #invalidSignature);
    };
    let oneOne = join(one, one);
    let minimal : Blob = "\30\06\02\01\01\02\01\01";
    assert ok(Secp.signatureToDer(oneOne)) == minimal;
    assert ok(Secp.signatureFromDer(minimal)) == oneOne;
    let padded : Blob = "\30\07\02\02\00\80\02\01\01";
    assert ok(Secp.signatureToDer(join("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\80", one))) == padded;
    assert ok(Secp.signatureFromDer(padded)) == join("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\80", one);
    let badDer : [Blob] = [
      "", "\30", "\30\00", "\30\06\02\01\01\02\01",
      "\31\06\02\01\01\02\01\01", // Wrong sequence tag.
      "\30\06\03\01\01\02\01\01", // Wrong integer tag.
      "\30\06\02\01\80\02\01\01", // Negative integer.
      "\30\06\02\01\01\02\01\80",
      "\30\07\02\02\00\01\02\01\01", // Redundant leading zero.
      "\30\07\02\01\01\02\02\00\01",
      "\30\06\02\01\00\02\01\01", // Zero ECDSA r.
      "\30\06\02\01\01\02\01\00", // Zero ECDSA s.
      "\30\05\02\00\02\01\01", // Empty integer.
      "\30\81\06\02\01\01\02\01\01", // Nonminimal length.
      "\30\80\02\01\01\02\01\01\00\00", // Indefinite length.
      join(minimal, "\00"), // Trailing garbage.
      join("\30\26\02\21\00", join(order, "\02\01\01")), // r = n.
    ];
    for (invalid in badDer.values()) err(Secp.signatureFromDer(invalid), #invalidSignature);
  };

  type SchnorrVector = { secret : Blob; publicKey : Blob; auxiliary : Blob; message : Blob; signature : Blob; expected : Secp.Result<Bool> };
  // Every row in bitcoin/bips bip-0340/test-vectors.csv, indices 0 through 18.
  let schnorrVectors : [SchnorrVector] = [
    // BIP340 vector 0
    { secret = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\03"; publicKey = "\f9\30\8a\01\92\58\c3\10\49\34\4f\85\f8\9d\52\29\b5\31\c8\45\83\6f\99\b0\86\01\f1\13\bc\e0\36\f9"; auxiliary = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; message = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; signature = "\e9\07\83\1f\80\84\8d\10\69\a5\37\1b\40\24\10\36\4b\df\1c\5f\83\07\b0\08\4c\55\f1\ce\2d\ca\82\15\25\f6\6a\4a\85\ea\8b\71\e4\82\a7\4f\38\2d\2c\e5\eb\ee\e8\fd\b2\17\2f\47\7d\f4\90\0d\31\05\36\c0"; expected = #ok(true) },
    // BIP340 vector 1
    { secret = "\b7\e1\51\62\8a\ed\2a\6a\bf\71\58\80\9c\f4\f3\c7\62\e7\16\0f\38\b4\da\56\a7\84\d9\04\51\90\cf\ef"; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01"; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\68\96\bd\60\ee\ae\29\6d\b4\8a\22\9f\f7\1d\fe\07\1b\de\41\3e\6d\43\f9\17\dc\8d\cf\8c\78\de\33\41\89\06\d1\1a\c9\76\ab\cc\b2\0b\09\12\92\bf\f4\ea\89\7e\fc\b6\39\ea\87\1c\fa\95\f6\de\33\9e\4b\0a"; expected = #ok(true) },
    // BIP340 vector 2
    { secret = "\c9\0f\da\a2\21\68\c2\34\c4\c6\62\8b\80\dc\1c\d1\29\02\4e\08\8a\67\cc\74\02\0b\be\a6\3b\14\e5\c9"; publicKey = "\dd\30\8a\fe\c5\77\7e\13\12\1f\a7\2b\9c\c1\b7\cc\01\39\71\53\09\b0\86\c9\60\e1\8f\d9\69\77\4e\b8"; auxiliary = "\c8\7a\a5\38\24\b4\d7\ae\2e\b0\35\a2\b5\bb\bc\cc\08\0e\76\cd\c6\d1\69\2c\4b\0b\62\d7\98\e6\d9\06"; message = "\7e\2d\58\d8\b3\bc\df\1a\ba\de\c7\82\90\54\f9\0d\da\98\05\aa\b5\6c\77\33\30\24\b9\d0\a5\08\b7\5c"; signature = "\58\31\aa\ee\d7\b4\4b\b7\4e\5e\ab\94\ba\9d\42\94\c4\9b\cf\2a\60\72\8d\8b\4c\20\0f\50\dd\31\3c\1b\ab\74\58\79\a5\ad\95\4a\72\c4\5a\91\c3\a5\1d\3c\7a\de\a9\8d\82\f8\48\1e\0e\1e\03\67\4a\6f\3f\b7"; expected = #ok(true) },
    // BIP340 vector 3: test fails if msg is reduced modulo p or n
    { secret = "\0b\43\2b\26\77\93\73\81\ae\f0\5b\b0\2a\66\ec\d0\12\77\30\62\cf\3f\a2\54\9e\44\f5\8e\d2\40\17\10"; publicKey = "\25\d1\df\f9\51\05\f5\25\3c\40\22\f6\28\a9\96\ad\3a\0d\95\fb\f2\1d\46\8a\1b\33\f8\c1\60\d8\f5\17"; auxiliary = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; message = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"; signature = "\7e\b0\50\97\57\e2\46\f1\94\49\88\56\51\61\1c\b9\65\ec\c1\a1\87\dd\51\b6\4f\da\1e\dc\96\37\d5\ec\97\58\2b\9c\b1\3d\b3\93\37\05\b3\2b\a9\82\af\5a\f2\5f\d7\88\81\eb\b3\27\71\fc\59\22\ef\c6\6e\a3"; expected = #ok(true) },
    // BIP340 vector 4
    { secret = ""; publicKey = "\d6\9c\35\09\bb\99\e4\12\e6\8b\0f\e8\54\4e\72\83\7d\fa\30\74\6d\8b\e2\aa\65\97\5f\29\d2\2d\c7\b9"; auxiliary = ""; message = "\4d\f3\c3\f6\8f\cc\83\b2\7e\9d\42\c9\04\31\a7\24\99\f1\78\75\c8\1a\59\9b\56\6c\98\89\b9\69\67\03"; signature = "\00\00\00\00\00\00\00\00\00\00\00\3b\78\ce\56\3f\89\a0\ed\94\14\f5\aa\28\ad\0d\96\d6\79\5f\9c\63\76\af\b1\54\8a\f6\03\b3\eb\45\c9\f8\20\7d\ee\10\60\cb\71\c0\4e\80\f5\93\06\0b\07\d2\83\08\d7\f4"; expected = #ok(true) },
    // BIP340 vector 5: public key not on the curve
    { secret = ""; publicKey = "\ee\fd\ea\4c\db\67\77\50\a4\20\fe\e8\07\ea\cf\21\eb\98\98\ae\79\b9\76\87\66\e4\fa\a0\4a\2d\4a\34"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\6c\ff\5c\3b\a8\6c\69\ea\4b\73\76\f3\1a\9b\cb\4f\74\c1\97\60\89\b2\d9\96\3d\a2\e5\54\3e\17\77\69\69\e8\9b\4c\55\64\d0\03\49\10\6b\84\97\78\5d\d7\d1\d7\13\a8\ae\82\b3\2f\a7\9d\5f\7f\c4\07\d3\9b"; expected = #err(#invalidPublicKey) },
    // BIP340 vector 6: has_even_y(R) is false
    { secret = ""; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\ff\f9\7b\d5\75\5e\ee\a4\20\45\3a\14\35\52\35\d3\82\f6\47\2f\85\68\a1\8b\2f\05\7a\14\60\29\75\56\3c\c2\79\44\64\0a\c6\07\cd\10\7a\e1\09\23\d9\ef\7a\73\c6\43\e1\66\be\5e\be\af\a3\4b\1a\c5\53\e2"; expected = #ok(false) },
    // BIP340 vector 7: negated message
    { secret = ""; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\1f\a6\2e\33\1e\db\c2\1c\39\47\92\d2\ab\11\00\a7\b4\32\b0\13\df\3f\6f\f4\f9\9f\cb\33\e0\e1\51\5f\28\89\0b\3e\db\6e\71\89\b6\30\44\8b\51\5c\e4\f8\62\2a\95\4c\fe\54\57\35\aa\ea\51\34\fc\cd\b2\bd"; expected = #ok(false) },
    // BIP340 vector 8: negated s value
    { secret = ""; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\6c\ff\5c\3b\a8\6c\69\ea\4b\73\76\f3\1a\9b\cb\4f\74\c1\97\60\89\b2\d9\96\3d\a2\e5\54\3e\17\77\69\96\17\64\b3\aa\9b\2f\fc\b6\ef\94\7b\68\87\a2\26\e8\d7\c9\3e\00\c5\ed\0c\18\34\ff\0d\0c\2e\6d\a6"; expected = #ok(false) },
    // BIP340 vector 9: sG - eP is infinite. Test fails in single verification if has_even_y(inf) is defined as true and x(inf) as 0
    { secret = ""; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\12\3d\da\83\28\af\9c\23\a9\4c\1f\ee\cf\d1\23\ba\4f\b7\34\76\f0\d5\94\dc\b6\5c\64\25\bd\18\60\51"; expected = #ok(false) },
    // BIP340 vector 10: sG - eP is infinite. Test fails in single verification if has_even_y(inf) is defined as true and x(inf) as 1
    { secret = ""; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\76\15\fb\af\5a\e2\88\64\01\3c\09\97\42\de\ad\b4\db\a8\7f\11\ac\67\54\f9\37\80\d5\a1\83\7c\f1\97"; expected = #ok(false) },
    // BIP340 vector 11: sig[0:32] is not an X coordinate on the curve
    { secret = ""; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\4a\29\8d\ac\ae\57\39\5a\15\d0\79\5d\db\fd\1d\cb\56\4d\a8\2b\0f\26\9b\c7\0a\74\f8\22\04\29\ba\1d\69\e8\9b\4c\55\64\d0\03\49\10\6b\84\97\78\5d\d7\d1\d7\13\a8\ae\82\b3\2f\a7\9d\5f\7f\c4\07\d3\9b"; expected = #ok(false) },
    // BIP340 vector 12: sig[0:32] is equal to field size
    { secret = ""; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ff\ff\fc\2f\69\e8\9b\4c\55\64\d0\03\49\10\6b\84\97\78\5d\d7\d1\d7\13\a8\ae\82\b3\2f\a7\9d\5f\7f\c4\07\d3\9b"; expected = #err(#invalidSignature) },
    // BIP340 vector 13: sig[32:64] is equal to curve order
    { secret = ""; publicKey = "\df\f1\d7\7f\2a\67\1c\5f\36\18\37\26\db\23\41\be\58\fe\ae\1d\a2\de\ce\d8\43\24\0f\7b\50\2b\a6\59"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\6c\ff\5c\3b\a8\6c\69\ea\4b\73\76\f3\1a\9b\cb\4f\74\c1\97\60\89\b2\d9\96\3d\a2\e5\54\3e\17\77\69\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ba\ae\dc\e6\af\48\a0\3b\bf\d2\5e\8c\d0\36\41\41"; expected = #err(#invalidSignature) },
    // BIP340 vector 14: public key is not a valid X coordinate because it exceeds the field size
    { secret = ""; publicKey = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\fe\ff\ff\fc\30"; auxiliary = ""; message = "\24\3f\6a\88\85\a3\08\d3\13\19\8a\2e\03\70\73\44\a4\09\38\22\29\9f\31\d0\08\2e\fa\98\ec\4e\6c\89"; signature = "\6c\ff\5c\3b\a8\6c\69\ea\4b\73\76\f3\1a\9b\cb\4f\74\c1\97\60\89\b2\d9\96\3d\a2\e5\54\3e\17\77\69\69\e8\9b\4c\55\64\d0\03\49\10\6b\84\97\78\5d\d7\d1\d7\13\a8\ae\82\b3\2f\a7\9d\5f\7f\c4\07\d3\9b"; expected = #err(#invalidPublicKey) },
    // BIP340 vector 15: message of size 0 (added 2022-12)
    { secret = "\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40"; publicKey = "\77\8c\aa\53\b4\39\3a\c4\67\77\4d\09\49\7a\87\22\4b\f9\fa\b6\f6\e6\8b\23\08\64\97\32\4d\6f\d1\17"; auxiliary = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; message = ""; signature = "\71\53\5d\b1\65\ec\d9\fb\bc\04\6e\5f\fa\ea\61\18\6b\b6\ad\43\67\32\fc\cc\25\29\1a\55\89\54\64\cf\60\69\ce\26\bf\03\46\62\28\f1\9a\3a\62\db\8a\64\9f\2d\56\0f\ac\65\28\27\d1\af\05\74\e4\27\ab\63"; expected = #ok(true) },
    // BIP340 vector 16: message of size 1 (added 2022-12)
    { secret = "\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40"; publicKey = "\77\8c\aa\53\b4\39\3a\c4\67\77\4d\09\49\7a\87\22\4b\f9\fa\b6\f6\e6\8b\23\08\64\97\32\4d\6f\d1\17"; auxiliary = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; message = "\11"; signature = "\08\a2\0a\0a\fe\f6\41\24\64\92\32\e0\69\3c\58\3a\b1\b9\93\4a\e6\3b\4c\35\11\f3\ae\11\34\c6\a3\03\ea\31\73\bf\ea\66\83\bd\10\1f\a5\aa\5d\bc\19\96\fe\7c\ac\fc\5a\57\7d\33\ec\14\56\4c\ec\2b\ac\bf"; expected = #ok(true) },
    // BIP340 vector 17: message of size 17 (added 2022-12)
    { secret = "\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40"; publicKey = "\77\8c\aa\53\b4\39\3a\c4\67\77\4d\09\49\7a\87\22\4b\f9\fa\b6\f6\e6\8b\23\08\64\97\32\4d\6f\d1\17"; auxiliary = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; message = "\01\02\03\04\05\06\07\08\09\0a\0b\0c\0d\0e\0f\10\11"; signature = "\51\30\f3\9a\40\59\b4\3b\c7\ca\c0\9a\19\ec\e5\2b\5d\86\99\d1\a7\1e\3c\52\da\9a\fd\b6\b5\0a\c3\70\c4\a4\82\b7\7b\f9\60\f8\68\15\40\e2\5b\67\71\ec\e1\e5\a3\7f\d8\0e\5a\51\89\7c\55\66\a9\7e\a5\a5"; expected = #ok(true) },
    // BIP340 vector 18: message of size 100 (added 2022-12)
    { secret = "\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40\03\40"; publicKey = "\77\8c\aa\53\b4\39\3a\c4\67\77\4d\09\49\7a\87\22\4b\f9\fa\b6\f6\e6\8b\23\08\64\97\32\4d\6f\d1\17"; auxiliary = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"; message = "\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99\99"; signature = "\40\3b\12\b0\d8\55\5a\34\41\75\ea\7e\c7\46\56\63\03\32\1e\5d\bf\a8\be\6f\09\16\35\16\3e\ca\79\a8\58\5e\d3\e3\17\08\07\e7\c0\3b\72\0f\c5\4c\7b\23\89\7f\cb\a0\e9\d0\b4\a0\68\94\cf\d2\49\f2\23\67"; expected = #ok(true) },
  ];

  public func schnorrKnownAnswers() {
    for (v in schnorrVectors.values()) {
      assert Secp.schnorrVerify(v.publicKey, v.message, v.signature) == v.expected;
      if (v.secret.size() > 0) {
        assert ok(Secp.schnorrSign(v.secret, v.message, v.auxiliary)) == v.signature;
        assert ok(Secp.xOnlyPublicKey(ok(Secp.derivePublicKey(v.secret)))) == v.publicKey;
      };
    };
  };

  public func schnorrErrors() {
    let v = schnorrVectors[0];
    for (invalid in (["", zeros(31), zeros(33)] : [Blob]).values()) {
      err(Secp.schnorrSign(v.secret, v.message, invalid), #invalidAuxiliaryRandomness);
    };
    for (invalid in (["", zeros(63), zeros(65), join(field, one), join(one, order)] : [Blob]).values()) {
      err(Secp.schnorrVerify(v.publicKey, v.message, invalid), #invalidSignature);
    };
    for (invalid in (["", zero, field, generator] : [Blob]).values()) {
      err(Secp.schnorrVerify(invalid, v.message, v.signature), #invalidPublicKey);
    };
    // Unlike ECDSA, BIP340 permits scalar s=0 and r=0 in the encoding.
    // A wrong equation still returns false, not a malformed-input error.
    assert Secp.schnorrVerify(v.publicKey, v.message, zeros(64)) == #ok(false);
    assert Secp.schnorrVerify(v.publicKey, "different message", v.signature) == #ok(false);
    assert Secp.schnorrVerify(generatorX, v.message, v.signature) == #ok(false);
  };

  public func evaluationAndAliases() {
    var order = "";
    let v = ecdsaVectors[0];
    let result = (do { order #= "callee;"; Secp.signPrehash })(
      do { order #= "secret;"; v.secret },
      do { order #= "digest;"; v.digest }
    );
    assert order == "callee;secret;digest;";
    assert ok(result) == v.signature;
    order := "";
    let verified = (do { order #= "callee;"; Secp.verifyPrehash })(
      do { order #= "public;"; v.publicKey },
      do { order #= "digest;"; v.digest },
      do { order #= "signature;"; v.signature }
    );
    assert order == "callee;public;digest;signature;";
    assert ok(verified);
    order := "";
    let schnorr = schnorrVectors[0];
    let signed = (do { order #= "callee;"; Secp.schnorrSign })(
      do { order #= "secret;"; schnorr.secret },
      do { order #= "message;"; schnorr.message },
      do { order #= "auxiliary;"; schnorr.auxiliary }
    );
    assert order == "callee;secret;message;auxiliary;";
    assert ok(signed) == schnorr.signature;
    let derive = Secp.derivePublicKey;
    let operations = { derive };
    func identity<T>(value : T) : T = value;
    let aliases = [derive, identity(derive)];
    let callback : Blob -> Secp.Result<Blob> = func(secret) { Secp.derivePublicKey(secret) };
    assert ok(operations.derive(one)) == generator;
    assert ok(aliases[0](two)) == twice;
    assert ok(aliases[1](three)) == triple;
    assert ok(callback(one)) == generator;
    switch (?derive) { case (?f) assert ok(f(one)) == generator; case null assert false };
  };

  public func retainedResults() {
    let v = ecdsaVectors[0];
    let savedKey = ok(Secp.publicKey(one, false));
    let savedSignature = ok(Secp.signPrehash(one, v.digest));
    let savedDer = ok(Secp.signatureToDer(savedSignature));
    let savedSchnorr = ok(Secp.schnorrSign(schnorrVectors[0].secret, zero, zero));
    let savedTweaked = ok(Secp.tweakXOnlyPublicKey(ok(Secp.xOnlyPublicKey(triple)), three));
    var iteration = 0;
    while (iteration < 32) {
      let allocation = Prim.arrayToBlob(Array.repeat<Nat8>(255, 131_072 + iteration));
      assert ok(Secp.derivePublicKey(two)) == twice;
      assert ok(Secp.signPrehash(two, ecdsaVectors[2].digest)) == ecdsaVectors[2].signature;
      assert ok(Secp.signatureToDer(ecdsaVectors[1].signature)) == ecdsaVectors[1].der;
      assert ok(Secp.tweakPublicKey(generator, two)) == triple;
      assert savedKey == generatorUncompressed;
      assert savedSignature == v.signature;
      assert savedDer == v.der;
      assert savedSchnorr == schnorrVectors[0].signature;
      assert savedTweaked == sixfold;
      assert allocation.size() == 131_072 + iteration;
      iteration += 1;
    };
    assert v.secret == one;
    assert savedKey == generatorUncompressed;
  };
}
