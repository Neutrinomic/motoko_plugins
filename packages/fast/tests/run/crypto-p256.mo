//MOC-FLAG --package fast ../../src --package core ../../.mops/core@2.5.0/src --plugin ../../../../dist/p256 --sanity-checks
import P256 "mo:fast/P256";
import Array "mo:core/Array";
import Blob "mo:core/Blob";

// RFC 6979 A.2.5 SHA-256, loading only the P256 plugin.
  func concat(a : Blob, b : Blob) : Blob { Blob.fromArray(a.toArray().concat(b.toArray())) };
  let secret : Blob = "\c9\af\a9\d8\45\ba\75\16\6b\5c\21\57\67\b1\d6\93\4e\50\c3\db\36\e8\9b\12\7b\8a\62\2b\12\0f\67\21";
  let publicCompressed : Blob = "\03\60\fe\d4\ba\25\5a\9d\31\c9\61\eb\74\c6\35\6d\68\c0\49\b8\92\3b\61\fa\6c\e6\69\62\2e\60\f2\9f\b6";
  let publicUncompressed : Blob = "\04\60\fe\d4\ba\25\5a\9d\31\c9\61\eb\74\c6\35\6d\68\c0\49\b8\92\3b\61\fa\6c\e6\69\62\2e\60\f2\9f\b6\79\03\fe\10\08\b8\bc\99\a4\1a\e9\e9\56\28\bc\64\f2\f1\b2\0c\2d\7e\9f\51\77\a3\c2\94\d4\46\22\99";
  let sampleHash : Blob = "\af\2b\db\e1\aa\9b\6e\c1\e2\ad\e1\d6\94\f4\1f\c7\1a\83\1d\02\68\e9\89\15\62\11\3d\8a\62\ad\d1\bf";
  let testHash : Blob = "\9f\86\d0\81\88\4c\7d\65\9a\2f\ea\a0\c5\5a\d0\15\a3\bf\4f\1b\2b\0b\82\2c\d1\5d\6c\15\b0\f0\0a\08";
  let sampleSignature : Blob = "\ef\d4\8b\2a\ac\b6\a8\fd\11\40\dd\9c\d4\5e\81\d6\9d\2c\87\7b\56\aa\f9\91\c3\4d\0e\a8\4e\af\37\16\f7\cb\1c\94\2d\65\7c\41\d4\36\c7\a1\b6\e2\9f\65\f3\e9\00\db\b9\af\f4\06\4d\c4\ab\2f\84\3a\cd\a8";
  let testSignature : Blob = "\f1\ab\b0\23\51\83\51\cd\71\d8\81\56\7b\1e\a6\63\ed\3e\fc\f6\c5\13\2b\35\4f\28\d3\b0\b7\d3\83\67\01\9f\41\13\74\2a\2b\14\bd\25\92\6b\49\c6\49\15\5f\26\7e\60\d3\81\4b\4c\0c\c8\42\50\e4\6f\00\83";
  let sampleLowSignature : Blob = "\ef\d4\8b\2a\ac\b6\a8\fd\11\40\dd\9c\d4\5e\81\d6\9d\2c\87\7b\56\aa\f9\91\c3\4d\0e\a8\4e\af\37\16\08\34\e3\6a\d2\9a\83\bf\2b\c9\38\5e\49\1d\60\99\c8\fd\f9\d1\ed\67\aa\7e\a5\f5\1f\93\78\28\57\a9";
  let sampleDer : Blob = "\30\46\02\21\00\ef\d4\8b\2a\ac\b6\a8\fd\11\40\dd\9c\d4\5e\81\d6\9d\2c\87\7b\56\aa\f9\91\c3\4d\0e\a8\4e\af\37\16\02\21\00\f7\cb\1c\94\2d\65\7c\41\d4\36\c7\a1\b6\e2\9f\65\f3\e9\00\db\b9\af\f4\06\4d\c4\ab\2f\84\3a\cd\a8";
  let one : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01";
  let zero : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
  let order : Blob = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51";
  let maxScalar : Blob = "\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50";
  let allOnes : Blob = "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff";
  let generatorCompressed : Blob = "\03\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96";
  let negativeGeneratorCompressed : Blob = "\02\6b\17\d1\f2\e1\2c\42\47\f8\bc\e6\e5\63\a4\40\f2\77\03\7d\81\2d\eb\33\a0\f4\a1\39\45\d8\98\c2\96";
assert P256.publicKey(secret, true) == #ok publicCompressed;
      assert P256.derivePublicKey(secret) == #ok publicCompressed;
assert P256.publicKey(secret, false) == #ok publicUncompressed;
assert P256.convertPublicKey(publicCompressed, false) == #ok publicUncompressed;
assert P256.signPrehash(secret, sampleHash) == #ok sampleSignature;
assert P256.signPrehash(secret, testHash) == #ok testSignature;
assert P256.verifyPrehash(publicCompressed, sampleHash, sampleSignature) == #ok true;
assert P256.verifyPrehash(publicUncompressed, sampleHash, sampleLowSignature) == #ok true;
assert P256.verifyPrehash(publicCompressed, testHash, sampleSignature) == #ok false;
assert P256.signatureToDer(sampleSignature) == #ok sampleDer;
assert P256.signatureFromDer(sampleDer) == #ok sampleSignature;
assert P256.normalizeSignature(sampleSignature) == #ok sampleLowSignature;
assert P256.normalizeSignature(sampleLowSignature) == #ok sampleLowSignature;
assert P256.publicKey(zero, true) == #err(#invalidSecretKey);
assert P256.publicKey(order, true) == #err(#invalidSecretKey);
assert P256.publicKey(allOnes, true) == #err(#invalidSecretKey);
assert P256.convertPublicKey("\00", true) == #err(#invalidPublicKey);
assert P256.signPrehash(secret, "") == #err(#invalidDigest);
assert P256.verifyPrehash("", "", "") == #err(#invalidPublicKey);
assert P256.verifyPrehash(publicCompressed, "", "") == #err(#invalidDigest);
assert P256.verifyPrehash(publicCompressed, sampleHash, concat(zero, one)) == #err(#invalidSignature);
assert P256.signatureFromDer("\30\07\02\02\00\01\02\01\01") == #err(#invalidSignature);
let saved = P256.signPrehash(secret, sampleHash);
let derive = P256.publicKey;
assert derive(secret, true) == #ok publicCompressed;
func deriveWrapped(key : Blob, compressed : Bool) : P256.Result<Blob> { P256.publicKey(key, compressed) };
let wrappers : [(Blob, Bool) -> P256.Result<Blob>] = [deriveWrapped];
assert wrappers[0](one, true) == #ok generatorCompressed;
assert wrappers[0](maxScalar, true) == #ok negativeGeneratorCompressed;
assert saved == #ok sampleSignature;

// Independent RFC6979 + OpenSSL vectors. RFC6979 bits2octets reduces the
// prehash modulo n before nonce generation; digest n must sign identically to 0.
let boundaryVectors : [(Blob, Blob)] = [
  // zero
  ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", "\68\89\7a\78\df\51\05\8b\49\0c\60\12\25\1c\95\92\1a\bb\a9\6e\2e\48\8c\8c\c9\98\94\2e\44\0d\b9\b7\80\58\7f\b3\87\36\3a\1d\f2\c9\e8\3c\00\f8\ca\99\0f\c0\a5\5b\5e\47\09\46\49\9b\82\ca\3b\55\2a\87"),
  // n_minus_one
  ("\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\50", "\c6\75\c4\3e\82\9a\5e\83\8b\e6\01\45\15\bc\c7\d8\2f\b8\d3\05\3c\77\0d\32\d3\22\a9\e9\e3\55\30\e7\49\99\6e\b9\5b\9f\44\71\48\4b\96\cd\60\fe\f8\0a\14\f6\50\4e\d7\27\9e\13\34\04\a6\1e\1a\b8\ae\e5"),
  // n
  ("\ff\ff\ff\ff\00\00\00\00\ff\ff\ff\ff\ff\ff\ff\ff\bc\e6\fa\ad\a7\17\9e\84\f3\b9\ca\c2\fc\63\25\51", "\68\89\7a\78\df\51\05\8b\49\0c\60\12\25\1c\95\92\1a\bb\a9\6e\2e\48\8c\8c\c9\98\94\2e\44\0d\b9\b7\80\58\7f\b3\87\36\3a\1d\f2\c9\e8\3c\00\f8\ca\99\0f\c0\a5\5b\5e\47\09\46\49\9b\82\ca\3b\55\2a\87"),
  // all_ff
  ("\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff", "\1f\2a\db\c5\4b\88\76\4c\27\9f\68\9f\c9\50\59\59\fc\9e\73\e8\0d\c2\08\89\a4\e0\be\91\86\5d\e7\5b\9d\10\9b\65\e2\fb\fc\0a\e4\2b\a0\b2\e5\f0\36\70\cd\45\8c\ff\48\82\df\67\83\f3\d9\3d\60\7d\17\55"),
];
for ((digest, expected) in boundaryVectors.values()) {
  assert P256.signPrehash(secret, digest) == #ok expected;
  assert P256.verifyPrehash(publicCompressed, digest, expected) == #ok true;
};
assert P256.signPrehash(secret, order) == P256.signPrehash(secret, zero);
