//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa --sanity-checks
import RSA "mo:fast/RSA";
import F "../fixtures/RSA";
import V "../fixtures/RSARound5";
import Prim "mo:⛔";

func unwrap<T>(r : RSA.Result<T>) : T {
  switch r { case (#ok x) x; case (#err _) Prim.trap("RSA preparation failed") }
};
func bytes(length : Nat, value : Nat8) : Blob {
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(length, func _ { value }))
};
let preparedPublic = unwrap(RSA.preparePublicKey(F.publicKey));
let preparedSecret = unwrap(RSA.prepareSecretKey(F.privateKey));
let saltAndMessage = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(32, func i { Prim.natToNat8(i) }));
let saltAndDigest = bytes(32, 255);
let longMessage = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(8193, func i { Prim.natToNat8((i * 71 + 193) % 256) }));
// Identical Blob values fill multiple public arguments, including a key as message.
let messages : [Blob] = [F.privateKey, saltAndMessage, saltAndDigest, longMessage];
let salts : [Blob] = [V.keySalt, saltAndMessage, saltAndDigest, bytes(32, 0)];
for (i in [0, 1, 3].values()) {
  let expected = #ok(V.signatures[i]);
  assert RSA.sign(F.privateKey, messages[i], salts[i]) == expected;
  assert RSA.signPrepared(preparedSecret, messages[i], salts[i]) == expected;
  assert RSA.verify(F.publicKey, messages[i], V.signatures[i]) == #ok true;
  assert RSA.verifyPrepared(preparedPublic, messages[i], V.signatures[i]) == #ok true;
};
assert RSA.signPrehash(F.privateKey, saltAndDigest, saltAndDigest) == #ok(V.signatures[2]);
assert RSA.signPrehashPrepared(preparedSecret, saltAndDigest, saltAndDigest) == #ok(V.signatures[2]);
assert RSA.verifyPrehash(F.publicKey, saltAndDigest, V.signatures[2]) == #ok true;
assert RSA.verifyPrehashPrepared(preparedPublic, saltAndDigest, V.signatures[2]) == #ok true;
// Prehash consumes exactly these bytes, not their hash, and signatures may alias messages.
assert RSA.verify(F.publicKey, saltAndDigest, V.signatures[2]) == #ok false;
assert RSA.verifyPrepared(preparedPublic, V.signatures[2], V.signatures[2]) == #ok false;
assert RSA.verify(F.publicKey, F.publicKey, F.publicKey) == #err(#invalidSignature);
for (signature in V.malformed.values()) {
  assert RSA.verifyPrehash(F.publicKey, V.boundaryDigest, signature) == #ok false;
  assert RSA.verifyPrehashPrepared(preparedPublic, V.boundaryDigest, signature) == #ok false;
};
// Short and long invalid lengths; digest errors precede salt/signature errors.
for (length in [0, 1, 31, 33, 64, 384].values()) {
  let invalid = bytes(length, 0);
  assert RSA.signPrehash(F.privateKey, invalid, invalid) == #err(#invalidDigest);
  assert RSA.signPrehashPrepared(preparedSecret, invalid, invalid) == #err(#invalidDigest);
  assert RSA.verifyPrehash(F.publicKey, invalid, invalid) == #err(#invalidDigest);
  assert RSA.verifyPrehashPrepared(preparedPublic, invalid, invalid) == #err(#invalidDigest);
  assert RSA.sign(F.privateKey, "", invalid) == #err(#invalidSalt);
  assert RSA.signPrepared(preparedSecret, "", invalid) == #err(#invalidSalt);
  assert RSA.signPrehash(F.privateKey, saltAndDigest, invalid) == #err(#invalidSalt);
  assert RSA.signPrehashPrepared(preparedSecret, saltAndDigest, invalid) == #err(#invalidSalt);
};
