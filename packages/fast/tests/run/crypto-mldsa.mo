//MOC-FLAG --package fast ../../src --package core ../../.mops/core@2.5.0/src --plugin ../../../../dist/ml-dsa --sanity-checks
import MLDSA "mo:fast/MLDSA";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Vectors "../../../../plugins/ml-dsa/tests/Vectors";

func filled(size : Nat, byte : Nat8) : Blob {
  Blob.fromArray(Array.tabulate<Nat8>(size, func _ { byte }))
};
let deterministic = Vectors.sigGen[0];
let randomized = Vectors.sigGen[5];
assert MLDSA.publicKey(Vectors.keyGen[0].seed) == #ok(Vectors.keyGen[0].publicKey);
assert MLDSA.sign(deterministic.seed, deterministic.message, deterministic.context) == #ok(deterministic.signature);
assert MLDSA.signRandomized(randomized.seed, randomized.message, randomized.context, randomized.randomness) == #ok(randomized.signature);
assert MLDSA.verify(deterministic.publicKey, deterministic.message, deterministic.signature, deterministic.context) == #ok(true);
assert MLDSA.verify(randomized.publicKey, randomized.message, randomized.signature, randomized.context) == #ok(true);
let negative = Vectors.sigVer[8]; // NIST malformed-hint signature.
assert not negative.valid;
assert MLDSA.verify(negative.publicKey, negative.message, negative.signature, negative.context) == #ok(false);
assert MLDSA.verify(deterministic.publicKey, deterministic.message, deterministic.signature, "wrong context") == #ok(false);
assert MLDSA.publicKey("") == #err(#invalidSecretKey);
assert MLDSA.sign("", "", "") == #err(#invalidSecretKey);
assert MLDSA.sign(deterministic.seed, "", filled(256, 0)) == #err(#invalidContext);
assert MLDSA.signRandomized(deterministic.seed, "", "", "") == #err(#invalidRandomness);
assert MLDSA.verify("", "", "", "") == #err(#invalidPublicKey);
assert MLDSA.verify(deterministic.publicKey, "", "", "") == #err(#invalidSignature);
assert MLDSA.verify(deterministic.publicKey, "", deterministic.signature, filled(256, 0)) == #err(#invalidContext);
let saved = MLDSA.sign(deterministic.seed, deterministic.message, deterministic.context);
let derive = MLDSA.publicKey;
assert derive(deterministic.seed) == #ok(deterministic.publicKey);
let signer = MLDSA.sign;
assert signer(deterministic.seed, deterministic.message, deterministic.context) == saved;
assert saved == #ok(deterministic.signature);
