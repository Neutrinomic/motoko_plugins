//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa --sanity-checks
import RSA "mo:fast/RSA";
import F "../fixtures/RSA";
import Prim "mo:⛔";

func unwrap<T>(result : RSA.Result<T>) : T {
  switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected RSA error") }
};
func expectError<T>(result : RSA.Result<T>, expected : RSA.Error) {
  switch result { case (#err error) assert error == expected; case (#ok _) assert false }
};

let publicKey : RSA.PreparedPublicKey = unwrap(RSA.preparePublicKey(F.publicKey));
let secretKey : RSA.PreparedSecretKey = unwrap(RSA.prepareSecretKey(F.privateKey));
assert RSA.verifyPrepared(publicKey, F.message, F.signature) == #ok true;
assert RSA.verifyPrehashPrepared(publicKey, F.digest, F.signature) == #ok true;
assert RSA.signPrepared(secretKey, F.message, F.salt) == #ok(F.signature);
assert RSA.signPrehashPrepared(secretKey, F.digest, F.salt) == #ok(F.signature);
assert RSA.verifyPrepared(publicKey, "wrong", F.signature) == #ok false;
assert RSA.verifyPrehashPrepared(publicKey, F.digest, F.zeros(384)) == #ok false;
expectError(RSA.preparePublicKey(""), #invalidPublicKey);
expectError(RSA.prepareSecretKey(""), #invalidSecretKey);
assert RSA.verifyPrehashPrepared(publicKey, "", "") == #err(#invalidDigest);
assert RSA.verifyPrehashPrepared(publicKey, F.digest, "") == #err(#invalidSignature);
assert RSA.signPrehashPrepared(secretKey, "", "") == #err(#invalidDigest);
assert RSA.signPrehashPrepared(secretKey, F.digest, "") == #err(#invalidSalt);
assert RSA.signPrepared(secretKey, F.message, "") == #err(#invalidSalt);

let prepare = RSA.preparePublicKey;
let alias = unwrap(prepare(F.publicKey));
func verify(key : RSA.PreparedPublicKey, digest : Blob, signature : Blob) : RSA.Result<Bool> {
  RSA.verifyPrehashPrepared(key, digest, signature)
};
let callbacks : [(RSA.PreparedPublicKey, Blob, Blob) -> RSA.Result<Bool>] = [verify];
assert callbacks[0](alias, F.digest, F.signature) == #ok true;
assert RSA.verifyPrehash(F.publicKey, F.digest, F.signature) == #ok true;
