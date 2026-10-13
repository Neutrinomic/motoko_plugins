//MOC-FLAG --package fast ../../src --package core ../../.mops/core@2.5.0/src --plugin ../../../../dist/ml-dsa --sanity-checks
import MLDSA "mo:fast/MLDSA";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Prim "mo:⛔";
import Vectors "../../../../plugins/ml-dsa/tests/Vectors";

func unwrap<T>(result : MLDSA.Result<T>) : T {
  switch result { case (#ok value) value; case (#err _) Prim.trap("unexpected prepared MLDSA error") }
};
func filled(size : Nat, byte : Nat8) : Blob {
  Blob.fromArray(Array.tabulate<Nat8>(size, func _ { byte }))
};
let first = Vectors.sigGen[0];
let second = Vectors.sigGen[5];
let publicA = unwrap(MLDSA.preparePublicKey(first.publicKey));
let secretA = unwrap(MLDSA.prepareSecretKey(first.seed));
let publicB = unwrap(MLDSA.preparePublicKey(second.publicKey));
let secretB = unwrap(MLDSA.prepareSecretKey(second.seed));
let signer = MLDSA.signPrepared;
let randomizedSigner = MLDSA.signRandomizedPrepared;
let verify = MLDSA.verifyPrepared;
let saved = signer(secretA, first.message, first.context);
assert saved == #ok(first.signature);
assert randomizedSigner(secretB, second.message, second.context, second.randomness) == #ok(second.signature);
assert verify(publicA, first.message, first.signature, first.context) == #ok(true);
assert verify(publicB, second.message, second.signature, second.context) == #ok(true);
assert verify(publicB, first.message, first.signature, first.context) == #ok(false);
assert verify(publicA, first.message, first.signature, "wrong context") == #ok(false);
assert signer(secretA, first.message, first.context) == saved;
assert randomizedSigner(secretA, first.message, first.context, filled(32, 0)) == saved;
assert MLDSA.sign(first.seed, first.message, first.context) == saved;
let invalid = Vectors.sigVer[8];
let invalidKey = unwrap(MLDSA.preparePublicKey(invalid.publicKey));
assert verify(invalidKey, invalid.message, invalid.signature, invalid.context) == #ok(false);
let longContext = filled(256, 0);
assert signer(secretA, "", longContext) == #err(#invalidContext);
assert randomizedSigner(secretA, "", longContext, "") == #err(#invalidContext);
assert randomizedSigner(secretA, "", "", "") == #err(#invalidRandomness);
assert verify(publicA, "", "", longContext) == #err(#invalidSignature);
assert verify(publicA, "", first.signature, longContext) == #err(#invalidContext);
switch (MLDSA.prepareSecretKey("")) { case (#err(#invalidSecretKey)) {}; case _ assert false };
switch (MLDSA.preparePublicKey("")) { case (#err(#invalidPublicKey)) {}; case _ assert false };
assert saved == #ok(first.signature);
