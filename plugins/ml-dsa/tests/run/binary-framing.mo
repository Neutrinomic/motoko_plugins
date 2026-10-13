//MOC-FLAG --package fast ../../../../packages/fast/src --plugin ../../../../dist/ml-dsa --sanity-checks
import MLDSA "mo:fast/MLDSA";
import Prim "mo:⛔";
import Vectors "../Vectors";

func unwrap<T>(result : MLDSA.Result<T>) : T {
  switch result { case (#ok value) value; case (#err _) Prim.trap("binary framing: unexpected error") }
};
func filled(size : Nat, value : Nat8) : Blob {
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func _ { value }))
};
let v = Vectors.sigGen[0];
let publicKey = unwrap(MLDSA.preparePublicKey(v.publicKey));
let secretKey = unwrap(MLDSA.prepareSecretKey(v.seed));
let zeroRandomness = filled(32, 0);

// Each pair has identical context || message bytes. The length prefix must
// distinguish them even with embedded zero and high-bit bytes in the inputs.
for ((message, context, otherMessage, otherContext) in ([
  ("b\00c", "a", "\00c", "ab"),
  ("\00\ffa", "", "a", "\00\ff"),
] : [(Blob, Blob, Blob, Blob)]).values()) {
  let signature = unwrap(MLDSA.sign(v.seed, message, context));
  assert MLDSA.signRandomized(v.seed, message, context, zeroRandomness) == #ok(signature);
  assert MLDSA.signPrepared(secretKey, message, context) == #ok(signature);
  assert MLDSA.signRandomizedPrepared(secretKey, message, context, zeroRandomness) == #ok(signature);
  assert MLDSA.verify(v.publicKey, message, signature, context) == #ok(true);
  assert MLDSA.verifyPrepared(publicKey, message, signature, context) == #ok(true);
  assert MLDSA.verify(v.publicKey, otherMessage, signature, otherContext) == #ok(false);
  assert MLDSA.verifyPrepared(publicKey, otherMessage, signature, otherContext) == #ok(false);
};

// Repeated hedged calls share all four immutable Blob inputs.
// This also exercises argument aliasing through both compiler bindings.
let aliased = unwrap(MLDSA.signRandomized(v.seed, v.seed, v.seed, v.seed));
assert MLDSA.signRandomizedPrepared(secretKey, v.seed, v.seed, v.seed) == #ok(aliased);
assert MLDSA.signRandomized(v.seed, v.seed, v.seed, v.seed) == #ok(aliased);
assert MLDSA.verify(v.publicKey, v.seed, aliased, v.seed) == #ok(true);
assert MLDSA.verifyPrepared(publicKey, v.seed, aliased, v.seed) == #ok(true);

// A 255-byte binary context is valid; appending one byte gives a typed error.
// The official 255-byte-context corpus already supplies independent answers;
// this checks framing after NUL bytes and validation before randomness errors.
let context255 = filled(255, 0);
let boundary = unwrap(MLDSA.signPrepared(secretKey, "", context255));
assert MLDSA.sign(v.seed, "", context255) == #ok(boundary);
assert MLDSA.verify(v.publicKey, "", boundary, context255) == #ok(true);
assert MLDSA.verifyPrepared(publicKey, "", boundary, context255) == #ok(true);
assert MLDSA.verifyPrepared(publicKey, "", boundary, filled(254, 0)) == #ok(false);
let context256 = filled(256, 0);
assert MLDSA.signRandomized(v.seed, "", context256, "") == #err(#invalidContext);
assert MLDSA.signRandomizedPrepared(secretKey, "", context256, "") == #err(#invalidContext);
assert MLDSA.verify(v.publicKey, "", boundary, context256) == #err(#invalidContext);
assert MLDSA.verifyPrepared(publicKey, "", boundary, context256) == #err(#invalidContext);
assert MLDSA.signPrepared(secretKey, v.message, v.context) == #ok(v.signature);
