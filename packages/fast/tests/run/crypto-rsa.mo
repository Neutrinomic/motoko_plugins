//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa --sanity-checks
import RSA "mo:fast/RSA";
import F "../fixtures/RSA";

// Independent OpenSSL answer, not a plugin-generated round trip.
assert RSA.publicKey(F.privateKey) == #ok(F.publicKey);
assert RSA.derivePublicKey(F.privateKey) == #ok(F.publicKey);
assert RSA.validatePrivateKey(F.privateKey) == #ok true;
assert RSA.validatePublicKey(F.publicKey) == #ok true;
let signature = RSA.signPrehash(F.privateKey, F.digest, F.salt);
assert signature == #ok(F.signature);
assert RSA.sign(F.privateKey, F.message, F.salt) == signature;
assert RSA.verifyPrehash(F.publicKey, F.digest, F.signature) == #ok true;
assert RSA.verify(F.publicKey, F.message, F.signature) == #ok true;
assert RSA.verify(F.publicKey, F.append(F.message, 1), F.signature) == #ok false;
assert RSA.verifyPrehash(F.publicKey, F.flip(F.digest, 0, 1), F.signature) == #ok false;
assert RSA.verifyPrehash(F.publicKey, F.digest, F.flip(F.signature, 200, 1)) == #ok false;

assert RSA.validatePrivateKey("") == #err(#invalidSecretKey);
assert RSA.validatePublicKey("") == #err(#invalidPublicKey);
assert RSA.signPrehash("", "", "") == #err(#invalidSecretKey);
assert RSA.signPrehash(F.privateKey, "", "") == #err(#invalidDigest);
assert RSA.signPrehash(F.privateKey, F.digest, "") == #err(#invalidSalt);
assert RSA.verifyPrehash("", "", "") == #err(#invalidPublicKey);
assert RSA.verifyPrehash(F.publicKey, "", "") == #err(#invalidDigest);
assert RSA.verifyPrehash(F.publicKey, F.digest, "") == #err(#invalidSignature);
assert RSA.verifyPrehash(F.publicKey, F.digest, F.publicKey) == #err(#invalidSignature);
assert RSA.verifyPrehash(F.publicKey, F.digest, F.zeros(384)) == #ok false;
for (offset in [191, 383, 575, 767, 959].values()) {
  assert RSA.validatePrivateKey(F.flip(F.privateKey, offset, 1)) == #err(#invalidSecretKey);
};

let derive = RSA.publicKey;
assert derive(F.privateKey) == #ok(F.publicKey);
func verify(key : Blob, digest : Blob, sig : Blob) : RSA.Result<Bool> {
  RSA.verifyPrehash(key, digest, sig)
};
let callbacks : [(Blob, Blob, Blob) -> RSA.Result<Bool>] = [verify];
assert callbacks[0](F.publicKey, F.digest, F.signature) == #ok true;
assert signature == #ok(F.signature);
